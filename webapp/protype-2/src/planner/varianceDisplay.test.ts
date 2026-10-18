// W3 — tests for the variance display helpers.
//
// The numbers below are the real ones from job 9 ("Quote for the
// Nguyen wedding") as the live endpoint returned them, not invented
// values: 0.06225, 154.26895 and 0.057383333 minutes against a plan of
// 10/25/10. That job is the reason the "null is not zero" and
// "round for display only" rules exist here.
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  roundMinutes,
  formatMinutes,
  gapTone,
  formatGap,
  summariseJob,
  reasonLabel,
  eventLabel,
} from './varianceDisplay';

// ── roundMinutes ─────────────────────────────────────────────────────

test('UT-W3-01 rounds a real sub-minute reading to 0, not to null', () => {
  assert.equal(roundMinutes(0.06225), 0);
});

test('UT-W3-02 keeps null as null — "we do not know" is not "it took no time"', () => {
  assert.equal(roundMinutes(null), null);
  assert.equal(roundMinutes(undefined), null);
  assert.equal(roundMinutes(Number.NaN), null);
});

test('UT-W3-03 rounds a long reading to the nearest minute', () => {
  assert.equal(roundMinutes(154.26895), 154);
});

// ── formatMinutes ────────────────────────────────────────────────────

test('UT-W3-04 formats minutes, hours, and the unknown case', () => {
  assert.equal(formatMinutes(25), '25 min');
  assert.equal(formatMinutes(60), '1 hr');
  assert.equal(formatMinutes(154.26895), '2 hr 34 min');
  assert.equal(formatMinutes(null), '—');
});

// ── gapTone ──────────────────────────────────────────────────────────

test('UT-W3-05 a big overrun is "over"', () => {
  // Job 9's step 2: 154 minutes against a 25-minute plan.
  assert.equal(gapTone(129.26895, 517.1), 'over');
});

test('UT-W3-06 a big underrun is "under"', () => {
  assert.equal(gapTone(-9.93775, -99.4), 'under');
});

test('UT-W3-07 within 10% reads as on track — a report that flags everything says nothing', () => {
  assert.equal(gapTone(2.4, 9.6), 'on_track');
  assert.equal(gapTone(-2.4, -9.6), 'on_track');
});

test('UT-W3-08 a tiny absolute gap is on track even when the percentage is huge', () => {
  // A 1-minute step that took 2 is 100% over and nobody cares.
  assert.equal(gapTone(1, 100), 'on_track');
});

test('UT-W3-09 unknown stays unknown', () => {
  assert.equal(gapTone(null, null), 'unknown');
  assert.equal(gapTone(undefined, 50), 'unknown');
});

// ── formatGap ────────────────────────────────────────────────────────

test('UT-W3-10 phrases the gap in plain words', () => {
  assert.equal(formatGap(129.26895, 517.1), '2 hr 9 min over');
  assert.equal(formatGap(-30, -50), '30 min under');
  assert.equal(formatGap(1, 5), 'On track');
  assert.equal(formatGap(null, null), 'Not recorded');
});

// ── summariseJob ─────────────────────────────────────────────────────

test('UT-W3-11 says so plainly when nothing has been recorded', () => {
  assert.equal(
    summariseJob([
      {expected_minutes: 10, actual_minutes: null, is_outlier: false},
      {expected_minutes: 25, actual_minutes: null, is_outlier: false},
    ]),
    'Nothing recorded yet',
  );
});

test('UT-W3-12 summarises job 9 as it really happened', () => {
  const s = summariseJob([
    {expected_minutes: 10, actual_minutes: 0.06225, is_outlier: false},
    {expected_minutes: 25, actual_minutes: 154.26895, is_outlier: true},
    {expected_minutes: 10, actual_minutes: 0.057383333333333335, is_outlier: false},
  ]);
  assert.ok(s.includes('2 hr 34 min actual'), s);
  assert.ok(s.includes('45 min planned'), s);
  assert.ok(s.includes('over'), s);
  assert.ok(s.includes('1 step well over'), s);
});

test('UT-W3-13 a half-finished job is not reported as massively under plan', () => {
  // Only the recorded step counts toward the plan total; otherwise the
  // two unstarted steps would make this look 40 minutes under.
  const s = summariseJob([
    {expected_minutes: 10, actual_minutes: 11, is_outlier: false},
    {expected_minutes: 25, actual_minutes: null, is_outlier: false},
    {expected_minutes: 15, actual_minutes: null, is_outlier: false},
  ]);
  assert.ok(s.includes('11 min actual vs 10 min planned'), s);
  assert.ok(s.includes('On track'), s);
});

// ── labels ───────────────────────────────────────────────────────────

test('UT-W3-14 reason codes read as words, and an unknown one is passed through', () => {
  assert.equal(reasonLabel('waiting_on_someone'), 'Waiting on someone');
  assert.equal(reasonLabel('something_new'), 'something_new');
  assert.equal(reasonLabel(null), null);
  assert.equal(reasonLabel(''), null);
});

test('UT-W3-15 event types read as words', () => {
  assert.equal(eventLabel('completed'), 'Finished');
  assert.equal(eventLabel('blocked'), 'Blocked');
  assert.equal(eventLabel('invented'), 'invented');
});
