// GAP-FIX W4/W5 — tests for the day-navigation and empty-state logic.
//
// The cases below are the real ones from the walkthrough that produced
// these fixes, not invented ones: today is Oct 18 (UTC), the founder's
// published work is on Oct 17 and Oct 19, and the screen used to say
// "Nothing is scheduled for you today." for every one of them.
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  publishedDays,
  prevDayWithWork,
  nextDayWithWork,
  addDays,
  formatDayLabel,
  diagnoseEmptyDay,
} from './dayNavigation';

const DAYS = ['2026-10-17', '2026-10-19'];

// ── publishedDays ────────────────────────────────────────────────────

test('UT-W4-01 publishedDays de-duplicates and sorts oldest first', () => {
  // Exactly the shape the server returns: one entry per published ITEM, not per day.
  assert.deepEqual(
    publishedDays(['2026-10-19', '2026-10-19', '2026-10-17', '2026-10-17', '2026-10-17']),
    DAYS,
  );
});

test('UT-W4-02 publishedDays drops empty strings rather than listing a blank day', () => {
  assert.deepEqual(publishedDays(['', '2026-10-17', '']), ['2026-10-17']);
});

test('UT-W4-03 publishedDays returns an empty list unchanged', () => {
  assert.deepEqual(publishedDays([]), []);
});

// ── prevDayWithWork / nextDayWithWork ────────────────────────────────

test('UT-W4-04 finds the surrounding days from a day with no work', () => {
  assert.equal(prevDayWithWork(DAYS, '2026-10-18'), '2026-10-17');
  assert.equal(nextDayWithWork(DAYS, '2026-10-18'), '2026-10-19');
});

test('UT-W4-05 is strict: a day with work is not its own neighbour', () => {
  assert.equal(prevDayWithWork(DAYS, '2026-10-17'), null);
  assert.equal(nextDayWithWork(DAYS, '2026-10-19'), null);
});

test('UT-W4-06 returns null on both sides when nothing is published', () => {
  assert.equal(prevDayWithWork([], '2026-10-18'), null);
  assert.equal(nextDayWithWork([], '2026-10-18'), null);
});

// ── addDays ──────────────────────────────────────────────────────────

test('UT-W4-07 addDays steps across a month boundary', () => {
  assert.equal(addDays('2026-10-31', 1), '2026-11-01');
  assert.equal(addDays('2026-11-01', -1), '2026-10-31');
});

test('UT-W4-08 addDays steps across a year boundary', () => {
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
});

test('UT-W4-09 addDays leaves junk alone rather than producing "NaN"', () => {
  assert.equal(addDays('not-a-date', 1), 'not-a-date');
});

// ── formatDayLabel ───────────────────────────────────────────────────

test('UT-W4-10 formatDayLabel labels the date it was given, not the local-time one', () => {
  // The whole point: `new Date("2026-10-19")` is UTC midnight, which
  // west of Greenwich prints as the 18th. This must say the 19th.
  const label = formatDayLabel('2026-10-19');
  assert.ok(label.includes('19'), label);
  assert.ok(label.includes('Oct'), label);
});

test('UT-W4-11 formatDayLabel returns junk unchanged', () => {
  assert.equal(formatDayLabel('nope'), 'nope');
});

// ── diagnoseEmptyDay ─────────────────────────────────────────────────

test('UT-W5-01 names the no-agent case first — nothing can ever arrive', () => {
  const d = diagnoseEmptyDay({date: '2026-10-18', today: '2026-10-18', agentIds: [], days: []});
  assert.equal(d.reason, 'no_agent');
  assert.equal(d.jumpTo, null);
});

test('UT-W5-02 no-agent wins even if days somehow came back', () => {
  const d = diagnoseEmptyDay({date: '2026-10-18', today: '2026-10-18', agentIds: [], days: DAYS});
  assert.equal(d.reason, 'no_agent');
});

test('UT-W5-03 distinguishes "nothing published yet" from "not today"', () => {
  const d = diagnoseEmptyDay({date: '2026-10-18', today: '2026-10-18', agentIds: [21], days: []});
  assert.equal(d.reason, 'nothing_published');
});

test('UT-W5-04 points at the next day with work — the walkthrough case', () => {
  const d = diagnoseEmptyDay({date: '2026-10-18', today: '2026-10-18', agentIds: [21], days: DAYS});
  assert.equal(d.reason, 'other_days');
  assert.equal(d.jumpTo, '2026-10-19');
  assert.ok(d.detail.includes('Next work'), d.detail);
});

test('UT-W5-05 falls back to the last day with work when everything is in the past', () => {
  const d = diagnoseEmptyDay({date: '2026-10-20', today: '2026-10-20', agentIds: [21], days: DAYS});
  assert.equal(d.reason, 'other_days');
  assert.equal(d.jumpTo, '2026-10-19');
  assert.ok(d.detail.includes('Last work'), d.detail);
});

test('UT-W5-06 names the day when looking at one that is not today', () => {
  const d = diagnoseEmptyDay({date: '2026-10-20', today: '2026-10-18', agentIds: [21], days: DAYS});
  assert.ok(d.headline.includes('20'), d.headline);
  assert.ok(!d.headline.includes('today'), d.headline);
});

test('UT-W5-07 flags the shouldn’t-happen case separately', () => {
  const d = diagnoseEmptyDay({date: '2026-10-17', today: '2026-10-18', agentIds: [21], days: DAYS});
  assert.equal(d.reason, 'empty_day');
});
