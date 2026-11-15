import assert from 'node:assert/strict';
import test from 'node:test';
import {runCountsLine, runStatusLabel, runTone, runsHeadline, type CopilotRun} from './copilotRunModel';

// COP-5 story 05 - scheduled run model.

const run = (over: Partial<CopilotRun> = {}): CopilotRun => ({
  id: 1,
  status: 'finished',
  started_at: 1_800_000_000_000,
  finished_at: 1_800_000_060_000,
  open_task_count: 2,
  held_count: 0,
  told_count: 0,
  refused_count: 0,
  report: 'Did: nothing',
  reason: '',
  ...over,
});

test('names every status in plain words, and shows an unknown one as-is', () => {
  assert.equal(runStatusLabel('finished'), 'Finished');
  assert.equal(runStatusLabel('nothing_to_do'), 'Nothing to do');
  assert.equal(runStatusLabel('skipped'), 'Skipped');
  assert.equal(runStatusLabel('failed'), 'Failed');
  assert.equal(runStatusLabel('running'), 'Running now');
  assert.equal(runStatusLabel('mystery'), 'mystery');
  assert.equal(runStatusLabel(''), '');
});

test('marks only a failed run as a problem', () => {
  assert.equal(runTone('failed'), 'bad');
  assert.equal(runTone('skipped'), 'quiet');
  assert.equal(runTone('nothing_to_do'), 'quiet');
  assert.equal(runTone('finished'), 'ok');
  assert.equal(runTone('running'), 'ok');
});

test('says what was held, done-then-told and refused, and nothing when all are zero', () => {
  assert.equal(runCountsLine(run()), '');
  assert.equal(runCountsLine(run({held_count: 2})), '2 waiting for you');
  assert.equal(
    runCountsLine(run({held_count: 1, told_count: 3, refused_count: 1})),
    '1 waiting for you · 3 done, then told you · 1 refused',
  );
});

test('treats a missing count as zero (an untouched int column is 0, never null)', () => {
  assert.equal(runCountsLine(run({held_count: undefined, told_count: null as unknown as number})), '');
});

test('says plainly when scheduled work is off, on with no runs, and on with runs', () => {
  assert.match(runsHeadline(false, 0), /switched off/i);
  assert.match(runsHeadline(true, 0), /no runs yet/i);
  assert.match(runsHeadline(true, 3), /last 14 days/i);
  // Off but with old runs: still say it is off first.
  assert.match(runsHeadline(false, 3), /switched off/i);
});
