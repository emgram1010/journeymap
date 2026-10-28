import assert from 'node:assert/strict';
import test from 'node:test';
import {jobProgress, progressFromTasks, progressLabel, progressShortLabel, type ProgressTask, type StageOrderEntry} from './jobProgress';
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

// The sentence the founder actually reads in the job view goes through
// progressFromTasks, so it is pinned here rather than left untested.
test('progressFromTasks: 555 task order is the stage order', () => {
  const tasks = [
    {stage_key: 's1', status: 'done', stage_label: 'Triage'},
    {stage_key: 's2', status: 'skipped', stage_label: 'Quote'},
    {stage_key: 's3', status: 'not_started', stage_label: 'Repair'},
    {stage_key: 's4', status: 'not_started', stage_label: 'Return'},
  ];
  assert.deepEqual(progressFromTasks(tasks), {
    task_count: 4,
    finished_count: 2,
    has_blocked: false,
    current_stage_key: 's3',
    current_stage_label: 'Repair',
  });
  assert.equal(progressLabel(progressFromTasks(tasks)), '2 of 4 done · at Repair');
});

test('progressFromTasks: two owner rows at one stage — one done, the stage is still current', () => {
  const result = progressFromTasks([
    {stage_key: 's1', status: 'done', stage_label: 'Triage'},
    {stage_key: 's1', status: 'not_started', stage_label: 'Triage'},
    {stage_key: 's2', status: 'not_started', stage_label: 'Repair'},
  ]);
  assert.equal(result.current_stage_key, 's1');
  assert.equal(result.finished_count, 1);
  assert.equal(result.task_count, 3);
});

test('progressFromTasks: no steps, all finished, and a blocked step', () => {
  assert.equal(progressLabel(progressFromTasks([])), 'No steps');
  assert.equal(
    progressLabel(progressFromTasks([{stage_key: 's1', status: 'done', stage_label: 'Triage'}])),
    'Done',
  );
  assert.equal(
    progressLabel(
      progressFromTasks([
        {stage_key: 's1', status: 'done', stage_label: 'Triage'},
        {stage_key: 's2', status: 'blocked', stage_label: 'Repair'},
      ]),
    ),
    '1 of 2 done · blocked at Repair',
  );
});

// A KNOWN, DELIBERATE divergence, pinned so it stays visible: 555 sorts tasks
// by work_task.id, so the client cannot see real snapshot positions and cannot
// sort an unknown stage last the way the backend does. Golden 07 is the case
// that shows it. If 555 ever returns the job's stage order, delete this test
// and feed the real order through jobProgress instead.
test('progressFromTasks: without a stage order, an unknown stage cannot sort last (vs golden 07)', () => {
  const tasks = [
    {stage_key: 's1', status: 'done', stage_label: 'Stage 1'},
    {stage_key: 's2', status: 'done', stage_label: 'Stage 2'},
    {stage_key: 'ghost-stage', status: 'not_started', stage_label: null},
    {stage_key: 's3', status: 'not_started', stage_label: 'Stage 3'},
  ];
  const golden07 = golden.cases.find((c) => c.id === 'UT-EXC-2-golden-07');
  assert.equal(golden07?.expected.current_stage_key, 's3', 'the backend sorts the ghost stage last');
  assert.equal(progressFromTasks(tasks).current_stage_key, 'ghost-stage', 'the client can only take arrival order');
  // The counts, which is what the chips and the bar show, agree either way.
  assert.equal(progressFromTasks(tasks).finished_count, golden07?.expected.finished_count);
  assert.equal(progressFromTasks(tasks).task_count, golden07?.expected.task_count);
});

test('progressFromTasks: a null stage_label falls back to the key', () => {
  const result = progressFromTasks([{stage_key: 's9', status: 'not_started', stage_label: null}]);
  assert.equal(result.current_stage_label, 's9');
});

test('progressShortLabel: the "N of M" chip form', () => {
  assert.equal(progressShortLabel({task_count: 6, finished_count: 2, has_blocked: false, current_stage_key: 's3', current_stage_label: 'Repair'}), '2 of 6');
  // Never "0 of 0" — that reads as a job underway, and the job view's own
  // sentence says "No steps" for the very same job.
  assert.equal(progressShortLabel({task_count: 0, finished_count: 0, has_blocked: false, current_stage_key: '', current_stage_label: ''}), 'No steps');
});
