import assert from 'node:assert/strict';
import test from 'node:test';
import {healthStatus, HEARTBEAT_STALE_MS} from './healthStatus';

test('UT-OBS-1-06: green when the heartbeat is fresh and there are no open issues', () => {
  const result = healthStatus(0, 0);
  assert.equal(result.level, 'green');
});

test('UT-OBS-1-06: green at exactly the 15-minute boundary', () => {
  const result = healthStatus(HEARTBEAT_STALE_MS, 0);
  assert.equal(result.level, 'green');
});

test('UT-OBS-1-06: red one millisecond past the 15-minute boundary', () => {
  const result = healthStatus(HEARTBEAT_STALE_MS + 1, 0);
  assert.equal(result.level, 'red');
});

test('UT-OBS-1-06: red when there has never been a heartbeat', () => {
  const result = healthStatus(null, 0);
  assert.equal(result.level, 'red');
});

test('UT-OBS-1-06: amber when the heartbeat is fresh but issues are open', () => {
  const result = healthStatus(60_000, 3);
  assert.equal(result.level, 'amber');
  assert.match(result.reason, /3 open issues/);
});

test('UT-OBS-1-06: a stale heartbeat always wins over open issues (red, not amber)', () => {
  const result = healthStatus(HEARTBEAT_STALE_MS + 1, 5);
  assert.equal(result.level, 'red');
});

test('singular wording for exactly one open issue', () => {
  const result = healthStatus(0, 1);
  assert.match(result.reason, /1 open issue\./);
});
