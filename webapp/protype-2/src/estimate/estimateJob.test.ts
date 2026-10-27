import assert from 'node:assert/strict';
import test from 'node:test';
import {estimateJob} from './estimateJob';
import type {EstimateSnapshot, EstimateLine} from './estimateJob';
import golden from '../fixtures/estimate-golden.json';

function stageOf(result: ReturnType<typeof estimateJob>, stageKey: string) {
  const s = result.stages.find((st) => st.stage_key === stageKey);
  assert.ok(s, `stage ${stageKey} not found`);
  return s!;
}

test('UT-EST-1-01: a real order over 8 stages matches the hand calculation, complete', () => {
  const g = golden.simpleOrder;
  const result = estimateJob(g.snapshot as EstimateSnapshot, g.lines as EstimateLine[]);
  assert.equal(result.has_items_row, true);
  assert.equal(result.complete, true);
  assert.deepEqual(result.missing, []);
  assert.deepEqual(result.reasons, []);
  assert.equal(result.total_minutes, g.expected.total_minutes);
  for (const [stageKey, total] of Object.entries(g.expected.stage_totals)) {
    assert.equal(stageOf(result, stageKey).total_minutes, total, `stage ${stageKey}`);
  }
  // s7 has no owner cell at all in the fixture -> baseline 0, not an error.
  assert.equal(stageOf(result, 's7').baseline_minutes, g.expected.s7_no_cell_baseline);
});

test('UT-EST-1-02: two different orders on the same map give different, correct per-stage totals', () => {
  const g = golden.twoOrders;
  const a = estimateJob(g.snapshot as EstimateSnapshot, g.orderA.lines as EstimateLine[]);
  const b = estimateJob(g.snapshot as EstimateSnapshot, g.orderB.lines as EstimateLine[]);
  assert.equal(stageOf(a, 's8').total_minutes, g.orderA.expected_s8_total);
  assert.equal(stageOf(b, 's8').total_minutes, g.orderB.expected_s8_total);
});

test('UT-EST-1-03: two methods at one stage sum, and by_method carries both entries', () => {
  const g = golden.twoMethods;
  const result = estimateJob(g.snapshot as EstimateSnapshot, g.lines as EstimateLine[]);
  const s8 = stageOf(result, 's8');
  assert.equal(s8.total_minutes, g.expected.s8_total_minutes);
  assert.equal(s8.variable_minutes, g.expected.s8_variable_minutes);
  assert.deepEqual(s8.by_method, g.expected.by_method);
});

test('UT-EST-1-04: a line with no matching rate is reported missing, and the stage falls back to baseline only', () => {
  const g = golden.missingRate;
  const result = estimateJob(g.snapshot as EstimateSnapshot, g.lines as EstimateLine[]);
  assert.equal(result.complete, g.expected.complete);
  assert.equal(stageOf(result, 's2').total_minutes, g.expected.s2_total_minutes);
  assert.deepEqual(result.missing, g.expected.missing);
});

test('UT-EST-1-05: an Items row with zero lines is incomplete with reason no_lines', () => {
  const g = golden.noLines;
  const result = estimateJob(g.snapshot as EstimateSnapshot, g.lines as EstimateLine[]);
  assert.equal(result.complete, g.expected.complete);
  assert.deepEqual(result.reasons, g.expected.reasons);
  assert.deepEqual(result.missing, g.expected.missing);
  assert.equal(stageOf(result, 's2').total_minutes, g.expected.s2_total_minutes);
});

test('UT-EST-1-06: a map with no Items row is always per_order and complete, lines ignored', () => {
  const g = golden.noItemsRow;
  const result = estimateJob(g.snapshot as EstimateSnapshot, g.lines as EstimateLine[]);
  assert.equal(result.has_items_row, g.expected.has_items_row);
  assert.equal(result.complete, g.expected.complete);
  assert.equal(result.total_minutes, g.expected.total_minutes);
  assert.equal(stageOf(result, 's1').scales_with, 'per_order');
});

test('UT-EST-1-07: per_flagged_unit contributes 0 until flagged, then flagged_quantity x rate; never missing while 0', () => {
  const g = golden.perFlagged;
  const zero = estimateJob(g.snapshot as EstimateSnapshot, g.zeroFlagged.lines as EstimateLine[]);
  assert.equal(stageOf(zero, 's3').total_minutes, g.zeroFlagged.expected.s3_total_minutes);
  assert.deepEqual(zero.missing, g.zeroFlagged.expected.missing);
  assert.equal(zero.complete, g.zeroFlagged.expected.complete);

  const three = estimateJob(g.snapshot as EstimateSnapshot, g.threeFlagged.lines as EstimateLine[]);
  assert.equal(stageOf(three, 's3').total_minutes, g.threeFlagged.expected.s3_total_minutes);
  assert.deepEqual(three.missing, g.threeFlagged.expected.missing);

  // D-IR-16 also covers an item with NO rate at all, while nothing is flagged.
  const noRate = estimateJob(g.snapshot as EstimateSnapshot, g.zeroFlaggedNoRate.lines as EstimateLine[]);
  assert.equal(stageOf(noRate, 's3').total_minutes, g.zeroFlaggedNoRate.expected.s3_total_minutes);
  assert.deepEqual(noRate.missing, g.zeroFlaggedNoRate.expected.missing);
});

test('UT-EST-1-08: a stage sum of 19.5 rounds half-up to 20', () => {
  const g = golden.simpleOrder;
  const result = estimateJob(g.snapshot as EstimateSnapshot, g.lines as EstimateLine[]);
  const s2 = stageOf(result, 's2');
  assert.equal(s2.baseline_minutes, g.expected.s2.baseline_minutes);
  assert.equal(s2.variable_minutes, g.expected.s2.variable_minutes);
  assert.equal(s2.total_minutes, g.expected.s2.total_minutes);
});

test('UT-EST-1-09: source is measured only when every rate used is measured, seed the moment one is, n/a when none is used', () => {
  const allMeasured = estimateJob(golden.source.allMeasured.snapshot as EstimateSnapshot, golden.source.allMeasured.lines as EstimateLine[]);
  assert.equal(stageOf(allMeasured, 's1').source, golden.source.allMeasured.expected_source);

  const oneSeed = estimateJob(golden.source.oneSeed.snapshot as EstimateSnapshot, golden.source.oneSeed.lines as EstimateLine[]);
  assert.equal(stageOf(oneSeed, 's1').source, golden.source.oneSeed.expected_source);

  const none = estimateJob(golden.source.none.snapshot as EstimateSnapshot, golden.source.none.lines as EstimateLine[]);
  assert.equal(stageOf(none, 's1').source, golden.source.none.expected_source);
});

test('UT-EST-1-G01: a junk-shaped snapshot never throws — missing cells/scaling/rates default safely', () => {
  const bare: EstimateSnapshot = {schema_version: 2, stages: [{key: 's1', owner_lens_key: 'nobody'}], cells: []};
  assert.doesNotThrow(() => estimateJob(bare, []));
  const result = estimateJob(bare, []);
  assert.equal(result.stages[0].baseline_minutes, 0);
  assert.equal(result.stages[0].scales_with, 'per_order');
});

test('deep-check: the s8 stage in the golden order matches the epic\'s own worked sample exactly', () => {
  const g = golden.simpleOrder;
  const result = estimateJob(g.snapshot as EstimateSnapshot, g.lines as EstimateLine[]);
  const s8 = stageOf(result, 's8');
  assert.equal(s8.baseline_minutes, g.expected.s8.baseline_minutes);
  assert.equal(s8.variable_minutes, g.expected.s8.variable_minutes);
  assert.equal(s8.total_minutes, g.expected.s8.total_minutes);
  assert.deepEqual(s8.by_method, g.expected.s8.by_method);
  assert.equal(s8.source, g.expected.s8.source);
});
