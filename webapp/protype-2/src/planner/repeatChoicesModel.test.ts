import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {
  DEFAULT_CHOICES,
  setChoice,
  assignmentsLocked,
  choicesToRequest,
  choicesLine,
  visiblePlans,
  canDeletePlan,
  deleteConfirmLines,
  type DeleteCheck,
} from './repeatChoicesModel';

// REPEAT-2. What a repeat carries (people, jobs, assignments), and the plan's archive / delete
// rules as the screen shows them. The server decides and re-checks everything; this model only
// shapes the boxes, the request and the sentences. The second half reads the XanoScript source
// for the rules that must never drift (live proof is in the epic's Test Results).

test('UT-REPEAT2-01: everything is carried unless the planner unticks it', () => {
  assert.deepEqual(DEFAULT_CHOICES, {people: true, jobs: true, assignments: true});
  assert.deepEqual(choicesToRequest(DEFAULT_CHOICES), {skip_people: false, skip_jobs: false, skip_assignments: false});
});

test('UT-REPEAT2-02: no people means no assignments, and the box is locked', () => {
  const off = setChoice(DEFAULT_CHOICES, 'people', false);
  assert.deepEqual(off, {people: false, jobs: true, assignments: false});
  assert.equal(assignmentsLocked(off), true);
  assert.deepEqual(setChoice(off, 'assignments', true), off, 'cannot be ticked while people is off');
  assert.deepEqual(choicesToRequest(off), {skip_people: true, skip_jobs: false, skip_assignments: true});
  const back = setChoice(off, 'people', true);
  assert.equal(back.people, true);
  assert.equal(assignmentsLocked(back), false);
});

test('UT-REPEAT2-03: jobs and assignments are independent of each other', () => {
  assert.deepEqual(setChoice(DEFAULT_CHOICES, 'jobs', false), {people: true, jobs: false, assignments: true});
  assert.deepEqual(setChoice(DEFAULT_CHOICES, 'assignments', false), {people: true, jobs: true, assignments: false});
});

test('UT-REPEAT2-04: one plain line says what comes along', () => {
  assert.equal(choicesLine(DEFAULT_CHOICES), 'Carrying over: people, jobs and assignments.');
  assert.equal(choicesLine({people: true, jobs: false, assignments: true}), 'Carrying over: people and assignments. Jobs are left out.');
  assert.equal(choicesLine({people: false, jobs: false, assignments: false}), 'Only the plan itself is made: no people, no jobs, no assignments.');
});

test('UT-REPEAT2-05: archived plans are hidden unless asked for', () => {
  const plans = [{id: 1, isArchived: false}, {id: 2, isArchived: true}];
  assert.deepEqual(visiblePlans(plans, false).map(p => p.id), [1]);
  assert.deepEqual(visiblePlans(plans, true).map(p => p.id), [1, 2]);
});

test('UT-REPEAT2-06: only an admin is offered Delete; the confirm names what goes', () => {
  assert.equal(canDeletePlan(true), true);
  assert.equal(canDeletePlan(false), false);
  const ok: DeleteCheck = {allowed: true, code: '', message: '', name: 'Week 12', counts: {people: 3, days: 5, jobs: 10, steps: 20, slots: 14}, frees_repeat_date: true};
  const lines = deleteConfirmLines(ok);
  assert.match(lines[0], /Week 12/);
  assert.ok(lines.some(l => /3 people/.test(l) && /5 days/.test(l) && /10 jobs/.test(l) && /14 slots/.test(l)));
  assert.ok(lines.some(l => /cannot be undone/i.test(l)));
  assert.ok(lines.some(l => /repeat/i.test(l)), 'says the date is freed for a new repeat');
  const refused: DeleteCheck = {...ok, allowed: false, code: 'E-P3A-001', message: 'This plan has work recorded against it. Archive it instead. (E-P3A-001)'};
  assert.deepEqual(deleteConfirmLines(refused), [refused.message]);
});

// ── the server rules, read from source ──────────────────────────────────────────────────────────
const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

test('UT-REPEAT2-07: the choices are SKIP flags decided in one place, and people-off forces assignments-off', () => {
  const plan = read('functions/repeat/build_plan.xs');
  for (const f of ['skip_people', 'skip_jobs', 'skip_assignments']) assert.match(plan, new RegExp(`bool ${f}\\?`), f);
  assert.match(plan, /choices\s*:/, 'the decision travels with the plan to the copy');
  for (const f of ['functions/repeat/preview.xs', 'functions/repeat/create_plan.xs']) {
    assert.match(read(f), /skip_people: \$input\.skip_people/, `${f} passes the choice on explicitly`);
  }
  assert.match(read('functions/repeat/plan_work.xs'), /skip_assignments/, 'the slot planner honours it');
  assert.ok(!/skip_people|skip_jobs|skip_assignments/.test(read('ai/tool/plan_repeat.xs')), 'the AI tool cannot skip anything');
});

test('UT-REPEAT2-08: delete is an admin person, a no-history plan, one transaction, every table', () => {
  const api = read('apis/planner/688_workspace_workspace_id_DELETE.xs');
  assert.match(api, /function\.run "usr\/assert_team_admin"/, 'admin only');
  assert.match(api, /function\.run "copilot\/assert_person_only"/, 'never an AI');
  assert.match(api, /function\.run "planner\/assert_workspace"/, 'own account only');
  assert.match(api, /function\.run "planner\/delete_check"/);
  assert.match(api, /function\.run "planner\/delete_workspace_cascade"/);
  assert.match(api, /plan\.deleted/);
  assert.match(api, /plan\.delete_refused/);
  const check = read('functions/planner/delete_check.xs');
  for (const t of ['plan_publication', 'activity_log', 'work_item_origin', 'work_item_exception', 'work_item_unmatched_line', 'order_route']) {
    assert.match(check, new RegExp(`db\\.query ${t} `), `history check reads ${t}`);
  }
  assert.ok(!/db\.(add|patch|del)/.test(check), 'the check only reads');
  const cascade = read('functions/planner/delete_workspace_cascade.xs');
  assert.match(cascade, /db\.transaction/);
  for (const t of ['planner_task_review', 'planner_task_start_override', 'planner_task_work_task', 'planner_task', 'planner_timeline',
    'work_item_line', 'work_item_time_window', 'work_task', 'work_item', 'planner_agent', 'planner_workspace_map', 'plan_repeat', 'planner_workspace']) {
    assert.match(cascade, new RegExp(`db\\.del ${t} `), `cascade deletes ${t}`);
  }
  for (const t of ['plan_publication', 'activity_log', 'plan_change_log', 'work_item_origin', 'live_day_addition']) {
    assert.ok(!new RegExp(`db\\.del ${t} `).test(cascade), `history table ${t} is never deleted`);
  }
  assert.ok(!/field_name = "(workspace_id|work_item_id|planner_task_id|timeline_id)"/.test(cascade), 'every row is deleted by its own id');
});
