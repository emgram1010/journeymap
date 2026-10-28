import assert from 'node:assert/strict';
import test from 'node:test';
import {groupCardsByJob, jobCardDropRefusal, jobSlotProvenance, waitingJobsCount} from './boardModel';

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

// ── jobSlotProvenance — the amber line on a scheduled slot ───────────

test('UT-BOARD-1-07: a job slot names its job, a card says how many steps it covers', () => {
  assert.equal(jobSlotProvenance({jobTitle: 'Repair for Garcia', jobStepCount: 3}), 'Repair for Garcia · 3 steps');
  assert.equal(jobSlotProvenance({jobTitle: 'Repair for Garcia', jobStepCount: 1}), 'Repair for Garcia');
  assert.equal(jobSlotProvenance({jobTitle: 'Repair for Garcia'}), 'Repair for Garcia');
  assert.equal(jobSlotProvenance({}), null, 'a plain task has no provenance line');
});
