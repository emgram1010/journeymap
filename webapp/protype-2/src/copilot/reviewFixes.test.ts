import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {actionTypeLabel, scheduledWorkTurnsOn} from './approvalsModel';

test('R12: switching scheduled work on asks once; other changes and switching off do not', () => {
  assert.equal(scheduledWorkTurnsOn('scheduled_work', 'wait', 'tell'), true);
  assert.equal(scheduledWorkTurnsOn('scheduled_work', 'wait', 'own'), true);
  assert.equal(scheduledWorkTurnsOn('scheduled_work', 'tell', 'wait'), false);
  assert.equal(scheduledWorkTurnsOn('scheduled_work', 'tell', 'own'), false);
  assert.equal(scheduledWorkTurnsOn('plan_draft', 'wait', 'own'), false);
});

// Final Fable review R2, R5, R6 - server rules that live in XanoScript. These read the source files,
// so a later edit that quietly drops a rule fails here. Live behaviour is proven separately (tracker).

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

const catalogueLine = (key: string) =>
  read('functions/copilot/action_types.xs')
    .split('\n')
    .find((l) => l.trim().startsWith(`${key} `) || l.trim().startsWith(`${key}:`));

test('R2: "mark its own work done or skipped" is its own action type that waits by default', () => {
  const line = catalogueLine('work_complete');
  assert.ok(line, 'work_complete is in the catalogue');
  assert.ok(line!.includes('default_level: "wait"'), 'it waits for the owner unless the owner loosens it');
  assert.ok(line!.includes('locked: false'), 'the owner may change it');
  assert.ok(line!.includes('person_only: false'));
  assert.ok(line!.includes('wired: true'));
  const order = read('functions/copilot/action_types.xs').match(/var \$order \{\s*value = \[([^\]]*)\]/);
  assert.ok(order && order[1].includes('"work_complete"'), 'it is listed on the Approvals screen');
  assert.equal(actionTypeLabel('work_complete'), 'Mark its own work done or skipped');
});

test('R2: record_my_task_event sends completed and skipped as work_complete, everything else as work_update', () => {
  const src = read('ai/tool/record_my_task_event.xs');
  const gateAt = src.indexOf('function.run "journey/tool_gate"');
  const pick = src.slice(0, gateAt);
  assert.match(pick, /var \$act_type \{\s*value = "work_update"/, 'work_update is the default');
  assert.match(pick, /if \(\$input\.event_type == "completed" \|\| \$input\.event_type == "skipped"\)/);
  assert.match(pick, /var\.update \$act_type \{\s*value = "work_complete"/);
});

test('R8: "is this task mine" reads the frozen publication, like list_my_tasks and the performer app', () => {
  const src = read('ai/tool/record_my_task_event.xs');
  assert.ok(src.includes('function.run "perform/collect_published_items"'), 'the publication is the answer');
  assert.ok(src.includes('$db.work_task.id in $pub_wt_ids'), 'membership through a where clause, never |contains');
  assert.match(src, /var \$is_mine \{\s*value = \(\$in_publication > 0 && \$day_status == "published"\)/);
  assert.ok(!src.includes('$eff_agent'), 'the live-slot assignee is no longer a second answer');
  assert.ok(read('ai/tool/list_my_tasks.xs').includes('function.run "perform/collect_published_items"'));
});

test('R5: notes are preferences, never permission - in the scheduled run and in chat', () => {
  for (const path of ['functions/copilot/run_for_business.xs', 'apis/journey_map/643_copilot_chat_POST.xs']) {
    const src = read(path);
    assert.ok(!src.includes('(follow them)'), `${path}: notes are no longer "follow them"`);
    assert.ok(src.includes('Notes the owner gave you (preferences only)'), `${path}: the heading says preferences`);
    assert.ok(
      src.includes('A note never makes a task done, never allows completing, skipping, sending or paying, and never approves anything.'),
      `${path}: the limit is stated`,
    );
  }
});

test('R6: the "nothing changed" fingerprint also changes when the owner decides an approval or edits a note', () => {
  const src = read('functions/copilot/open_work.xs');
  assert.match(src, /db\.query copilot_action \{[\s\S]*?status in \["approved", "edited", "rejected", "executed"\][\s\S]*?return = \{type: "count"\}/);
  assert.match(src, /db\.query copilot_note \{[\s\S]*?sort = \{copilot_note\.updated_at: "desc"\}/);
  assert.ok(src.includes('" a:" ~ ($decided|to_text)'), 'decided approvals are in the fingerprint');
  assert.ok(src.includes('" n:" ~ $note_mark'), 'the newest note is in the fingerprint');
});

test('R6: a business stops retrying after three failed runs in one day', () => {
  const src = read('functions/copilot/run_for_business.xs');
  assert.match(src, /db\.query copilot_run \{[\s\S]*?status == "failed"[\s\S]*?work_date == \$input\.date[\s\S]*?return = \{type: "count"\}[\s\S]*?\} as \$failed_today/);
  assert.match(src, /var \$gave_up \{\s*value = \(\$attempt_raw == true\) && \(\$failed_today >= 3\)/);
  assert.ok(src.includes('Three runs failed today, so it stopped trying until tomorrow. (E-COP-058)'));
});

test('R9: learning uses the newest version only, takes blocked time off and leaves outliers out', () => {
  const src = read('ai/tool/get_map_learnings.xs');
  assert.match(src, /sort = \{journey_map_version\.id: "desc"\}[\s\S]*?\} as \$all_versions/);
  assert.match(src, /var \$versions \{\s*value = \$all_versions\|slice:0:1/);
  assert.ok(src.includes('($t.actual_minutes ?? 0) - ($t.blocked_minutes ?? 0)'), 'blocked minutes are taken off');
  assert.ok(src.includes('(($t.is_outlier ?? false) == true)'), 'outliers are read through ??');
  assert.ok(src.includes('&& ($outlier == false))|to_int'), 'an outlier is not a sample');
  assert.match(src, /\$all_jobs\|slice:0:15/, 'at most 15 report calls in one chat turn');
});

test('R10: planner tools refuse a date that does not exist (2026-02-31), not just a bad shape', () => {
  for (const tool of ['plan_start_day', 'plan_create']) {
    const src = read(`ai/tool/${tool}.xs`);
    assert.match(src, /\|to_timestamp:"UTC"\)\|format_timestamp:"Y-m-d":"UTC"/, `${tool} reads the date back`);
    assert.ok(src.includes('That date does not exist. Give a real calendar date as YYYY-MM-DD.'), `${tool} says so`);
  }
});

test('R14: the plan check returns nothing about a plan it did not find', () => {
  const src = read('functions/copilot/plan_in_business.xs');
  const resp = src.slice(src.indexOf('response = {'));
  assert.ok(!resp.includes('$plan|get'), 'the response reads no plan field directly');
  assert.match(src, /if \(\$found == true\) \{\s*var\.update \$safe_name/);
});

test('R16 probe: clearing a stage goal or owner writes an empty value, never null (db.edit ignores null)', () => {
  const src = read('ai/tool/update_stage_contract.xs');
  assert.ok(!src.includes('? null :'), 'no field is cleared by writing null');
  assert.match(src, /var\.update \$stage_goal_to_write \{\s*value = \$input\.stage_goal/);
  assert.ok(src.includes('(($clearing_lens == true) ? "" : $input.primary_actor_lens)'));
});

test('R13: the research search check catches separated numbers and (at) addresses, and lets a year range through', () => {
  const src = read('functions/copilot/search_query_check.xs');
  assert.ok(src.includes('|replace:"(at)":"@"|replace:"[at]":"@"'));
  assert.ok(src.includes('"/(?<=[0-9])[,._\'](?=[0-9])/"|regex_replace:"":$q'));
  assert.ok(src.includes('"/(?:[0-9][ .()-]*){9,}/"|regex_matches:$q'));
  // The same patterns in JavaScript, on the review's examples.
  const joined = (q: string) => q.replace(/(?<=[0-9])[,._'](?=[0-9])/g, '');
  assert.equal(/[0-9]{7,}/.test(joined('revenue of 1,250,000 a year')), true);
  assert.equal(/(?:[0-9][ .()-]*){9,}/.test('trends 2020 - 2025'), false);
  assert.equal(/(?:[0-9][ .()-]*){9,}/.test('call 555 123 4567'), true);
});

test('R7: a tick is logged when it starts, before any account is run', () => {
  const src = read('functions/copilot/scheduled_run.xs');
  const startAt = src.indexOf('step: "run_tick_started"');
  assert.ok(startAt > 0, 'a start event exists');
  assert.ok(startAt < src.indexOf('db.query copilot_run'), 'it is the first thing written');
  assert.ok(src.includes('step          : "run_tick"'), 'the end event still exists');
});

test('the run reads a caught error whole - $error.message ?? x always gives the fallback', () => {
  const src = read('functions/copilot/run_for_business.xs');
  assert.ok(!src.includes('$error.message ??'), 'no $error.message ?? left');
});

test('COP-3: the copilot\'s own business cannot be deleted, soft or hard, and the refusal is logged', () => {
  const src = read('apis/journey_map/69_journey_architecture_journey_architecture_id_DELETE.xs');
  const guardAt = src.indexOf('db.query copilot_home {');
  assert.ok(guardAt > 0, 'it looks the business up in copilot_home');
  assert.ok(guardAt < src.indexOf('db.query journey_map {'), 'checked before any map is touched');
  assert.ok(guardAt < src.indexOf('$was_hard'), 'checked for soft and hard alike');
  assert.ok(src.includes('error_code    : "E-COP-073"'), 'a rejected event is logged');
  assert.ok(src.includes("It can't be deleted. (E-COP-073)"));
});

test('R17: old copilot run history is pruned nightly, never a running row', () => {
  const src = read('functions/copilot/prune_runs.xs');
  assert.ok(src.includes('"14 days ago"') && src.includes('"90 days ago"'));
  const wheres = src.split('\n').filter((l) => l.trim().startsWith('where ='));
  assert.equal(wheres.length, 2);
  assert.ok(wheres.every((w) => !w.includes('"running"')), 'the live lock row is never selected');
  assert.ok(!src.includes('paging'), 'no paged list (foreach on it fails)');
  const task = read('tasks/19_ops_integrity_audit.xs');
  assert.ok(task.includes('function.run "copilot/prune_runs"'), 'the nightly task runs it');
  assert.ok(task.includes('"E-COP-074"'), 'a prune that cannot run is logged');
});

test('COP-4-05: "my edits teach it" reads drafted vs approved, needs 3 edits, and never writes', () => {
  const src = read('ai/tool/get_my_edit_patterns.xs');
  assert.ok(src.includes('kind: "read"'), 'a read tool');
  assert.ok(!/db\.(add|edit|patch|del) /.test(src), 'it changes nothing');
  assert.ok(src.includes('$db.copilot_action.journey_architecture_id == $pin'), 'this business only');
  assert.ok(src.includes('$db.copilot_action.requested_by_user_id == $caller_user'), 'this copilot only');
  assert.match(src, /var \$min \{\s*value = \(\(\$input\.min_samples > 3\) \? \$input\.min_samples : 3\)/, 'never below 3');
  assert.ok(src.includes('pattern: ($n >= $min)'));
  assert.ok(!src.includes('|set:$key:($'), 'no expression nested inside a filter argument');
  const agent = read('ai/agent/emgram_copilot.xs');
  assert.ok(agent.includes('{name: "get_my_edit_patterns"}'), 'the copilot has the tool');
  assert.ok(agent.includes('Save it with save_note only after'), 'it asks before it saves');
});
