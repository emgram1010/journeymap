import assert from 'node:assert/strict';
import test from 'node:test';
import {deriveJobStatus, groupTasksByRole, jobStatusLabel, movedUnits, summarizeUnits, tasksFromVersion, unitRowLabel, type TaskStatus, type VersionSnapshot} from './jobModel';

const t = (status: TaskStatus) => ({status});

// ── deriveJobStatus ────────────────────────────────────────────────

test('UT-JOB-1-01: all not_started -> open', () => {
  assert.equal(deriveJobStatus([t('not_started'), t('not_started')]), 'open');
});

test('UT-JOB-1-02: one in_progress -> in_progress', () => {
  assert.equal(deriveJobStatus([t('not_started'), t('in_progress'), t('not_started')]), 'in_progress');
});

test('UT-JOB-1-03: one blocked beats everything else being done', () => {
  assert.equal(deriveJobStatus([t('done'), t('blocked'), t('done')]), 'blocked');
  // Blocked wins even when nothing else has started.
  assert.equal(deriveJobStatus([t('not_started'), t('blocked')]), 'blocked');
});

test('UT-JOB-1-04: all done -> completed', () => {
  assert.equal(deriveJobStatus([t('done'), t('done')]), 'completed');
});

test('UT-JOB-1-05: done + skipped only -> completed', () => {
  assert.equal(deriveJobStatus([t('done'), t('skipped')]), 'completed');
  // Skipped alone still counts as finished with.
  assert.equal(deriveJobStatus([t('skipped'), t('skipped')]), 'completed');
});

test('UT-JOB-1-06: some done, rest not_started -> in_progress', () => {
  assert.equal(deriveJobStatus([t('done'), t('not_started')]), 'in_progress');
});

test('UT-JOB-1-07: cancelled wins even when every task is done', () => {
  assert.equal(deriveJobStatus([t('done'), t('done')], true), 'cancelled');
  assert.equal(deriveJobStatus([t('blocked')], true), 'cancelled');
  assert.equal(deriveJobStatus([], true), 'cancelled');
});

test('deriveJobStatus: a job with no tasks is open, not completed', () => {
  // "every task is finished" is vacuously true for an empty list, so
  // this is the case a naive implementation gets wrong.
  assert.equal(deriveJobStatus([]), 'open');
});

// ── tasksFromVersion ───────────────────────────────────────────────

/**
 * Three stages. Stage 1 and 2 are owned by work-doing rows; stage 3 is
 * owned by a row that does NO planned work, so it should produce
 * nothing and be reported.
 */
const GOLDEN: VersionSnapshot = {
  stages: [
    {key: 's1', label: 'Enquiry', owner_lens_key: 'sales'},
    {key: 's2', label: 'Quote', owner_lens_key: 'ops'},
    {key: 's3', label: 'Context', owner_lens_key: 'description'},
  ],
  lenses: [
    {key: 'description', label: 'Description', actor_type: '', does_planned_work: false},
    {key: 'sales', label: 'Sales', actor_type: 'internal', does_planned_work: true},
    {key: 'ops', label: 'Ops', actor_type: 'internal', does_planned_work: true},
  ],
  cells: [
    {stage_key: 's1', lens_key: 'sales', task: 'Log the enquiry', duration_minutes: 15},
    {stage_key: 's1', lens_key: 'ops', task: 'Check stock', duration_minutes: 10},
    {stage_key: 's1', lens_key: 'description', task: 'Customer gets in touch'},
    {stage_key: 's2', lens_key: 'ops', task: 'Draft the quote', duration_minutes: 30},
    // A work-doing row with NO task text — must not become a task.
    {stage_key: 's2', lens_key: 'sales', task: '   '},
    {stage_key: 's3', lens_key: 'description', task: 'Background only'},
  ],
};

test('UT-JOB-1-08: tasksFromVersion returns the expected keys in stage order', () => {
  const {tasks} = tasksFromVersion(GOLDEN);
  assert.deepEqual(
    tasks.map((x) => `${x.stage_key}/${x.lens_key}${x.is_owner ? '*' : ''}`),
    [
      's1/sales*', // owner of stage 1
      's1/ops', // extra work-doing row with a task
      's2/ops*', // owner of stage 2
    ],
  );
});

test('UT-JOB-1-08: the owner of each stage comes first', () => {
  const {tasks} = tasksFromVersion(GOLDEN);
  const s1 = tasks.filter((x) => x.stage_key === 's1');
  assert.equal(s1[0].is_owner, true);
  assert.equal(s1[0].lens_key, 'sales');
});

test('UT-JOB-1-09: a stage owned by a non-work row produces no task, and is reported', () => {
  const {tasks, skipped} = tasksFromVersion(GOLDEN);
  assert.equal(tasks.some((x) => x.stage_key === 's3'), false);
  assert.deepEqual(skipped, [{stage_key: 's3', reason: 'owner_does_no_planned_work'}]);
});

test('tasksFromVersion: a work-doing row with blank task text is not a task', () => {
  // s2/sales does planned work but its cell holds only whitespace.
  const {tasks} = tasksFromVersion(GOLDEN);
  assert.equal(tasks.some((x) => x.stage_key === 's2' && x.lens_key === 'sales'), false);
});

test('tasksFromVersion: an owner cell with no task text STILL produces a task', () => {
  // The owning row is the stage's work by definition, so it is not
  // conditional on cell text the way extra rows are.
  const {tasks} = tasksFromVersion({
    stages: [{key: 's1', owner_lens_key: 'sales'}],
    lenses: [{key: 'sales', does_planned_work: true}],
    cells: [],
  });
  assert.deepEqual(tasks, [{stage_key: 's1', lens_key: 'sales', is_owner: true}]);
});

test('tasksFromVersion: a stage with no owner, or a missing owner row, is reported', () => {
  const noOwner = tasksFromVersion({
    stages: [{key: 's1', owner_lens_key: null}],
    lenses: [{key: 'sales', does_planned_work: true}],
    cells: [],
  });
  assert.deepEqual(noOwner.skipped, [{stage_key: 's1', reason: 'no_owner'}]);

  const danglingOwner = tasksFromVersion({
    stages: [{key: 's1', owner_lens_key: 'ghost'}],
    lenses: [{key: 'sales', does_planned_work: true}],
    cells: [],
  });
  assert.deepEqual(danglingOwner.skipped, [{stage_key: 's1', reason: 'owner_lens_missing'}]);
});

test('UT-JOB-1-08: three stages each with a working owner yield exactly three tasks', () => {
  // The acceptance line from US-JOB-1-02, stated directly.
  const {tasks, skipped} = tasksFromVersion({
    stages: [
      {key: 'a', owner_lens_key: 'r'},
      {key: 'b', owner_lens_key: 'r'},
      {key: 'c', owner_lens_key: 'r'},
    ],
    lenses: [{key: 'r', does_planned_work: true}],
    cells: [],
  });
  assert.equal(tasks.length, 3);
  assert.deepEqual(skipped, []);
  assert.deepEqual(tasks.map((x) => x.stage_key), ['a', 'b', 'c']);
});

test('tasksFromVersion: an empty version produces nothing and reports nothing', () => {
  assert.deepEqual(tasksFromVersion({stages: [], lenses: [], cells: []}), {tasks: [], skipped: []});
});

// ── jobStatusLabel ─────────────────────────────────────────────────

test('jobStatusLabel: every derived status has planner words', () => {
  assert.equal(jobStatusLabel('open'), 'Not started');
  assert.equal(jobStatusLabel('in_progress'), 'In progress');
  assert.equal(jobStatusLabel('blocked'), 'Blocked');
  assert.equal(jobStatusLabel('completed'), 'Done');
  assert.equal(jobStatusLabel('cancelled'), 'Cancelled');
});

test('jobStatusLabel: an unknown status is shown as it arrived, never blanked', () => {
  assert.equal(jobStatusLabel('awaiting_parts'), 'awaiting_parts');
  assert.equal(jobStatusLabel(''), '');
});

// ── groupTasksByRole (US-QUE-1-04) ────────────────────────────────────

const step = (lensKey: string, label: string | null = null) => ({lens_key: lensKey, owner_lens_label: label});

test('UT-QUE-1-04-01: one role -> null (flat, no extra tier)', () => {
  assert.equal(groupTasksByRole([step('tech'), step('tech'), step('tech')]), null);
  assert.equal(groupTasksByRole([]), null, 'zero roles is still "flat" — nothing to group');
});

test('UT-QUE-1-04-02: two roles -> one group per role, first-seen order', () => {
  const groups = groupTasksByRole([step('tech'), step('inspector'), step('tech')]);
  assert.deepEqual(groups?.map((g) => g.lensKey), ['tech', 'inspector']);
});

test('UT-QUE-1-04-03: each group keeps its tasks in the order they arrived', () => {
  const a = {lens_key: 'tech', owner_lens_label: null, id: 1};
  const b = {lens_key: 'tech', owner_lens_label: null, id: 2};
  const c = {lens_key: 'inspector', owner_lens_label: null, id: 3};
  const groups = groupTasksByRole([a, c, b]);
  assert.deepEqual(groups?.find((g) => g.lensKey === 'tech')?.tasks.map((t) => t.id), [1, 2]);
});

test('UT-QUE-1-04-04: a group\'s label is the owner label, falling back to the key', () => {
  const groups = groupTasksByRole([step('tech', 'Repair Tech'), step('inspector', null)]);
  assert.equal(groups?.find((g) => g.lensKey === 'tech')?.lensLabel, 'Repair Tech');
  assert.equal(groups?.find((g) => g.lensKey === 'inspector')?.lensLabel, 'inspector');
});

// ── summarizeUnits / movedUnits (QTY-1) ───────────────────────────────

test('UT-QTY-1-01-01: quantities across several item types sum to a total', () => {
  const s = summarizeUnits([
    {item_label: 'Bouncer', unit: 'units', quantity: 8},
    {item_label: 'Blower', unit: 'units', quantity: 2},
  ]);
  assert.equal(s.totalQuantity, 10);
  assert.deepEqual(s.lines.map((l) => `${l.quantity} ${l.unit} ${l.item_label}`), ['8 units Bouncer', '2 units Blower']);
});

test('UT-QTY-1-01-02: no lines is null, not zero — "none recorded" must not look like a real 0', () => {
  assert.deepEqual(summarizeUnits([]), {totalQuantity: null, lines: []});
});

test('UT-QTY-1-01-03: a zero-quantity line is still a line, and totals to a real 0', () => {
  const s = summarizeUnits([{item_label: 'Bouncer', unit: 'units', quantity: 0}]);
  assert.equal(s.totalQuantity, 0, 'a genuine zero, distinguishable from null above');
  assert.equal(s.lines.length, 1);
});

test('UT-QTY-1-01-04: a line with no label names itself rather than rendering blank', () => {
  assert.equal(summarizeUnits([{item_key: 'bouncer', quantity: 1}]).lines[0].item_label, 'bouncer');
  assert.equal(summarizeUnits([{quantity: 1}]).lines[0].item_label, 'Unnamed item');
  assert.equal(summarizeUnits([{quantity: 1}]).lines[0].unit, 'units');
});

test('UT-QTY-1-02-01: a link reports how many units it moved, naming the other job', () => {
  const moved = movedUnits([
    {work_item_id: 141, title: 'Garcia party — damaged', moved_lines: [{quantity: 1}, {quantity: 1}]},
  ]);
  assert.deepEqual(moved, [{workItemId: 141, title: 'Garcia party — damaged', quantity: 2}]);
});

test('UT-QTY-1-02-02: nothing moved means no lineage to render', () => {
  assert.deepEqual(movedUnits([]), []);
  assert.deepEqual(movedUnits([{work_item_id: 141, moved_lines: []}]), [], 'a link that moved nothing is dropped');
  assert.deepEqual(movedUnits([{work_item_id: 141, moved_lines: null}]), [], 'older data with no moved_lines at all');
});

test('UT-QTY-1-02-03: an untitled linked job is still named by its number', () => {
  assert.equal(movedUnits([{work_item_id: 141, moved_lines: [{quantity: 3}]}])[0].title, 'Job #141');
});

// ── unitRowLabel (US-QTY-1-03) ────────────────────────────────────────

test('UT-QTY-1-03-01: an unsplit job just states what it holds', () => {
  assert.equal(unitRowLabel({unit_total: 10, units_moved_out: 0}), '10 ordered');
});

test('UT-QTY-1-03-02: a split job reconciles — ordered is derived from the parts', () => {
  assert.equal(unitRowLabel({unit_total: 8, units_moved_out: 2}), '10 ordered · 8 here · 2 moved out');
});

test('UT-QTY-1-03-03: a job whose units ALL moved out still reconciles', () => {
  // Job 125 live: holds 0, moved 1 to its child. The row must not read "0 ordered".
  assert.equal(unitRowLabel({unit_total: 0, units_moved_out: 1}), '1 ordered · 0 here · 1 moved out');
});

test('UT-QTY-1-03-04: absent fields are unknown, not zero — an old response says nothing', () => {
  assert.equal(unitRowLabel({}), null, 'endpoint predates the fields');
  assert.equal(unitRowLabel({unit_total: 0, units_moved_out: 0}), null, 'genuinely no units');
});
