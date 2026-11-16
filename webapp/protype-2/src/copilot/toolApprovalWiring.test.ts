import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// Final Fable review R1 - a copilot tool that WRITES must declare its action type to the gate, or
// the owner's approval level for it does nothing. This reads the tool source files, so a new write
// tool that forgets (or a level that is quietly un-wired) fails here instead of in production.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

const WIRED: Record<string, string> = {
  plan_create: 'plan_draft',
  plan_accept_map: 'plan_draft',
  plan_add_job: 'plan_draft',
  plan_add_person: 'plan_draft',
  plan_start_day: 'plan_draft',
  plan_schedule_step: '$act_type',
  plan_schedule_card: '$act_type',
  plan_unschedule_step: 'plan_draft',
  plan_set_start_time: '$act_type',
  plan_set_time_window: '$act_type',
  record_my_task_event: '$act_type',
  save_note: 'note_internal',
};

for (const [tool, actType] of Object.entries(WIRED)) {
  test(`R1: ${tool} declares "${actType}" to the gate and reports how it ended`, () => {
    const src = read(`ai/tool/${tool}.xs`);
    const gateCalls = src.match(/function\.run "journey\/tool_gate" \{[\s\S]*?\} as \$cop1_gate/g) ?? [];
    assert.equal(gateCalls.length, 1, 'exactly one gate call');
    const gate = gateCalls[0];
    assert.ok(gate.includes(`tool: "${tool}"`), 'the gate is told the tool name');
    assert.ok(gate.includes('kind: "write"'), 'it is a write');
    const declared = actType.startsWith('$') ? `act_type: ${actType}` : `act_type: "${actType}"`;
    assert.ok(gate.includes(declared), 'the action type is declared');
    assert.ok(gate.includes('act_payload: {'), 'the exact input is sent, so "waits for you" can store it');
    assert.ok(gate.includes('act_summary: $act_summary'), 'the owner gets a sentence to read');
    assert.ok(gate.includes('act_approval_id: $input.approval_id'), 'an approved action can be run');
    assert.match(src, /int approval_id\?/, 'the tool accepts approval_id');
    // The write sits inside a try, and the ending is reported once, after it.
    const tryAt = src.indexOf('try_catch {');
    const closeAt = src.indexOf('function.run "copilot/action_close"');
    assert.ok(tryAt > src.indexOf(gate), 'the body runs inside try_catch, after the gate');
    assert.ok(closeAt > tryAt, 'copilot/action_close is called after the try');
    assert.equal(src.split('function.run "copilot/action_close"').length - 1, 1, 'called exactly once');
    // The payload never carries the ticket.
    const payload = gate.slice(gate.indexOf('act_payload: {'), gate.indexOf('act_summary'));
    assert.ok(!payload.includes('ticket'), 'the run ticket is never stored in an approval');
  });
}

test('R1: every action type a tool declares exists in the catalogue and is marked as used', () => {
  const catalogue = read('functions/copilot/action_types.xs');
  const declared = [...Object.values(WIRED).filter((t) => !t.startsWith('$')), 'work_update', 'work_complete', 'plan_draft', 'plan_live_change'];
  for (const actType of new Set(declared)) {
    const line = catalogue.split('\n').find((l) => l.trim().startsWith(`${actType} `) || l.trim().startsWith(`${actType}:`));
    assert.ok(line, `${actType} is in copilot/action_types`);
    assert.ok(line!.includes('wired: true'), `${actType} says a copilot tool uses it`);
  }
});

test('R1: the gate looks the level up in the business the conversation is pinned to', () => {
  const gate = read('functions/journey/tool_gate.xs');
  assert.ok(gate.includes('act_architecture_id: $act_arch'), 'the action gate is given the resolved business');
  assert.match(gate, /if \(\$act_arch == 0 && \$pin != 0\)/, 'a tool that names no map and no business uses the pin');
});

test('R1: the ending is passed on with its own kind of error, from one shared function', () => {
  const close = read('functions/copilot/action_close.xs');
  assert.ok(close.includes('function.run "copilot/action_finish"'), 'it reports to the approval list');
  for (const kind of ['accessdenied', 'notfound', 'inputerror']) {
    assert.ok(close.includes(`error_type = "${kind}"`), `${kind} is passed on`);
  }
});

test('COP-5-01: a change to a live day is plan_live_change, which always waits (locked), chosen before the gate', () => {
  const line = read('functions/copilot/action_types.xs').split('\n').find((l) => l.trim().startsWith('plan_live_change '));
  assert.ok(line && line.includes('default_level: "wait"') && line.includes('locked: true'));
  for (const tool of ['plan_schedule_step', 'plan_schedule_card', 'plan_set_start_time', 'plan_set_time_window']) {
    const src = read(`ai/tool/${tool}.xs`);
    assert.ok(src.indexOf('function.run "copilot/live_target"') < src.indexOf('function.run "journey/tool_gate"'), `${tool}: chosen before the gate`);
    assert.ok(src.includes('"plan_live_change" : "plan_draft"'), `${tool}: live -> plan_live_change`);
    assert.ok(src.includes('|| $act_type == "plan_live_change") {'), `${tool}: an approved live change is no longer refused`);
  }
  const lt = read('functions/copilot/live_target.xs');
  assert.ok(lt.includes('function.run "usr/tool_caller"') && lt.includes('== $account_id'), "only the caller's own account can be live");
  assert.ok(read('ai/tool/plan_unschedule_step.xs').includes('act_type: "plan_draft"'), 'unschedule keeps the screen rule (no unscheduling from a live day)');
});
