import assert from 'node:assert/strict';
import test from 'node:test';
import {firstJobToShow, reportJobOptions, type ReportJobEntry} from './reportsModel';

const entry = (over: Partial<ReportJobEntry['work_item']> & {id: number}, rest: Partial<ReportJobEntry> = {}): ReportJobEntry => ({
  work_item: {id: over.id, title: over.title ?? `Job ${over.id}`, status: over.status ?? 'open'},
  task_count: rest.task_count ?? 6,
  finished_count: rest.finished_count ?? 0,
  has_progress: rest.has_progress ?? false,
});

test('reportJobOptions: one option per job, with the planner words for its status', () => {
  const options = reportJobOptions([
    entry({id: 12, title: 'Quote for the Garcia party', status: 'in_progress'}, {finished_count: 2, has_progress: true}),
  ]);
  assert.deepEqual(options, [
    {
      id: 12,
      title: 'Quote for the Garcia party',
      statusLabel: 'In progress',
      stepSummary: '2 of 6 steps done',
      hasRecord: true,
    },
  ]);
});

test('reportJobOptions: one step is singular, and no steps says so', () => {
  const [one] = reportJobOptions([entry({id: 1}, {task_count: 1, finished_count: 1})]);
  assert.equal(one.stepSummary, '1 of 1 step done');
  // Never "0 of 0" — the same rule the job view's own sentence follows.
  const [none] = reportJobOptions([entry({id: 2}, {task_count: 0, finished_count: 0})]);
  assert.equal(none.stepSummary, 'No steps');
});

test('reportJobOptions: jobs with something recorded come first, then the newest', () => {
  const options = reportJobOptions([
    entry({id: 3}),
    entry({id: 9}),
    entry({id: 5}, {has_progress: true}),
    entry({id: 7}, {has_progress: true}),
  ]);
  assert.deepEqual(options.map((o) => o.id), [7, 5, 9, 3]);
});

test('reportJobOptions: an unknown status is shown as it came, never hidden', () => {
  const [o] = reportJobOptions([entry({id: 4, status: 'awaiting_parts'})]);
  assert.equal(o.statusLabel, 'awaiting_parts');
});

test('reportJobOptions: does not mutate the list it was given', () => {
  const entries = [entry({id: 1}), entry({id: 2}, {has_progress: true})];
  const before = structuredClone(entries);
  reportJobOptions(entries);
  assert.deepEqual(entries, before);
});

test('firstJobToShow: the job worth opening on, or nothing at all', () => {
  const options = reportJobOptions([entry({id: 3}), entry({id: 8}, {has_progress: true})]);
  assert.equal(firstJobToShow(options), 8);
  assert.equal(firstJobToShow([]), null);
});
