import assert from 'node:assert/strict';
import test from 'node:test';
import {startOverrideChange, START_OVERRIDE_FORMAT_MESSAGE} from './startOverrideModel';

const computed = {planned_start: '08:00', startOverride: ''};
const pinned = {planned_start: '14:30', startOverride: '14:30'};

test('UT-SCHED-2-03-01: untouched field = no change', () => {
  assert.deepEqual(startOverrideChange(computed, '08:00', false, false), {kind: 'none'});
  assert.deepEqual(startOverrideChange(pinned, '14:30', false, false), {kind: 'none'});
});

test('UT-SCHED-2-03-02: a new time on a computed step sets an override', () => {
  assert.deepEqual(startOverrideChange(computed, '10:15', false, false), {kind: 'set', value: '10:15'});
});

test('UT-SCHED-2-03-03: a new time on an already-pinned step replaces it', () => {
  assert.deepEqual(startOverrideChange(pinned, '15:00', false, false), {kind: 'set', value: '15:00'});
});

test('UT-SCHED-2-03-04: "use computed time" clears an existing override', () => {
  assert.deepEqual(startOverrideChange(pinned, '14:30', true, false), {kind: 'clear'});
});

test('UT-SCHED-2-03-05: "use computed time" on a step with no override is a no-op', () => {
  assert.deepEqual(startOverrideChange(computed, '08:00', true, false), {kind: 'none'});
});

test('UT-SCHED-2-03-06: a backlog step never changes its start', () => {
  assert.deepEqual(startOverrideChange({planned_start: '', startOverride: ''}, '09:00', false, true), {kind: 'none'});
});

test('UT-SCHED-2-03-07: an empty or malformed time is refused with the server\'s own message (E-SCHED-009)', () => {
  for (const bad of ['', '9:00', '24:00', '12:60', '2:30pm']) {
    assert.deepEqual(startOverrideChange(computed, bad, false, false), {kind: 'invalid', message: START_OVERRIDE_FORMAT_MESSAGE}, bad);
  }
});

test('UT-SCHED-2-03-08: surrounding spaces are ignored', () => {
  assert.deepEqual(startOverrideChange(computed, ' 10:15 ', false, false), {kind: 'set', value: '10:15'});
});
