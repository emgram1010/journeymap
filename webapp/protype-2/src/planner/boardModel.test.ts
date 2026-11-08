import assert from 'node:assert/strict';
import test from 'node:test';
import {canRepublish, classifyUnscheduleTarget, groupCardsByJob, jobCardDropRefusal, jobSlotProvenance, cardSubtitle, initialBoardDay, localToday, workOutsidePlan, cellPreview, capacityFit, overloadMessage, formatFree, versionBadge, waitingJobsCount} from './boardModel';

const card = (workItemId: number, lensKey: string, jobTitle: string | null = `Job ${workItemId}`) => ({
  card_key: `${workItemId}::${lensKey}`,
  work_item_id: workItemId,
  job_title: jobTitle,
  lens_key: lensKey,
});

// ── groupCardsByJob ──────────────────────────────────────────────────

test('UT-BOARD-1-01: cards group under their job, newest job first', () => {
  const groups = groupCardsByJob([card(7, 'tech'), card(9, 'qa'), card(7, 'driver'), card(9, 'tech')]);
  assert.deepEqual(
    groups.map((g) => ({id: g.workItemId, cards: g.cards.map((c) => c.lens_key)})),
    [
      {id: 9, cards: ['qa', 'tech']},
      {id: 7, cards: ['tech', 'driver']},
    ],
  );
});

test('UT-BOARD-1-02: a job with no title is still a group, named by its number', () => {
  const [g] = groupCardsByJob([card(12, 'tech', null)]);
  assert.equal(g.jobTitle, 'Job #12');
});

test('UT-BOARD-1-03: cards within a job keep the order the server gave them', () => {
  const [g] = groupCardsByJob([card(5, 'b'), card(5, 'a'), card(5, 'c')]);
  assert.deepEqual(g.cards.map((c) => c.lens_key), ['b', 'a', 'c']);
});

test('UT-BOARD-1-04: grouping does not mutate the list it was given', () => {
  const cards = [card(2, 'x'), card(1, 'y')];
  const before = structuredClone(cards);
  groupCardsByJob(cards);
  assert.deepEqual(cards, before);
});

// ── waitingJobsCount ─────────────────────────────────────────────────

test('UT-BOARD-1-05: the header counts jobs, not cards', () => {
  assert.equal(waitingJobsCount([card(7, 'tech'), card(7, 'driver'), card(9, 'qa')]), 2);
  assert.equal(waitingJobsCount([]), 0);
});

// ── jobCardDropRefusal — the drop-intent rule, apart from the DOM ────

test('UT-BOARD-1-06: a published day refuses with a sentence; a draft or missing day does not', () => {
  assert.equal(
    jobCardDropRefusal('published'),
    'That day is published and frozen — reopen it before adding work.',
  );
  assert.equal(jobCardDropRefusal('draft'), null);
  assert.equal(jobCardDropRefusal(undefined), null); // no day yet — it will be created
});

// ── canRepublish / versionBadge (REPUB-1) ─────────────────────────────

test('UT-REPUB-1-10: a published, unsealed timeline may be republished', () => {
  assert.equal(canRepublish({status: 'published', isSealed: false}), true);
});

test('UT-REPUB-1-11: a sealed timeline may not be republished', () => {
  assert.equal(canRepublish({status: 'published', isSealed: true}), false);
});

test('UT-REPUB-1-12: a draft timeline may not be republished, sealed or not', () => {
  assert.equal(canRepublish({status: 'draft', isSealed: false}), false);
  assert.equal(canRepublish({status: 'draft'}), false);
});

test('UT-REPUB-1-13: the version badge is quiet until a day has been republished', () => {
  assert.equal(versionBadge(1), null, 'the ordinary first-publish case shows no badge');
  assert.equal(versionBadge(2), 'v2');
  assert.equal(versionBadge(5), 'v5');
  assert.equal(versionBadge(0), null, 'never published');
  assert.equal(versionBadge(undefined), null);
  assert.equal(versionBadge(null), null);
});

// ── jobSlotProvenance — the amber line on a scheduled slot ───────────

test('UT-BOARD-1-07: a job slot names its job, a card says how many steps it covers', () => {
  assert.equal(jobSlotProvenance({jobTitle: 'Repair for Garcia', jobStepCount: 3}), 'Repair for Garcia · 3 steps');
  assert.equal(jobSlotProvenance({jobTitle: 'Repair for Garcia', jobStepCount: 1}), 'Repair for Garcia');
  assert.equal(jobSlotProvenance({jobTitle: 'Repair for Garcia'}), 'Repair for Garcia');
  assert.equal(jobSlotProvenance({}), null, 'a plain task has no provenance line');
});

// ── classifyUnscheduleTarget (US-QUE-1-05/06) ─────────────────────────

test('UT-QUE-1-05-01: a job slot always needs confirmation', () => {
  assert.equal(classifyUnscheduleTarget({workItemId: 7, workTaskId: 42}), 'confirm-job-slot');
});

test('UT-QUE-1-05-02: a plain task keeps its existing, un-confirmed path', () => {
  assert.equal(classifyUnscheduleTarget({}), 'plain-task');
  assert.equal(classifyUnscheduleTarget({workItemId: 0}), 'plain-task');
});

test('UT-QUE-1-05-03: a job slot missing its work_task_id is invalid, not confirmable', () => {
  assert.equal(classifyUnscheduleTarget({workItemId: 7}), 'invalid');
  assert.equal(classifyUnscheduleTarget({workItemId: 7, workTaskId: 0}), 'invalid');
});

// ── PUX-3-04 — one title per card ────────────────────────────────────
test('UT-PUX-3-03: the job line is hidden when it repeats the card title', () => {
  assert.equal(cardSubtitle({title: 'E2E card 1 · 8 steps', jobTitle: 'E2E card 1', jobStepCount: 8}), null);
  assert.equal(cardSubtitle({title: '  E2E card 1 · 8 steps ', jobTitle: 'E2E card 1', jobStepCount: 8}), null);
});

test('UT-PUX-3-03: a single-step card still names its job under the step', () => {
  assert.equal(cardSubtitle({title: 'Triage', jobTitle: 'Turn-around', jobStepCount: 1}), 'Turn-around');
});

test('UT-PUX-3-03: a plain task has no job line', () => {
  assert.equal(cardSubtitle({title: 'Call supplier'}), null);
});

// ── PUX-3-01 — open on the right day ─────────────────────────────────
test('UT-PUX-3-01: today inside the plan → today', () => {
  assert.equal(initialBoardDay('2026-11-04', '2026-11-01', '2026-11-07', '2026-10-27'), '2026-11-04');
});
test('UT-PUX-3-01: today outside the plan → the plan first day, never the first timeline', () => {
  assert.equal(initialBoardDay('2026-11-09', '2026-11-01', '2026-11-07', '2026-10-27'), '2026-11-01');
  assert.equal(initialBoardDay('2026-10-01', '2026-11-01', '2026-11-07', '2026-10-27'), '2026-11-01');
});
test('UT-PUX-3-01: a plan with no dates → its first timeline, else today', () => {
  assert.equal(initialBoardDay('2026-11-09', '', '', '2026-10-27'), '2026-10-27');
  assert.equal(initialBoardDay('2026-11-09', '', '', null), '2026-11-09');
});

// ── PUX-3-02 — work outside the plan is flagged, not hidden ──────────
test('UT-PUX-3-02: days with work outside the plan, earliest first', () => {
  const timelines = [
    {id: '46', plannedDate: '2026-10-27'},
    {id: '47', plannedDate: '2026-11-01'},
    {id: '60', plannedDate: '2026-11-09'},
    {id: '61', plannedDate: '2026-10-20'},
  ];
  const tasks = [
    {timelineId: '46'}, {timelineId: '46'},
    {timelineId: '47'},
    {timelineId: '60'},
    // timeline 61 is outside but EMPTY — an empty day is not hidden work
  ];
  assert.deepEqual(workOutsidePlan(timelines, tasks, '2026-11-01', '2026-11-07'), [
    {timelineId: '46', date: '2026-10-27', slots: 2},
    {timelineId: '60', date: '2026-11-09', slots: 1},
  ]);
});
test('UT-PUX-3-02: nothing outside, or no plan dates → empty', () => {
  assert.deepEqual(workOutsidePlan([{id: '47', plannedDate: '2026-11-01'}], [{timelineId: '47'}], '2026-11-01', '2026-11-07'), []);
  assert.deepEqual(workOutsidePlan([{id: '46', plannedDate: '2026-10-27'}], [{timelineId: '46'}], '', ''), []);
});

// ── PUX-3-03 — names, not counts, in the week view ───────────────────
test('UT-PUX-3-04: a cell lists its first items in day order, then "+N more"', () => {
  const tasks = [
    {seq: 3, planned_start: '11:00', title: 'C'},
    {seq: 1, planned_start: '08:00', title: 'A'},
    {seq: 2, planned_start: '09:30', title: 'B'},
    {seq: 4, planned_start: '13:00', title: 'D'},
    {seq: 5, planned_start: '14:00', title: 'E'},
  ];
  const r = cellPreview(tasks, 3);
  assert.deepEqual(r.shown.map((t) => t.title), ['A', 'B', 'C']);
  assert.equal(r.more, 2);
});
test('UT-PUX-3-04: a small cell shows everything, no "more"', () => {
  const r = cellPreview([{seq: 1, planned_start: '08:00', title: 'A'}], 3);
  assert.equal(r.shown.length, 1);
  assert.equal(r.more, 0);
});

// ── PUX-4-01/02 — who's free ─────────────────────────────────────────
test('UT-PUX-4-01: an empty day fits a 3h job with 8h free', () => {
  assert.deepEqual(capacityFit(0, 8, 180), {freeMinutes: 480, afterMinutes: 180, state: 'fits'});
});
test('UT-PUX-4-01: a partly full day that the job would overflow is "over"', () => {
  assert.deepEqual(capacityFit(360, 8, 180), {freeMinutes: 120, afterMinutes: 540, state: 'over'});
});
test('UT-PUX-4-01: a day already at or past capacity is "full"', () => {
  assert.equal(capacityFit(480, 8, 30).state, 'full');
  assert.equal(capacityFit(710, 8, 30).state, 'full');
  assert.equal(capacityFit(710, 8, 30).freeMinutes, 0);
});
test('UT-PUX-4-01: a custom capacity is respected; exactly filling the day still fits', () => {
  assert.equal(capacityFit(0, 4, 240).state, 'fits');
  assert.equal(capacityFit(0, 4, 241).state, 'over');
});
test('UT-PUX-4-01: formatFree reads like a person talks', () => {
  assert.equal(formatFree(480), '8h free');
  assert.equal(formatFree(90), '1h 30m free');
  assert.equal(formatFree(0), 'no time free');
});
test('UT-PUX-4-02: the overload question names the person and the totals', () => {
  assert.equal(
    overloadMessage('Jav', capacityFit(710, 8, 710), 8),
    'This puts Jav at 23h 40m of 8h. Place anyway?',
  );
});

test('UT-PUX-3-01b: localToday is the local calendar date, not UTC', () => {
  // 21:30 local on 6 Nov — toISOString() would already say 7 Nov west of UTC.
  assert.equal(localToday(new Date(2026, 10, 6, 21, 30)), '2026-11-06');
  assert.equal(localToday(new Date(2026, 0, 1, 0, 5)), '2026-01-01');
});
