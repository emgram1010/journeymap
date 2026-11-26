import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// REPEAT-1 story 07 - an AI can preview, or draft, "this plan again for the next period". The rules live in
// XanoScript; these tests read the source. Live proof (through the real outside door) is in the epic's Test Results.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');
const tool = () => read('ai/tool/plan_repeat.xs');

test('UT-REPEAT-07-01: the tool is in the outside door and in both copilots, and nowhere does it publish', () => {
  for (const f of ['ai/mcp_server/journey_map.xs', 'ai/agent/emgram_copilot.xs', 'ai/agent/emgram_copilot_strong.xs']) {
    assert.match(read(f), /\{name: "plan_repeat"\}/, f);
  }
  assert.match(read('ai/agent/emgram_copilot.xs'), /create false/, 'the copilot is told to preview first');
});

test('UT-REPEAT-07-02: one policy class, the draft class (never a ceiling, never unclassed)', () => {
  assert.match(read('functions/aim/policy.xs'), /plan_repeat\s*:\s*"draft_plan"/);
});

test('UT-REPEAT-07-03: it passes the gate once; a preview is a read, only a create is a draft write', () => {
  const src = tool();
  assert.equal((src.match(/function\.run "journey\/tool_gate"/g) ?? []).length, 1, 'exactly one gate call');
  assert.match(src, /tool: "plan_repeat"/);
  assert.match(src, /kind: \$gate_kind/);
  assert.match(src, /act_type: \$act_type/);
  assert.match(src, /"plan_draft"/, 'a create asks for the plan_draft approval level');
  assert.match(src, /act_approval_id: \$input\.approval_id/, 'an approved action can be resent');
  assert.match(src, /function\.run "copilot\/action_close"/, 'how it ended is recorded');
});

test('UT-REPEAT-07-04: omitting create can only ever preview, and the ticket never reaches the approval payload', () => {
  const src = tool();
  assert.match(src, /bool create\?/);
  assert.match(src, /\$input\.create == true/, 'only an explicit true creates');
  const payload = src.match(/act_payload: \{[^}]*\}/)?.[0] ?? '';
  assert.ok(payload.length > 0 && !/ticket/.test(payload), 'the run ticket is not copied into the approval');
});

test('UT-REPEAT-07-05: it reuses the screen\'s own functions, so a draft equals a repeat made on screen', () => {
  const src = tool();
  assert.match(src, /function\.run "repeat\/preview"/);
  assert.match(src, /function\.run "repeat\/create_plan"/);
  assert.match(read('apis/planner/682_workspace_workspace_id_repeat_preview_POST.xs'), /function\.run "repeat\/preview"/, 'the screen preview is the same function');
});

test('UT-REPEAT-07-06: it never publishes, never clears a mark, never changes the AI plan list', () => {
  // look at what it RUNS and WRITES only (not at the words it says to the owner)
  const runs = [...tool().matchAll(/function\.run "([^"]+)"/g)].map((m) => m[1]);
  assert.ok(runs.every((r) => !/publish|clear_marks/.test(r)), `runs: ${runs.join(', ')}`);
  assert.ok(!/db\.(patch|edit|del|add)\s+(ai_member_profile|planner_task_review)/.test(tool()), 'no writes to the AI profile or the review marks');
  assert.ok(!/plan_ids/.test(tool().replace(/\/\/.*$/gm, '').replace(/instructions = .*/g, '')), 'plan_ids is never touched');
});

test('UT-REPEAT-07-07: the AI only reaches plans it may work in; the outcome is an event naming its manager', () => {
  const src = tool();
  assert.match(src, /function\.run "copilot\/plan_in_business"/);
  assert.match(src, /plan\.repeat_by_ai/);
  assert.match(src, /manager_user_id/);
});

test('UT-REPEAT-07-08: the answer leads with what was left out and says a person must review and publish', () => {
  const src = tool();
  assert.match(src, /Left out \(/);
  assert.match(src, /Publish to live/);
  assert.match(src, /needs review/);
  assert.match(src, /published\s*:\s*false/);
});
