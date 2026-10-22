import assert from 'node:assert/strict';
import test from 'node:test';
import {
  isValidScheduledDuration,
  defaultBlockDuration,
  isValidTweakReason,
  groupStepsBySlot,
  linkedCardTitle,
  MIN_SCHEDULED_MINUTES,
  MAX_SCHEDULED_MINUTES,
} from './scheduleModel';

test('UT-SCHED-1-08: tweak validation accepts only whole minutes in 1..1440', () => {
  // The epic's exact row: 0, -3, 7.5, "x", 45
  assert.equal(isValidScheduledDuration(0), false);
  assert.equal(isValidScheduledDuration(-3), false);
  assert.equal(isValidScheduledDuration(7.5), false);
  assert.equal(isValidScheduledDuration('x' as unknown), false);
  assert.equal(isValidScheduledDuration(45), true);
});

test('UT-SCHED-1-08: the boundaries themselves are allowed', () => {
  assert.equal(isValidScheduledDuration(MIN_SCHEDULED_MINUTES), true);
  assert.equal(isValidScheduledDuration(MAX_SCHEDULED_MINUTES), true);
  assert.equal(isValidScheduledDuration(MAX_SCHEDULED_MINUTES + 1), false);
});

test('UT-SCHED-1-G01: junk never passes the duration rule', () => {
  for (const junk of [null, undefined, '', '45', NaN, Infinity, -Infinity, {}, [], true]) {
    assert.equal(isValidScheduledDuration(junk as unknown), false, `expected ${String(junk)} to be rejected`);
  }
});

test('UT-SCHED-1-06: defaultBlockDuration sums the known durations', () => {
  const r = defaultBlockDuration([
    {stage_key: 's1', lens_key: 'sales', expected_minutes: 15},
    {stage_key: 's2', lens_key: 'ops', expected_minutes: 30},
  ]);
  assert.equal(r.minutes, 45);
  assert.deepEqual(r.missing, []);
});

test('UT-SCHED-1-06: a task with no duration is reported, not guessed', () => {
  const r = defaultBlockDuration([
    {stage_key: 's1', lens_key: 'sales', expected_minutes: 15},
    {stage_key: 's2', lens_key: 'ops', expected_minutes: null},
    {stage_key: 's3', lens_key: 'ops'},
  ]);
  // The sum is of what is actually known...
  assert.equal(r.minutes, 15);
  // ...and the planner is told exactly which steps had no estimate.
  assert.deepEqual(r.missing, ['s2/ops', 's3/ops']);
});

test('UT-SCHED-1-06: zero is treated as missing, not as a real estimate', () => {
  // An untouched decimal column reads as 0 in this workspace
  // (CLAUDE.md), so 0 means "nobody filled this in", not "instant".
  const r = defaultBlockDuration([{stage_key: 's1', lens_key: 'sales', expected_minutes: 0}]);
  assert.equal(r.minutes, 0);
  assert.deepEqual(r.missing, ['s1/sales']);
});

test('UT-SCHED-1-06: an empty block sums to zero with nothing missing', () => {
  assert.deepEqual(defaultBlockDuration([]), {minutes: 0, missing: []});
});

test('tweak reason: optional, "other", or a key the job really has', () => {
  const keys = ['customer_name', 'order_ref'];

  // Not giving a reason is fine — the reason is optional.
  assert.equal(isValidTweakReason(null, keys), true);
  assert.equal(isValidTweakReason(undefined, keys), true);
  assert.equal(isValidTweakReason('', keys), true);

  assert.equal(isValidTweakReason('other', keys), true);
  assert.equal(isValidTweakReason('order_ref', keys), true);

  // A reason pointing at an attribute the job does not have would be
  // a dead reference the moment anyone tried to read it.
  assert.equal(isValidTweakReason('made_up_key', keys), false);
  assert.equal(isValidTweakReason('Other', keys), false);
});

test('tweak reason: a job with no attributes still allows "other"', () => {
  assert.equal(isValidTweakReason('other', []), true);
  assert.equal(isValidTweakReason('anything', []), false);
});

// ── BLK-1 (US-BLK-1-07) ────────────────────────────────────

const step = (
  plannerTaskId: number,
  workTaskId: number,
  position: number | null | undefined,
  extra: {stage_key?: string; step_title?: string | null; job_title?: string | null} = {},
) => ({
  planner_task_id: plannerTaskId,
  work_task_id: workTaskId,
  position,
  stage_key: extra.stage_key ?? `s${workTaskId}`,
  step_title: extra.step_title ?? null,
  job_title: extra.job_title ?? null,
});

test('UT-BLK-1-12: two steps of one slot group into one card, in position order', () => {
  const slots = groupStepsBySlot([step(9, 77, 2), step(9, 75, 1)]);

  assert.equal(slots.length, 1);
  assert.equal(slots[0].plannerTaskId, 9);
  assert.equal(slots[0].stepCount, 2);
  assert.deepEqual(
    slots[0].steps.map((s) => s.work_task_id),
    [75, 77],
    'position decides the order, not the order the board happened to return',
  );
});

test('UT-BLK-1-13: a step is never dropped, even with a missing or duplicate position', () => {
  // The bug this replaces lost every step but one. Losing a step would
  // hide work that really is on somebody's day.
  const slots = groupStepsBySlot([
    step(9, 75, 1),
    step(9, 76, null),
    step(9, 77, 1),
    step(9, 78, 0),
  ]);

  assert.equal(slots.length, 1);
  assert.equal(slots[0].stepCount, 4);
  assert.deepEqual(
    slots[0].steps.map((s) => s.work_task_id),
    [75, 77, 76, 78],
    'positioned steps first in position order, ties and unpositioned ones in arrival order',
  );
});

test('UT-BLK-1-14: several slots keep first-appearance order and never mix', () => {
  const slots = groupStepsBySlot([
    step(11, 90, 1),
    step(9, 75, 1),
    step(11, 91, 2),
    step(9, 77, 2),
  ]);

  assert.deepEqual(
    slots.map((s) => s.plannerTaskId),
    [11, 9],
    "the board's own ordering survives the grouping",
  );
  assert.deepEqual(slots[0].steps.map((s) => s.work_task_id), [90, 91]);
  assert.deepEqual(slots[1].steps.map((s) => s.work_task_id), [75, 77]);
});

test('UT-BLK-1-15: an empty list groups to nothing', () => {
  assert.deepEqual(groupStepsBySlot([]), []);
});

test('UT-BLK-1-16: a one-step slot still reads as its step', () => {
  assert.equal(
    linkedCardTitle([step(9, 75, 1, {step_title: 'Log the enquiry', job_title: 'Garcia party'})]),
    'Log the enquiry',
  );

  // No text in the version for that cell: fall back to job and stage,
  // never a blank card.
  assert.equal(
    linkedCardTitle([step(9, 75, 1, {step_title: null, job_title: 'Garcia party', stage_key: 's1'})]),
    'Garcia party — s1',
  );
});

test('UT-BLK-1-17: a multi-step slot is named as a card, not as its first stage', () => {
  // Naming it "Receive the return" would be the old bug with a stable
  // order instead of an arbitrary one — the planner would still think
  // the slot was one stage of the work.
  assert.equal(
    linkedCardTitle([
      step(9, 75, 1, {step_title: 'Receive the return', job_title: 'Garcia party'}),
      step(9, 77, 2, {step_title: 'File the paperwork', job_title: 'Garcia party'}),
    ]),
    'Garcia party · 2 steps',
  );

  assert.equal(linkedCardTitle([]), null, 'nothing to name means no made-up string');
});
