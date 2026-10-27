import assert from 'node:assert/strict';
import test from 'node:test';
import {jobProgress, progressLabel, progressShortLabel, type ProgressTask, type StageOrderEntry} from './jobProgress';
import golden from '../fixtures/job-progress-golden.json';

for (const c of golden.cases) {
  test(`${c.id}: ${c.name}`, () => {
    const result = jobProgress(c.tasks as ProgressTask[], c.stageOrder as StageOrderEntry[]);
    assert.deepEqual(result, c.expected);
  });
}

test('jobProgress never mutates its inputs', () => {
  const tasks = structuredClone(golden.cases[2].tasks) as ProgressTask[];
  const stageOrder = structuredClone(golden.cases[2].stageOrder) as StageOrderEntry[];
  const tasksBefore = structuredClone(tasks);
  const stageOrderBefore = structuredClone(stageOrder);
  jobProgress(tasks, stageOrder);
  assert.deepEqual(tasks, tasksBefore);
  assert.deepEqual(stageOrder, stageOrderBefore);
});

test('UT-EXC-2-02: in_progress is neither finished nor blocked', () => {
  const tasks: ProgressTask[] = [
    {stage_key: 's1', status: 'in_progress'},
    {stage_key: 's2', status: 'not_started'},
  ];
  const stageOrder: StageOrderEntry[] = [
    {key: 's1', label: 'Stage 1'},
    {key: 's2', label: 'Stage 2'},
  ];
  const result = jobProgress(tasks, stageOrder);
  assert.equal(result.finished_count, 0);
  assert.equal(result.has_blocked, false);
  assert.equal(result.current_stage_key, 's1');
});

test('UT-EXC-2-04: progressLabel for every shape', () => {
  assert.equal(progressLabel({task_count: 0, finished_count: 0, has_blocked: false, current_stage_key: '', current_stage_label: ''}), 'No steps');
  assert.equal(progressLabel({task_count: 6, finished_count: 0, has_blocked: false, current_stage_key: 's1', current_stage_label: 'Triage'}), '0 of 6 done · at Triage');
  assert.equal(progressLabel({task_count: 6, finished_count: 2, has_blocked: false, current_stage_key: 's3', current_stage_label: 'Repair'}), '2 of 6 done · at Repair');
  assert.equal(progressLabel({task_count: 6, finished_count: 2, has_blocked: true, current_stage_key: 's3', current_stage_label: 'Repair'}), '2 of 6 done · blocked at Repair');
  assert.equal(progressLabel({task_count: 6, finished_count: 6, has_blocked: false, current_stage_key: '', current_stage_label: ''}), 'Done');
});

test('progressShortLabel: the "N of M" chip form', () => {
  assert.equal(progressShortLabel({task_count: 6, finished_count: 2, has_blocked: false, current_stage_key: 's3', current_stage_label: 'Repair'}), '2 of 6');
  assert.equal(progressShortLabel({task_count: 0, finished_count: 0, has_blocked: false, current_stage_key: '', current_stage_label: ''}), '0 of 0');
});
