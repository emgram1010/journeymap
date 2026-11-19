import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// COP-14 story 03 - the founder can plan through the outside MCP door (Claude on the Max plan), as the
// signed-in person and under that person's permissions, never as the copilot. Publish to live stays a
// button (Epic-23 D-4). The rules live in XanoScript; these tests read the source. Live proof is in
// EPIC-COP-14's Test results.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

const PLAN_TOOLS = [
  'plan_create', 'plan_accept_map', 'plan_add_job', 'plan_add_person', 'plan_start_day',
  'plan_schedule_step', 'plan_schedule_card', 'plan_unschedule_step', 'plan_set_start_time', 'plan_set_time_window',
];

test('UT-COP-14-03-01: the outside door lists all ten planner tools', () => {
  const door = read('ai/mcp_server/journey_map.xs');
  for (const t of PLAN_TOOLS) assert.match(door, new RegExp(`\\{name: "${t}"\\}`), t);
  assert.match(door, /## Planning/, 'the door tells outside assistants how to plan');
  assert.match(door, /journey_architecture_id/, 'and that they name the business');
});

test('UT-COP-14-03-02: no tool on the door publishes a plan to live', () => {
  const door = read('ai/mcp_server/journey_map.xs');
  const names = [...door.matchAll(/\{name: "([a-z_]+)"\}/g)].map((m) => m[1]);
  for (const n of names) assert.ok(!/publish_(day|plan|live)|go_live|plan_publish/.test(n), `${n} must not publish to live`);
  assert.match(door, /never publish(es)? .*to live|Publish to live is a button/i);
});

test('UT-COP-14-03-03: ONE rule picks the business: the chat\'s pin, or the business an outside person names', () => {
  const fn = read('functions/copilot/work_business.xs');
  assert.match(fn, /function "copilot\/work_business"/);
  assert.match(fn, /\$input\.pin != 0/, 'a pinned chat always wins');
  assert.match(fn, /\$input\.via == "token" && \$input\.context == "outside"/, 'only an OUTSIDE caller signed in by token may name one (review 2026-11-19: an in-app empty ticket also resolves by token)');
  assert.match(fn, /\$named_account == \$input\.account_id/, 'and only a business of their own account, re-checked here');
  assert.ok(!/db\.(add|patch|del)/.test(fn), 'it only decides, never writes');
});

test('UT-COP-14-03-04: every planner tool passes the named business to the gate and uses the one rule', () => {
  for (const t of PLAN_TOOLS) {
    const src = read(`ai/tool/${t}.xs`);
    assert.match(src, /int journey_architecture_id\?/, `${t}: takes the business`);
    assert.match(src, /function\.run "journey\/tool_gate" \{\s*input = \{journey_map_id: [^,]+, journey_architecture_id: \$input\.journey_architecture_id,/, `${t}: the gate checks it is in the caller's account`);
    assert.match(src, /function\.run "copilot\/work_business"/, `${t}: uses the one rule`);
    assert.match(src, /context: \$gate_context, named: \$input\.journey_architecture_id, account_id: \$gate_account/, `${t}: passes where the call came from and whose account`);
    assert.ok(!/var \$pin \{\s*value = \$cop1_gate\.pin_architecture_id/.test(src), `${t}: no longer uses the chat pin directly as the business`);
    assert.match(src, /pass journey_architecture_id\. \(E-COP-045\)/, `${t}: the refusal says what to do`);
  }
});

test('UT-COP-14-03-05: approval levels still apply to AI identities only - the gate is unchanged on that point', () => {
  const ag = read('functions/copilot/action_gate.xs');
  assert.match(ag, /if \(\$ai\.is_ai == true\)/);
  const gate = read('functions/journey/tool_gate.xs');
  assert.match(gate, /E-COP-048/, 'an AI with no business pin is still refused, even if it names a business');
});
