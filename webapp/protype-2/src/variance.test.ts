import assert from 'node:assert/strict';
import test from 'node:test';
import {computeTaskVariance, isOutlier, OUTLIER_FACTOR, OUTLIER_FLOOR_MINUTES, type VarianceEvent} from './variance';

const MIN = 60_000;
const T0 = 1_800_000_000_000; // an arbitrary fixed epoch so every test is deterministic

function ev(type: VarianceEvent['event_type'], offsetMinutes: number): VarianceEvent {
  return {event_type: type, occurred_at: T0 + offsetMinutes * MIN};
}

test('UT-VAR-1-01: start 09:00, done 09:40, expected 30 → actual 40, expected gap +10 (+33.3%)', () => {
  const r = computeTaskVariance({
    events: [ev('started', 0), ev('completed', 40)],
    expectedMinutes: 30,
    scheduledMinutes: null,
    plannedStartAt: null,
  });
  assert.equal(r.actualMinutes, 40);
  assert.equal(r.expectedGapMinutes, 10);
  assert.equal(r.expectedGapPct, 33.3);
});

test('UT-VAR-1-02: same, with scheduled 45 → scheduled gap -5 (-11.1%)', () => {
  const r = computeTaskVariance({
    events: [ev('started', 0), ev('completed', 40)],
    expectedMinutes: 30,
    scheduledMinutes: 45,
    plannedStartAt: null,
  });
  assert.equal(r.scheduledGapMinutes, -5);
  assert.equal(r.scheduledGapPct, -11.1);
});

test('UT-VAR-1-03: blocked 09:10–09:20 → blocked_minutes 10; actual_minutes unchanged (elapsed)', () => {
  const r = computeTaskVariance({
    events: [ev('started', 0), ev('blocked', 10, ), ev('unblocked', 20), ev('completed', 40)],
    expectedMinutes: 30,
    scheduledMinutes: null,
    plannedStartAt: null,
  });
  assert.equal(r.blockedMinutes, 10);
  // The elapsed span still runs start→done; the blocked time is reported
  // separately, never subtracted from the wall-clock span.
  assert.equal(r.actualMinutes, 40);
});

test('UT-VAR-1-04: never started / never completed → actual null, no outlier', () => {
  const r = computeTaskVariance({
    events: [],
    expectedMinutes: 30,
    scheduledMinutes: null,
    plannedStartAt: null,
  });
  assert.equal(r.actualMinutes, null);
  assert.equal(r.isOutlier, false);
});

test('UT-VAR-1-05: expected missing → expected gap null; scheduled gap still computed', () => {
  const r = computeTaskVariance({
    events: [ev('started', 0), ev('completed', 40)],
    expectedMinutes: null,
    scheduledMinutes: 45,
    plannedStartAt: null,
  });
  assert.equal(r.expectedGapMinutes, null);
  assert.equal(r.expectedGapPct, null);
  assert.equal(r.scheduledGapMinutes, -5);
});

test('UT-VAR-1-06: start 09:05, planned 09:00 → start_lateness_minutes 5', () => {
  const r = computeTaskVariance({
    events: [ev('started', 5), ev('completed', 35)],
    expectedMinutes: 30,
    scheduledMinutes: null,
    plannedStartAt: T0,
  });
  assert.equal(r.startLatenessMinutes, 5);
});

test('UT-VAR-1-07: reopened then completed directly → the reopen itself marks the resumed span (no re-start is possible)', () => {
  // `logModel.ts::canTransition` has no `in_progress`+`started` row —
  // a real event log can never contain an explicit `started` after a
  // `reopened`, and the UI's `availableActions('in_progress')` doesn't
  // even offer a Start button. Reproduced live during VAR-1 testing.
  const r = computeTaskVariance({
    events: [
      ev('started', 0),
      ev('completed', 40), // first attempt: 40 minutes
      ev('reopened', 60),
      ev('completed', 75), // second attempt: 15 minutes, measured from the reopen itself
    ],
    expectedMinutes: 30,
    scheduledMinutes: null,
    plannedStartAt: null,
  });
  assert.equal(r.actualMinutes, 15);
  assert.deepEqual(r.warnings, []); // NOT "done with no start" — the reopen is a real resumption signal
});

test('UT-VAR-1-07b: start_lateness_minutes always uses the FIRST start, even across a reopen', () => {
  const r = computeTaskVariance({
    events: [ev('started', 5), ev('completed', 40), ev('reopened', 60), ev('completed', 75)],
    expectedMinutes: 30,
    scheduledMinutes: null,
    plannedStartAt: T0,
  });
  assert.equal(r.startLatenessMinutes, 5); // the original 09:05 start, not the reopen at minute 60
});

test('UT-VAR-1-08: outlier boundary — reference 30, actual 60 not flagged, 61 flagged', () => {
  const at = (actual: number) =>
    computeTaskVariance({
      events: [ev('started', 0), ev('completed', actual)],
      expectedMinutes: null,
      scheduledMinutes: 30,
      plannedStartAt: null,
    }).isOutlier;
  assert.equal(at(60), false);
  assert.equal(at(61), true);
});

test('UT-VAR-1-09: small task — reference 3, actual 12 not flagged (floor +10 → 13)', () => {
  const r = computeTaskVariance({
    events: [ev('started', 0), ev('completed', 12)],
    expectedMinutes: null,
    scheduledMinutes: 3,
    plannedStartAt: null,
  });
  assert.equal(r.isOutlier, false);
});

test('UT-VAR-1-12: frozen inputs, called twice, no mutation, same output', () => {
  const events = Object.freeze([ev('started', 0), ev('completed', 40)]);
  const input = Object.freeze({events, expectedMinutes: 30, scheduledMinutes: 45, plannedStartAt: T0});
  const a = computeTaskVariance(input);
  const b = computeTaskVariance(input);
  assert.deepEqual(a, b);
});

test('UT-VAR-1-13: done without a start event → actual unknown; no gap; no outlier; W-VAR-001', () => {
  const r = computeTaskVariance({
    events: [ev('completed', 0)],
    expectedMinutes: 30,
    scheduledMinutes: null,
    plannedStartAt: null,
  });
  assert.equal(r.actualMinutes, null);
  assert.equal(r.expectedGapMinutes, null);
  assert.equal(r.isOutlier, false);
  assert.ok(r.warnings.includes('W-VAR-001'));
});

// ── isOutlier as a standalone, reusable rule ───────────────────────────────

test('isOutlier: constants are 2.0× / 10 minutes, exported for reuse', () => {
  assert.equal(OUTLIER_FACTOR, 2.0);
  assert.equal(OUTLIER_FLOOR_MINUTES, 10);
  assert.equal(isOutlier(60, 30), false);
  assert.equal(isOutlier(61, 30), true);
  assert.equal(isOutlier(null, 30), false);
  assert.equal(isOutlier(60, null), false);
});

// ── UT-VAR-1-G01: every data-quality warning ──────────────────────────────

test('UT-VAR-1-G01: W-VAR-001 — done with no start event', () => {
  const r = computeTaskVariance({events: [ev('completed', 0)], expectedMinutes: 30, scheduledMinutes: null, plannedStartAt: null});
  assert.deepEqual(r.warnings, ['W-VAR-001']);
});

test('UT-VAR-1-G01: W-VAR-002 — end earlier than start', () => {
  // Constructed directly rather than through a valid event sequence (the
  // real engine, logModel.ts, cannot produce this) — this check exists
  // for a clock problem or a tampered row, which is exactly what it is
  // meant to catch.
  const r = computeTaskVariance({
    events: [{event_type: 'started', occurred_at: T0 + 10 * MIN}, {event_type: 'completed', occurred_at: T0}],
    expectedMinutes: 30,
    scheduledMinutes: null,
    plannedStartAt: null,
  });
  assert.ok(r.warnings.includes('W-VAR-002'));
});

test('UT-VAR-1-G01: W-VAR-003 — elapsed time longer than 24 hours', () => {
  const r = computeTaskVariance({
    events: [ev('started', 0), ev('completed', 1441)],
    expectedMinutes: 30,
    scheduledMinutes: null,
    plannedStartAt: null,
  });
  assert.ok(r.warnings.includes('W-VAR-003'));
});

test('UT-VAR-1-G01: W-VAR-004 — no expected duration on the map', () => {
  const r = computeTaskVariance({
    events: [ev('started', 0), ev('completed', 40)],
    expectedMinutes: null,
    scheduledMinutes: null,
    plannedStartAt: null,
  });
  assert.ok(r.warnings.includes('W-VAR-004'));
});

test('UT-VAR-1-G01: a clean task carries no warnings', () => {
  const r = computeTaskVariance({
    events: [ev('started', 0), ev('completed', 40)],
    expectedMinutes: 30,
    scheduledMinutes: 45,
    plannedStartAt: T0,
  });
  assert.deepEqual(r.warnings, []);
});
