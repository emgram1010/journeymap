// EXEC-1 US-EXEC-1-01 — every TaskStatus has a label, an icon and both
// color forms, and STATUS_CONFIG has no extra keys beyond the 5 fixed
// statuses (LOG-1's status engine is the one source of truth for which
// statuses exist; this file must never drift from it).
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {STATUS_CONFIG, ALL_STATUSES} from './statusConfig';

test('every status has a non-empty label, an icon, a pill class and a ring color', () => {
  for (const status of ALL_STATUSES) {
    const config = STATUS_CONFIG[status];
    assert.ok(config, `missing config for ${status}`);
    assert.ok(config.label.trim().length > 0, `${status} has an empty label`);
    assert.ok(config.icon, `${status} has no icon`);
    assert.ok(config.pillClassName.trim().length > 0, `${status} has no pill class`);
    assert.match(config.ringColor, /^#[0-9a-f]{6}$/i, `${status} ring color isn't a hex string`);
  }
});

test('STATUS_CONFIG has exactly the 5 fixed statuses, no more, no less', () => {
  const keys = Object.keys(STATUS_CONFIG).sort();
  assert.deepEqual(keys, [...ALL_STATUSES].sort());
});

test('no two statuses share the same pill class (so they stay visually distinct)', () => {
  const classes = ALL_STATUSES.map((s) => STATUS_CONFIG[s].pillClassName);
  assert.equal(new Set(classes).size, classes.length);
});
