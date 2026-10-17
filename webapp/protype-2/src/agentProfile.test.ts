import assert from 'node:assert/strict';
import test from 'node:test';
import {isValidColorHex, isValidCapacityHours, isValidProfileName} from './agentProfile';

// ── UT-PLAN-2-02: isValidColorHex ──────────────────────────────────────────

test('UT-PLAN-2-02: a full 6-digit hex color is valid', () => {
  assert.equal(isValidColorHex('#4f46e5'), true);
  assert.equal(isValidColorHex('#FFFFFF'), true);
});

test('UT-PLAN-2-02: empty/null/undefined are valid (color is optional)', () => {
  assert.equal(isValidColorHex(''), true);
  assert.equal(isValidColorHex(null), true);
  assert.equal(isValidColorHex(undefined), true);
});

test('UT-PLAN-2-02: a color name, a 3-digit shorthand, or a non-string is invalid', () => {
  assert.equal(isValidColorHex('blue'), false);
  assert.equal(isValidColorHex('#fff'), false);
  assert.equal(isValidColorHex(123), false);
  assert.equal(isValidColorHex('4f46e5'), false); // missing '#'
});

// ── UT-PLAN-2-01: isValidCapacityHours ─────────────────────────────────────

test('UT-PLAN-2-01: a positive number of hours is valid', () => {
  assert.equal(isValidCapacityHours(8), true);
  assert.equal(isValidCapacityHours(0.5), true);
  assert.equal(isValidCapacityHours(24), true);
});

test('UT-PLAN-2-01: zero, negative, non-finite, or non-numeric is invalid', () => {
  assert.equal(isValidCapacityHours(0), false);
  assert.equal(isValidCapacityHours(-1), false);
  assert.equal(isValidCapacityHours(Infinity), false);
  assert.equal(isValidCapacityHours(NaN), false);
  assert.equal(isValidCapacityHours('8'), false);
});

// ── isValidProfileName ──────────────────────────────────────────────────

test('a person profile (user_id != 0) never needs a name', () => {
  assert.equal(isValidProfileName('', 2), true);
  assert.equal(isValidProfileName(undefined, 2), true);
});

test('an AI profile (user_id = 0) needs a non-blank name', () => {
  assert.equal(isValidProfileName('Route Optimizer Bot', 0), true);
  assert.equal(isValidProfileName('', 0), false);
  assert.equal(isValidProfileName('   ', 0), false);
  assert.equal(isValidProfileName(undefined, 0), false);
});
