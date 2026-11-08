// LOAD-1 (US-LOAD-1-03) — a card's steps are read when the card is selected.
//
// The Unscheduled list now arrives as summary rows only (no steps). Opening
// a card fetches the job (GET work_item/{id}, 555) and this helper picks out
// THAT card's steps. The card's `work_task_ids` is the contract: it holds
// exactly the unscheduled steps, already in the pinned version's stage order,
// so the job's own task order (by id) must never decide the order shown.
//
// The fixtures below are shaped like the live responses (28 cards / 142
// steps were compared 559 vs 555-filtered on 2026-11-02 with no difference).
import assert from 'node:assert/strict';
import test from 'node:test';
import {cardStepsFromJobTasks} from './backlogCardSteps';
import type {WorkItemTask} from './plannerApi';

function task(id: number, stageKey: string, over: Partial<WorkItemTask> = {}): WorkItemTask {
  return {
    id,
    stage_key: stageKey,
    lens_key: 'lens-2',
    status: 'not_started',
    started_at: null,
    completed_at: null,
    stage_label: `Stage ${stageKey}`,
    owner_lens_label: 'Ops',
    task: `Do ${stageKey}`,
    done_when: `Done ${stageKey}`,
    expected_minutes: 10,
    estimate_status: 'n/a',
    estimate_source: 'n/a',
    ...over,
  };
}

test('steps come back in the CARD\'s order, not the job\'s task-id order', () => {
  // Job tasks are by id (s1, s7, s2); the pinned version's stage order is s1, s2, s7.
  const jobTasks = [task(1, 's1'), task(2, 's7'), task(3, 's2')];
  const {steps, missing} = cardStepsFromJobTasks({work_task_ids: [1, 3, 2]}, jobTasks);
  assert.deepEqual(steps.map((s) => s.stage_key), ['s1', 's2', 's7']);
  assert.deepEqual(steps.map((s) => s.work_task_id), [1, 3, 2]);
  assert.deepEqual(missing, []);
});

test('tasks that are not in the card (already scheduled, other actor row) are left out', () => {
  const jobTasks = [task(1, 's1'), task(2, 's2'), task(3, 's3'), task(4, 's4')];
  const {steps} = cardStepsFromJobTasks({work_task_ids: [2, 4]}, jobTasks);
  assert.deepEqual(steps.map((s) => s.work_task_id), [2, 4]);
});

test('every field the Stages panel shows is carried across, and `id` becomes `work_task_id`', () => {
  const jobTasks = [
    task(7, 's3', {
      status: 'in_progress',
      stage_label: 'Repair',
      task: 'Fix the seam',
      done_when: 'Holds pressure',
      expected_minutes: 660,
      estimate_status: 'complete',
      estimate_source: 'seed',
    }),
  ];
  const {steps} = cardStepsFromJobTasks({work_task_ids: [7]}, jobTasks);
  assert.deepEqual(steps, [
    {
      work_task_id: 7,
      stage_key: 's3',
      stage_label: 'Repair',
      status: 'in_progress',
      task: 'Fix the seam',
      done_when: 'Holds pressure',
      expected_minutes: 660,
      estimate_status: 'complete',
      estimate_source: 'seed',
    },
  ]);
});

test('a stage with no label reads as an empty string (what the backlog sent), never null', () => {
  const {steps} = cardStepsFromJobTasks({work_task_ids: [1]}, [task(1, 's1', {stage_label: null})]);
  assert.equal(steps[0].stage_label, '');
});

test('null text and null minutes stay null (null is not zero)', () => {
  const {steps} = cardStepsFromJobTasks(
    {work_task_ids: [1]},
    [task(1, 's1', {task: null, done_when: null, expected_minutes: null})],
  );
  assert.equal(steps[0].task, null);
  assert.equal(steps[0].done_when, null);
  assert.equal(steps[0].expected_minutes, null);
});

test('an id the job no longer has is REPORTED, not silently dropped', () => {
  const {steps, missing} = cardStepsFromJobTasks({work_task_ids: [1, 99, 2]}, [task(1, 's1'), task(2, 's2')]);
  assert.deepEqual(steps.map((s) => s.work_task_id), [1, 2]);
  assert.deepEqual(missing, [99]);
});

test('an empty card gives no steps and nothing missing', () => {
  const {steps, missing} = cardStepsFromJobTasks({work_task_ids: []}, [task(1, 's1')]);
  assert.deepEqual(steps, []);
  assert.deepEqual(missing, []);
});

test('the input is not mutated', () => {
  const jobTasks = [task(1, 's1'), task(2, 's2')];
  const before = JSON.stringify(jobTasks);
  cardStepsFromJobTasks({work_task_ids: [2, 1]}, jobTasks);
  assert.equal(JSON.stringify(jobTasks), before);
});
