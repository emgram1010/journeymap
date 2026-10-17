import assert from 'node:assert/strict';
import test from 'node:test';
import {
  isValidScheduledDuration,
  defaultBlockDuration,
  isValidTweakReason,
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
