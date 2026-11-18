import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// COP-12 / COP-14-05 - the map AIs and outside Claude READ "How I work" through one read-only tool.
// The rules live in XanoScript; these tests read the source. Live behaviour (FT-COP-12-*) is proven
// against the real workspace and recorded in the epic's Test results.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');
const strip = (src: string) => src.replace(/\/\/.*$/gm, '');

const TOOL = 'ai/tool/get_how_i_work.xs';

test('UT-COP-12-01: get_how_i_work runs the ONE loader the copilot uses, through the tool gate, as a read', () => {
  const tool = read(TOOL);
  assert.match(tool, /tool get_how_i_work \{/);
  assert.match(tool, /function\.run "journey\/tool_gate"/);
  assert.match(tool, /kind: "read"/);
  assert.match(tool, /function\.run "copilot\/skill_library"/, 'same loader as chat 643 and run_for_business');
  assert.match(tool, /log_success: false/, 'a read per task is not an event per call');
});

test('UT-COP-12-02: it can never write: no db write, no skill writer, no approval action type', () => {
  const code = strip(read(TOOL));
  assert.ok(!/\bdb\.(add|patch|del|edit|truncate)\b/.test(code), 'writes nothing');
  assert.ok(!/copilot\/skill_write|copilot\/skill_undo/.test(code), 'does not call the skill writer');
  assert.ok(!/act_type/.test(code), 'a read declares no approval action type');
});

test('UT-COP-12-03: the map is checked to belong to the caller\'s account before its business is used', () => {
  const code = strip(read(TOOL));
  assert.match(code, /\$db\.journey_map\.account_id == \$account_id/, 'the map must be in the caller\'s account');
  assert.match(code, /\$account_id != 0/, 'an unknown caller loads nothing');
});

test('UT-COP-12-04: no map AI lists a skill WRITER; the copilot stays the only writer', () => {
  for (const f of ['ai/agent/journey_map_builder.xs', 'ai/agent/journey_map_chat_agent.xs', 'ai/agent/journey_map_assistant.xs']) {
    const list = read(f).split('tools = [')[1];
    for (const w of ['save_skill', 'retire_skill']) assert.ok(!list.includes(`{name: "${w}"}`), `${f} has no ${w}`);
  }
});

test('UT-COP-12-05: the Builder and Chat agents list the tool and are told to read it first', () => {
  for (const f of ['ai/agent/journey_map_builder.xs', 'ai/agent/journey_map_chat_agent.xs', 'ai/agent/journey_map_assistant.xs']) {
    assert.match(read(f), /\{name: "get_how_i_work"\}/, `${f} lists get_how_i_work`);
  }
  // The Assistant's prompt is injected live; its instruction to read first is the tool's own.
  assert.match(read(TOOL), /Call this ONCE at the start of any build or planning task/);
  for (const f of ['ai/agent/journey_map_builder.xs', 'ai/agent/journey_map_chat_agent.xs']) {
    assert.match(read(f).split('tools = [')[0], /get_how_i_work/, `${f}: the prompt names the tool`);
  }
});

test('UT-COP-12-06: the chat agent is still read-only', () => {
  const list = read('ai/agent/journey_map_chat_agent.xs').split('tools = [')[1];
  for (const w of ['update_cell', 'batch_update', 'update_actor_cell_fields', 'update_actor_identity', 'update_journey_settings', 'set_cell_status', 'batch_set_status', 'mutate_structure', 'scaffold_structure', 'infer_stage_metrics', 'record_skill_used']) {
    assert.ok(!list.includes(`{name: "${w}"}`), `chat mode has no ${w}`);
  }
});
