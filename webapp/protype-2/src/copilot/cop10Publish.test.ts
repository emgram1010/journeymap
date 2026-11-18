import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// COP-10 - the AI checks a map against the real publish checklist. The rules live in XanoScript;
// these tests read the source so a later edit that quietly breaks a rule fails here. Live behaviour
// (FT-COP-10-*) is proven against the real workspace and recorded in the epic's Test results.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

const TOOL = 'ai/tool/check_publish_ready.xs';
const FUNCTION = 'functions/pub/check_map_ready.xs';
const AGENTS = [
  'ai/agent/journey_map_builder.xs',
  'ai/agent/journey_map_assistant.xs',
  'ai/agent/journey_map_chat_agent.xs',
  'ai/agent/emgram_copilot.xs',
];

test('UT-COP-10-01: E-COP-088 is in the catalog with a plain message and one meaning', () => {
  const entries = JSON.parse(read('webapp/protype-2/src/ops/errorCatalog.json')) as Record<string, {code: string; feature: string; user_message: string; owner: string; severity: string}>;
  const e = entries['E-COP-088'];
  assert.ok(e, 'E-COP-088 is catalogued');
  assert.equal(e.code, 'E-COP-088');
  assert.equal(e.feature, 'COP-10');
  assert.ok(e.user_message.length > 10);
  assert.ok(['user', 'product_manager', 'engineer'].includes(e.owner), 'owner is one the catalog allows');
  assert.ok(['info', 'warn', 'error', 'critical'].includes(e.severity));
});

test('UT-COP-10-02: one rule, one place - the checklist function chains the SAME three functions endpoint 520 uses', () => {
  const fn = read(FUNCTION);
  assert.match(fn, /function "pub\/check_map_ready"/);
  assert.match(fn, /function\.run "pub\/build_map_snapshot"/, 'builds the same snapshot a publish would freeze');
  assert.match(fn, /function\.run "exceptions\/exception_targets"/);
  assert.match(fn, /function\.run "pub\/evaluate_gate"/, 'the gate Publish version runs');
  const ep = read('apis/journey_map/520_journey_map_journey_map_id_readiness_GET.xs');
  for (const f of ['pub/build_map_snapshot', 'exceptions/exception_targets', 'pub/evaluate_gate']) {
    assert.ok(ep.includes(`function.run "${f}"`), `endpoint 520 also runs ${f}`);
  }
});

test('UT-COP-10-03: neither the function nor the tool keeps its own copy of any checklist rule code', () => {
  for (const f of [FUNCTION, TOOL]) {
    const src = read(f);
    for (const code of ['NO_WORK_TYPE_NAME', 'NO_STAGES', 'NO_STAGE_NAME', 'NO_OWNER', 'OWNER_NOT_WORK_ROLE', 'NO_TASK', 'NO_DURATION', 'NO_DONE_WHEN', 'PARTIAL_WORK_CELL', 'INACTIVE_ITEM']) {
      assert.ok(!src.includes(code), `${f} must not copy ${code}: a new rule would never reach the AI`);
    }
  }
});

test('UT-COP-10-04: the tool is read-only and goes through the gate like every map tool', () => {
  const tool = read(TOOL);
  assert.match(tool, /tool check_publish_ready \{/);
  assert.match(tool, /function\.run "journey\/tool_gate"/);
  assert.match(tool, /kind: "read"/, 'declared as a read');
  assert.ok(!/act_type/.test(tool), 'a read declares no approval action type');
  for (const f of [TOOL, FUNCTION]) {
    const src = read(f);
    assert.ok(!/\bdb\.(add|patch|del|edit|truncate)\b/.test(src.replace(/\/\/.*$/gm, '')), `${f} writes nothing to the database`);
  }
  assert.ok(!/function\.run "pub\/(publish|freeze)/.test(tool), 'it never publishes');
});

test('UT-COP-10-05: the tool passes the gate\'s blockers and warnings through and logs success and failure', () => {
  const tool = read(TOOL);
  assert.match(tool, /blockers/);
  assert.match(tool, /warnings/);
  assert.match(tool, /E-COP-088/, 'a failing checklist run is reported, not swallowed');
  assert.match(tool, /try_catch/);
  assert.match(tool, /ops\/log_event/);
  assert.match(tool, /feature\s*:\s*"COP-10"/);
  assert.match(tool, /outcome\s*:\s*"failure"/);
  assert.match(tool, /outcome\s*:\s*"success"/);
});

test('UT-COP-10-06: every AI that builds maps lists the tool and is told to use it before "ready"', () => {
  for (const f of AGENTS) {
    const src = read(f);
    assert.match(src, /\{name: "check_publish_ready"\}/, `${f} lists check_publish_ready`);
    assert.match(src, /check_publish_ready/, `${f}`);
  }
  // The Journey Map Assistant's system prompt is a placeholder ("temp"): endpoint 52 injects the real
  // one, so its instruction to check lives in the tool's own instructions (asserted below).
  for (const f of AGENTS.filter((a) => !a.includes('assistant'))) {
    const prompt = read(f).split('tools = [')[0];
    assert.match(prompt, /check_publish_ready/, `${f}: the prompt tells it to check before saying a map is ready`);
  }
  assert.match(read(TOOL), /Call this before you tell the owner a map is ready to publish/);
  assert.match(read(TOOL), /Say "ready to publish" only when ready is\s+true/);
});

test('UT-COP-10-07: the chat agent stays read-only and the copilot has no publish tool', () => {
  const chat = read('ai/agent/journey_map_chat_agent.xs');
  assert.ok(!/\{name: "publish_map"\}/.test(chat), 'chat mode has no publish tool');
  const writes = ['update_cell', 'batch_update', 'update_actor_cell_fields', 'update_actor_identity', 'update_journey_settings', 'set_cell_status', 'batch_set_status', 'mutate_structure', 'scaffold_structure', 'infer_stage_metrics'];
  const toolList = chat.split('tools = [')[1];
  for (const w of writes) assert.ok(!toolList.includes(`{name: "${w}"}`), `chat mode has no ${w}`);
  assert.ok(!/\{name: "publish_map"\}/.test(read('ai/agent/emgram_copilot.xs')), 'the copilot has no publish tool');
});
