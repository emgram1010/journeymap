import assert from 'node:assert/strict';
import test from 'node:test';
import {groupIssues, type OpsEvent} from './groupIssues';

function event(partial: Partial<OpsEvent>): OpsEvent {
  return {feature: 'PUB-1', step: 'publish_version', error_code: 'E-PUB-001', created_at: '2026-01-01T00:00:00Z', ...partial};
}

test('UT-OBS-1-08: groups repeated events into one issue with the right count', () => {
  const events: OpsEvent[] = [
    event({created_at: '2026-01-01T00:00:00Z'}),
    event({created_at: '2026-01-01T00:05:00Z'}),
    event({created_at: '2026-01-01T00:10:00Z'}),
  ];
  const issues = groupIssues(events);
  assert.equal(issues.length, 1);
  assert.equal(issues[0].count, 3);
});

test('UT-OBS-1-08: first_seen and last_seen reflect the earliest and latest events', () => {
  const events: OpsEvent[] = [
    event({created_at: '2026-01-01T00:00:00Z', message: 'first'}),
    event({created_at: '2026-01-02T00:00:00Z', message: 'last'}),
  ];
  const issues = groupIssues(events);
  assert.equal(issues[0].first_seen, '2026-01-01T00:00:00Z');
  assert.equal(issues[0].last_seen, '2026-01-02T00:00:00Z');
  assert.equal(issues[0].latest_message, 'last');
});

test('different feature/step/error_code combinations stay separate issues', () => {
  const events: OpsEvent[] = [
    event({feature: 'PUB-1', step: 'publish_version', error_code: 'E-PUB-001'}),
    event({feature: 'PUB-1', step: 'publish_version', error_code: 'E-PUB-002'}),
    event({feature: 'LOG-1', step: 'record_event', error_code: 'E-PUB-001'}),
  ];
  const issues = groupIssues(events);
  assert.equal(issues.length, 3);
});

test('returns an empty array for no events', () => {
  assert.deepEqual(groupIssues([]), []);
});

test('issues are returned in first-seen order', () => {
  const events: OpsEvent[] = [
    event({feature: 'A', step: 's1', error_code: 'E-A-001', created_at: '2026-01-01T00:00:00Z'}),
    event({feature: 'B', step: 's2', error_code: 'E-B-001', created_at: '2026-01-01T00:01:00Z'}),
    event({feature: 'A', step: 's1', error_code: 'E-A-001', created_at: '2026-01-01T00:02:00Z'}),
  ];
  const issues = groupIssues(events);
  assert.equal(issues[0].feature, 'A');
  assert.equal(issues[1].feature, 'B');
  assert.equal(issues.length, 2);
});
