import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {AGENT_MODELS} from '../health/agentModels';

// COP-13 part A - which model each agent runs on. The model is a setting in each agent's file
// (and in Xano); these tests keep the repo's files honest and guard the one known hazard: the
// newer models reject a fixed `temperature`, so an agent on one must not set it.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const AGENT_DIR = repo('ai/agent');

// The model each agent is MEANT to run on right now. Change a line here only together with the agent's
// file AND a passing run of its test scenarios (see EPIC-COP-13 Test results).
// One list only: the Health page's manifest (src/health/agentModels.ts), which agentModels.test.ts also checks.
const EXPECTED: Record<string, string> = Object.fromEntries(AGENT_MODELS.map((a) => [a.file, a.model]));

const NO_FIXED_TEMPERATURE = /^claude-(sonnet-5|opus-5|haiku-5|fable|mythos)/;

const modelOf = (src: string) => /^\s*model\s*:\s*"([^"]+)"/m.exec(src)?.[1] ?? '';

test('UT-COP-13-01: every Anthropic agent file runs on the model we expect', () => {
  for (const [file, want] of Object.entries(EXPECTED)) {
    const src = readFileSync(`${AGENT_DIR}/${file}`, 'utf8');
    assert.equal(modelOf(src), want, `${file}`);
  }
});

test('UT-COP-13-02: no agent file is missing from the list above', () => {
  const files = readdirSync(AGENT_DIR).filter((f) => f.endsWith('.xs') && f !== 'xano_example_agent.xs');
  for (const f of files) assert.ok(EXPECTED[f], `${f} is not in the expected-model list: add it`);
});

test('UT-COP-13-03: an agent on a newer model sets no fixed temperature (it would be rejected)', () => {
  for (const file of Object.keys(EXPECTED)) {
    const src = readFileSync(`${AGENT_DIR}/${file}`, 'utf8');
    if (NO_FIXED_TEMPERATURE.test(modelOf(src))) {
      assert.ok(!/^\s*temperature\s*:/m.test(src), `${file} runs on ${modelOf(src)} and must not set temperature`);
    }
  }
});

test('UT-COP-13-04: POST journey_map/{id}/invoke returns the agent\'s reply text (read from "result", like the chat endpoints)', () => {
  const src = readFileSync(repo('apis/journey_map/209_journey_map_journey_map_id_invoke_POST.xs'), 'utf8');
  assert.match(src, /\$agent_result\s*\|get:"result"/, 'the reply is read from result');
  assert.ok(!/\|get:"messages"\s*\|last/.test(src), 'the old, empty path (messages > last > content) is gone');
});

test('UT-COP-13-05: invoke tells the orchestrator its map and the run, and never to repeat the ticket', () => {
  const src = readFileSync(repo('apis/journey_map/209_journey_map_journey_map_id_invoke_POST.xs'), 'utf8');
  assert.match(src, /## Orchestrator Mode Active/, 'the routing line the agent prompt expects');
  assert.match(src, /## Tool Logging/, 'the block the agent prompt expects');
  assert.match(src, /- journey_map_id: " ~ \(\$input\.journey_map_id\|to_text\)/, 'the map id is given');
  assert.match(src, /- turn_id: /, 'a turn id is given');
  assert.match(src, /- ticket: " ~ \$cop1_ticket\.ticket/, 'the ticket is still passed so the tools can identify the caller');
  assert.match(src, /Never repeat the ticket/i, 'the agent is told not to echo it');
});

test('UT-COP-13-06: validate_workflow never reads a lens field that does not exist, and a missing "primary" role does not block', () => {
  const src = readFileSync(repo('ai/tool/validate_workflow.xs'), 'utf8');
  // journey_lens has no actor_role column (live or repo): a bare $ln.actor_role throws and crashed every
  // pre-flight on a map with an internal actor. Read it through ?? so a future column still works.
  assert.ok(!/\$ln\.actor_role ==/.test(src), 'no bare $ln.actor_role');
  assert.match(src, /\(\$ln\.actor_role \?\? ""\) == "primary"/);
  // The Orchestrator's own rule: with no primary role, the first internal actor with a task objective leads.
  assert.ok(!/severity: "blocker", code: "no_primary_actor"/.test(src), 'a role nobody can set must not block');
  assert.match(src, /severity: "info", code: "no_primary_actor"/);
});

test('UT-COP-13-07: save_workflow_state really saves the stage outputs it builds', () => {
  const src = readFileSync(repo('ai/tool/save_workflow_state.xs'), 'utf8');
  // It merged the new stage output into $updated_stage_outputs and then never put it in $data, so every
  // orchestrator run saved empty outputs (found 2026-11-19: the agent reported "the save calls returned an empty list").
  assert.match(src, /\|set:"stage_outputs":\$updated_stage_outputs/);
  assert.ok(src.indexOf('set:"stage_outputs"') > src.indexOf('var $data {'), 'added after $data exists');
  assert.ok(src.indexOf('set:"stage_outputs"') < src.indexOf('db.patch workflow_execution'), 'and before it is saved');
});

test('UT-COP-13-08: each saved stage output carries a real time, not the word "now"', () => {
  const src = readFileSync(repo('ai/tool/save_workflow_state.xs'), 'utf8');
  assert.match(src, /var \$done_at \{\s*value = now\|to_int/);
  assert.match(src, /completed_at: \$done_at/);
});
