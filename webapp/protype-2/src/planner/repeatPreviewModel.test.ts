import assert from 'node:assert/strict';
import test from 'node:test';
import {
  defaultRepeatStart,
  shiftDays,
  weekdaysAlign,
  windowOverlaps,
  validateStartDate,
  canTick,
  toggleSkip,
  groupJobs,
  reasonText,
  capList,
  summaryLines,
  peopleLeftOff,
  type RepeatJob,
  type RepeatCounts,
} from './repeatPreviewModel';

// REPEAT-1 story 01. The server (functions/repeat/build_plan.xs) decides what a repeat copies.
// This model only helps the screen: the same date rules, so a bad date is caught before the
// round trip, and plain wording for each verdict. Golden values below were read from the live
// function on 2026-11-25 (plans 42 and 115).

const job = (over: Partial<RepeatJob> = {}): RepeatJob => ({
  id: 1,
  title: 'Job',
  status: 'open',
  verdict: 'repeat',
  reason: '',
  uses_newer_version: false,
  map_id: 10,
  map_title: 'Map',
  from_version_id: 5,
  to_version_id: 5,
  to_version_no: 1,
  steps: 2,
  ...over,
});

// ── T-REPEAT-01-1: offered start date ──────────────────────────────

test('T-REPEAT-01-1: the offered start is the day after the plan ends (7-day plan)', () => {
  assert.equal(defaultRepeatStart('2026-11-27'), '2026-11-28');
});

test('T-REPEAT-01-1: 14-day plan, and across a month and a year end', () => {
  assert.equal(defaultRepeatStart('2026-12-14'), '2026-12-15');
  assert.equal(defaultRepeatStart('2026-11-30'), '2026-12-01');
  assert.equal(defaultRepeatStart('2026-12-31'), '2027-01-01');
});

test('T-REPEAT-01-1: shift is counted in whole days (matches the server: 42 → 9, 115 → 14)', () => {
  assert.equal(shiftDays('2026-10-27', '2026-11-05'), 9);
  assert.equal(shiftDays('2026-12-01', '2026-12-15'), 14);
});

// ── T-REPEAT-01-6: weekday warning and overlap ─────────────────────

test('T-REPEAT-01-6: a whole number of weeks keeps the weekdays; anything else warns', () => {
  assert.equal(weekdaysAlign('2026-12-01', '2026-12-15'), true);
  assert.equal(weekdaysAlign('2026-10-27', '2026-11-05'), false);
  assert.equal(weekdaysAlign('2026-12-01', '2026-12-08'), true);
});

test('T-REPEAT-01-6: a start inside the source window overlaps; the day after the end does not', () => {
  assert.equal(windowOverlaps('2026-12-01', '2026-12-14', '2026-12-10'), true);
  assert.equal(windowOverlaps('2026-12-01', '2026-12-14', '2026-12-14'), true);
  assert.equal(windowOverlaps('2026-12-01', '2026-12-14', '2026-12-15'), false);
});

test('T-REPEAT-01-6: a start far enough before the source does not overlap; one that runs into it does', () => {
  assert.equal(windowOverlaps('2026-12-01', '2026-12-14', '2026-11-17'), false);
  assert.equal(windowOverlaps('2026-12-01', '2026-12-14', '2026-11-20'), true);
});

test('E-REPEAT-002: an empty, badly written or impossible date is refused with the catalog code', () => {
  for (const bad of ['', 'tomorrow', '2026-13-45', '2027-02-31', '26-12-01']) {
    const r = validateStartDate(bad, '2026-12-01', '2026-12-14');
    assert.equal(r.ok === false && r.code, 'E-REPEAT-002', bad);
  }
});

test('E-REPEAT-003: an overlapping date is refused; a good one passes', () => {
  const over = validateStartDate('2026-12-10', '2026-12-01', '2026-12-14');
  assert.equal(over.ok === false && over.code, 'E-REPEAT-003');
  assert.deepEqual(validateStartDate('2026-12-15', '2026-12-01', '2026-12-14'), {ok: true});
});

// ── T-REPEAT-01-3 / -5: which jobs can be ticked, and why not ──────

test('T-REPEAT-01-3: only a job that repeats (or was unticked) can be ticked', () => {
  assert.equal(canTick(job({verdict: 'repeat'})), true);
  assert.equal(canTick(job({verdict: 'left_out', reason: 'left_out'})), true);
  assert.equal(canTick(job({verdict: 'will_not_repeat', reason: 'outside_order'})), false);
  assert.equal(canTick(job({verdict: 'will_not_repeat', reason: 'exception_child'})), false);
  assert.equal(canTick(job({verdict: 'will_not_repeat', reason: 'cancelled'})), false);
  assert.equal(canTick(job({verdict: 'cannot_repeat', reason: 'no_published_version'})), false);
});

test('T-REPEAT-01-3: every reason has plain wording, and an unknown one never shows a raw code', () => {
  for (const r of ['outside_order', 'exception_child', 'cancelled', 'map_unavailable', 'no_published_version', 'left_out']) {
    const text = reasonText(r);
    assert.ok(text.length > 10, r);
    assert.ok(!text.includes('_'), r);
  }
  assert.ok(!reasonText('something_new').includes('_'));
  assert.equal(reasonText(''), '');
});

test('T-REPEAT-01-5: jobs are grouped by verdict, and "newer version" is its own list', () => {
  const g = groupJobs([
    job({id: 1}),
    job({id: 2, uses_newer_version: true, to_version_id: 9, to_version_no: 4}),
    job({id: 3, verdict: 'left_out', reason: 'left_out'}),
    job({id: 4, verdict: 'will_not_repeat', reason: 'cancelled'}),
    job({id: 5, verdict: 'cannot_repeat', reason: 'map_unavailable'}),
  ]);
  assert.deepEqual(g.repeat.map(j => j.id), [1, 2]);
  assert.deepEqual(g.newer.map(j => j.id), [2]);
  assert.deepEqual(g.leftOut.map(j => j.id), [3]);
  assert.deepEqual(g.willNot.map(j => j.id), [4]);
  assert.deepEqual(g.cannot.map(j => j.id), [5]);
});

test('leave a job out: toggling adds and removes its id, and never duplicates', () => {
  assert.deepEqual(toggleSkip([], 7), [7]);
  assert.deepEqual(toggleSkip([7], 7), []);
  assert.deepEqual(toggleSkip([3, 7], 3), [7]);
  assert.deepEqual(toggleSkip([3], 7), [3, 7]);
});

// ── T-REPEAT-01-4: people left off ─────────────────────────────────

test('T-REPEAT-01-4: a person left off is listed with the slots that go to the backlog', () => {
  const left = peopleLeftOff([
    {agent_id: 48, name: 'Tony', kind: 'person', left_off: true, slots_to_backlog: 1},
    {agent_id: 49, name: 'Jav', kind: 'person', left_off: false, slots_to_backlog: 0},
  ]);
  assert.deepEqual(left, [{agent_id: 48, name: 'Tony', slots_to_backlog: 1}]);
});

test('T-REPEAT-01-4: a person with no name still gets a label', () => {
  const left = peopleLeftOff([{agent_id: 5, name: '', kind: 'person', left_off: true, slots_to_backlog: 0}]);
  assert.equal(left[0].name, 'Unnamed person');
});

// ── T-REPEAT-01-2: counts ──────────────────────────────────────────

const counts = (over: Partial<RepeatCounts> = {}): RepeatCounts => ({
  people: 1, people_left_off: 1, days: 4, jobs: 3, jobs_left_out: 0, jobs_will_not: 7, jobs_cannot: 0,
  jobs_newer: 3, steps: 24, slots: 2, slots_to_backlog: 1, backlog: 0, slots_dropped: 5, row_estimate: 39,
  ...over,
});

test('T-REPEAT-01-2: the summary states people, days, jobs, slots and backlog, with singulars right', () => {
  const lines = summaryLines(counts());
  assert.deepEqual(lines, ['1 person', '4 days', '3 jobs', '2 scheduled slots', '1 backlog item']);
  assert.deepEqual(summaryLines(counts({people: 3, days: 1, jobs: 1, slots: 1, slots_to_backlog: 0, backlog: 4})),
    ['3 people', '1 day', '1 job', '1 scheduled slot', '4 backlog items']);
});

test('long lists are capped with "and N more"', () => {
  assert.deepEqual(capList([1, 2, 3], 5), {shown: [1, 2, 3], more: 0});
  assert.deepEqual(capList([1, 2, 3, 4, 5, 6, 7], 5), {shown: [1, 2, 3, 4, 5], more: 2});
});
