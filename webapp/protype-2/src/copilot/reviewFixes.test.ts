import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {actionTypeLabel} from './approvalsModel';

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

test('the run reads a caught error whole - $error.message ?? x always gives the fallback', () => {
  const src = read('functions/copilot/run_for_business.xs');
  assert.ok(!src.includes('$error.message ??'), 'no $error.message ?? left');
});
