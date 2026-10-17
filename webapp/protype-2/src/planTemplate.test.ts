import assert from 'node:assert/strict';
import test from 'node:test';
import {
  windowEnd,
  isValidStartTime,
  isValidWindowDays,
  MIN_WINDOW_DAYS,
  MAX_WINDOW_DAYS,
} from './planTemplate';

test('UT-PLAN-1-01: windowEnd(start, 14) is start + 13 days', () => {
  // Inclusive of both ends: a fortnight is 14 days, not 15.
  assert.equal(windowEnd('2026-10-14', 14), '2026-10-27');
  assert.equal(windowEnd('2026-01-01', 14), '2026-01-14');
});

test('UT-PLAN-1-01: a 1-day window starts and ends the same day', () => {
  assert.equal(windowEnd('2026-10-14', 1), '2026-10-14');
});

test('UT-PLAN-1-02: windowEnd crosses a month boundary', () => {
  assert.equal(windowEnd('2026-01-25', 14), '2026-02-07');
  // 30-day September into October.
  assert.equal(windowEnd('2026-09-30', 2), '2026-10-01');
});

test('UT-PLAN-1-02: windowEnd crosses a year boundary', () => {
  assert.equal(windowEnd('2026-12-26', 14), '2027-01-08');
  assert.equal(windowEnd('2026-12-31', 1), '2026-12-31');
  assert.equal(windowEnd('2026-12-31', 2), '2027-01-01');
});

test('UT-PLAN-1-02: windowEnd handles the leap day in both directions', () => {
  // 2028 is a leap year: February has 29 days, so a window spanning it
  // lands a day later than the same window in a common year.
  assert.equal(windowEnd('2028-02-27', 3), '2028-02-29');
  assert.equal(windowEnd('2028-02-28', 2), '2028-02-29');
  assert.equal(windowEnd('2028-02-28', 3), '2028-03-01');

  // 2027 is not a leap year — the same start skips straight to March.
  assert.equal(windowEnd('2027-02-28', 2), '2027-03-01');

  // 2100 is divisible by 4 but NOT a leap year (century rule).
  assert.equal(windowEnd('2100-02-28', 2), '2100-03-01');

  // 2000 WAS a leap year (divisible by 400).
  assert.equal(windowEnd('2000-02-28', 2), '2000-02-29');
});

test('UT-PLAN-1-02: a full 366-day window lands correctly', () => {
  // 2028 is a leap year, so 366 days from Jan 1 is Dec 31 of the same year.
  assert.equal(windowEnd('2028-01-01', 366), '2028-12-31');
  // 2026 is not, so 366 days from Jan 1 spills into the next year.
  assert.equal(windowEnd('2026-01-01', 366), '2027-01-01');
});

test('UT-PLAN-1-02: windowEnd rejects a malformed start or window', () => {
  assert.throws(() => windowEnd('14/10/2026', 14), /YYYY-MM-DD/);
  assert.throws(() => windowEnd('2026-10-14', 0), /whole number/);
  assert.throws(() => windowEnd('2026-10-14', -3), /whole number/);
  assert.throws(() => windowEnd('2026-10-14', 1.5), /whole number/);
});

test('UT-PLAN-1-03: isValidStartTime accepts only two-digit HH:MM', () => {
  assert.equal(isValidStartTime('08:00'), true);
  assert.equal(isValidStartTime('00:00'), true);
  assert.equal(isValidStartTime('23:59'), true);

  // Rejected on purpose: unambiguous to a person, but it gives the same
  // time of day two spellings in the database.
  assert.equal(isValidStartTime('8:00'), false);

  assert.equal(isValidStartTime('25:00'), false);
  assert.equal(isValidStartTime('23:60'), false);
  assert.equal(isValidStartTime(''), false);
});

test('UT-PLAN-1-03: isValidStartTime rejects non-strings and near-misses', () => {
  assert.equal(isValidStartTime(null), false);
  assert.equal(isValidStartTime(undefined), false);
  assert.equal(isValidStartTime(800), false);
  assert.equal(isValidStartTime(' 08:00'), false);
  assert.equal(isValidStartTime('08:00 '), false);
  assert.equal(isValidStartTime('08:00:00'), false);
});

test('UT-PLAN-1-G01: isValidWindowDays enforces the 1–366 range', () => {
  assert.equal(isValidWindowDays(MIN_WINDOW_DAYS), true);
  assert.equal(isValidWindowDays(14), true);
  assert.equal(isValidWindowDays(MAX_WINDOW_DAYS), true);

  assert.equal(isValidWindowDays(0), false);
  assert.equal(isValidWindowDays(-1), false);
  assert.equal(isValidWindowDays(367), false);
  assert.equal(isValidWindowDays(14.5), false);
  assert.equal(isValidWindowDays('14'), false);
  assert.equal(isValidWindowDays(null), false);
  assert.equal(isValidWindowDays(NaN), false);
});
