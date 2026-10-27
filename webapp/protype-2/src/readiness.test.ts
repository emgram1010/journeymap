import assert from 'node:assert/strict';
import test from 'node:test';
import {computeStageReadiness, computeMapReadiness} from './readiness';
import type {ReadinessLensInput, ReadinessStageInput, ReadinessCellInput} from './readiness';
import map178Fixture from './fixtures/readiness-golden.json';

const workLens: ReadinessLensInput = {key: 'owner', actorType: 'internal'};
const customerLens: ReadinessLensInput = {key: 'customer', actorType: 'customer'};
const otherWorkLens: ReadinessLensInput = {key: 'other-worker', actorType: 'internal'};

const readyStage: ReadinessStageInput = {key: 's1', label: 'Stage 1', ownerLensKey: 'owner'};
const readyOwnerCell: ReadinessCellInput = {
  lensKey: 'owner',
  task: 'Do the thing',
  durationValue: 15,
  durationUnit: 'minutes',
  hasAnyContent: true,
};

test('UT-AUTH-1-01: fully ready stage has ready=true and no reasons', () => {
  const result = computeStageReadiness(readyStage, [workLens], [readyOwnerCell]);
  assert.deepEqual(result, {ready: true, reasons: []});
});

test('UT-AUTH-1-02: stage with no owner reports NO_OWNER', () => {
  const stage: ReadinessStageInput = {key: 's1', label: 'Stage 1', ownerLensKey: null};
  const result = computeStageReadiness(stage, [workLens], []);
  assert.ok(result.reasons.includes('NO_OWNER'));
  assert.equal(result.ready, false);
});

test('UT-AUTH-1-03: owner row with "does planned work?" off reports OWNER_NOT_WORK_ROLE', () => {
  const result = computeStageReadiness(readyStage, [customerLens], []); // owner key "owner" doesn't resolve -> treated as not a work role
  assert.ok(result.reasons.includes('OWNER_NOT_WORK_ROLE'));
});

test('owner row explicitly switched off (internal type, override false) reports OWNER_NOT_WORK_ROLE', () => {
  const lens: ReadinessLensInput = {key: 'owner', actorType: 'internal', doesPlannedWorkOverride: false};
  const result = computeStageReadiness(readyStage, [lens], [readyOwnerCell]);
  assert.ok(result.reasons.includes('OWNER_NOT_WORK_ROLE'));
});

test('UT-AUTH-1-04: owner cell missing task reports NO_TASK', () => {
  const cell: ReadinessCellInput = {...readyOwnerCell, task: null};
  const result = computeStageReadiness(readyStage, [workLens], [cell]);
  assert.ok(result.reasons.includes('NO_TASK'));
  assert.ok(!result.reasons.includes('NO_DURATION'));
});

test('UT-AUTH-1-05: owner cell has duration value but no unit reports NO_DURATION', () => {
  const cell: ReadinessCellInput = {...readyOwnerCell, durationUnit: null};
  const result = computeStageReadiness(readyStage, [workLens], [cell]);
  assert.ok(result.reasons.includes('NO_DURATION'));
});

test('UT-AUTH-1-06: duration of 0 minutes is valid, not null', () => {
  const cell: ReadinessCellInput = {...readyOwnerCell, durationValue: 0, durationUnit: 'minutes'};
  const result = computeStageReadiness(readyStage, [workLens], [cell]);
  assert.ok(!result.reasons.includes('NO_DURATION'));
});

test('UT-AUTH-1-07: non-owner work cell with only notes/task filled (no duration) reports PARTIAL_WORK_CELL', () => {
  const otherCell: ReadinessCellInput = {
    lensKey: 'other-worker',
    task: 'Partially started',
    durationValue: null,
    durationUnit: null,
    hasAnyContent: true,
  };
  const result = computeStageReadiness(readyStage, [workLens, otherWorkLens], [readyOwnerCell, otherCell]);
  assert.ok(result.reasons.includes('PARTIAL_WORK_CELL'));
});

test('UT-AUTH-1-08: non-owner work cell completely empty reports no reason', () => {
  const result = computeStageReadiness(readyStage, [workLens, otherWorkLens], [readyOwnerCell]);
  assert.deepEqual(result, {ready: true, reasons: []});
});

test('UT-AUTH-1-09: customer-type cells are never required, empty or filled', () => {
  const emptyCustomerCell: ReadinessCellInput = {lensKey: 'customer', hasAnyContent: false};
  const filledCustomerCell: ReadinessCellInput = {
    lensKey: 'customer',
    task: null,
    durationValue: null,
    durationUnit: null,
    hasAnyContent: true,
  };
  const r1 = computeStageReadiness(readyStage, [workLens, customerLens], [readyOwnerCell, emptyCustomerCell]);
  const r2 = computeStageReadiness(readyStage, [workLens, customerLens], [readyOwnerCell, filledCustomerCell]);
  assert.equal(r1.ready, true);
  assert.equal(r2.ready, true);
});

test('UT-AUTH-1-10: zero stages reports NO_STAGES; empty work type name reports NO_WORK_TYPE_NAME', () => {
  const result = computeMapReadiness({workTypeName: ''}, [], [workLens], {});
  assert.ok(result.mapReasons.includes('NO_STAGES'));
  assert.ok(result.mapReasons.includes('NO_WORK_TYPE_NAME'));
  assert.equal(result.ready, false);
});

test('UT-AUTH-1-11: readyCount/total over mixed stages is correct', () => {
  const stage2: ReadinessStageInput = {key: 's2', label: 'Stage 2', ownerLensKey: 'owner'};
  const result = computeMapReadiness(
    {workTypeName: 'Test'},
    [readyStage, stage2],
    [workLens],
    {s1: [readyOwnerCell], s2: []},
  );
  assert.equal(result.total, 2);
  assert.equal(result.readyCount, 1);
  assert.equal(result.ready, false);
});

test('UT-AUTH-1-12: same input twice gives the same result; inputs are never mutated', () => {
  const lenses = [workLens];
  const cells = [readyOwnerCell];
  const frozenStage = Object.freeze({...readyStage});
  const frozenLenses = Object.freeze([...lenses]);
  const frozenCells = Object.freeze([...cells]);
  const r1 = computeStageReadiness(frozenStage, frozenLenses, frozenCells);
  const r2 = computeStageReadiness(frozenStage, frozenLenses, frozenCells);
  assert.deepEqual(r1, r2);
});

test('UT-AUTH-1-13: map 178 golden — stages 1-4 and 7 (customer-owned) report OWNER_NOT_WORK_ROLE', () => {
  const fixture = map178Fixture.map178;
  const result = computeMapReadiness(
    {workTypeName: fixture.workTypeName},
    fixture.stages,
    fixture.lenses as ReadinessLensInput[],
    fixture.cellsByStage,
  );

  for (const key of fixture.expectOwnerNotWorkRole) {
    const stageResult = result.perStage.find((s) => s.stageKey === key);
    assert.ok(stageResult, `missing perStage entry for ${key}`);
    assert.ok(
      stageResult!.reasons.includes('OWNER_NOT_WORK_ROLE'),
      `${key} should report OWNER_NOT_WORK_ROLE, got ${stageResult!.reasons.join(', ')}`,
    );
  }

  for (const key of fixture.expectNotOwnerNotWorkRole) {
    const stageResult = result.perStage.find((s) => s.stageKey === key);
    assert.ok(stageResult, `missing perStage entry for ${key}`);
    assert.ok(
      !stageResult!.reasons.includes('OWNER_NOT_WORK_ROLE'),
      `${key} should NOT report OWNER_NOT_WORK_ROLE, got ${stageResult!.reasons.join(', ')}`,
    );
  }
});

// ── EXC-1 (US-EXC-1-01) — exception-link warnings ─────────────────────────
import exceptionGolden from './fixtures/exception-readiness-golden.json';
import {exceptionLinkWarnings, type ExceptionTargetInput} from './readiness';

for (const c of exceptionGolden.cases) {
  test(`${c.id}: ${c.name}`, () => {
    const result = exceptionLinkWarnings(c.sourceHasItemsRow, c.targets as ExceptionTargetInput[]);
    assert.deepEqual(result, c.expected);
  });
}
