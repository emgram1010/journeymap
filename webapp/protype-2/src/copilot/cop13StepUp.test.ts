import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// COP-13 part B - start cheap, ask before stepping up. The copilot runs on its standard copy (Sonnet 5.5);
// when a task is too hard it calls request_step_up, which goes through the approval levels (new action
// type step_up_model, default "waits for you") and a daily cap. Once allowed, the chat re-runs the same
// turn on the strong copy (Opus 5.5). The rules live in XanoScript; these tests read the source.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

const STD = 'ai/agent/emgram_copilot.xs';
const STRONG = 'ai/agent/emgram_copilot_strong.xs';
const TOOL = 'ai/tool/request_step_up.xs';

test('UT-COP-13-B-01: "use a stronger model" is an action type that waits for the owner by default and is marked as spending money', () => {
  const t = read('functions/copilot/action_types.xs');
  const line = t.split('\n').find((l) => l.includes('step_up_model'))!;
  assert.ok(line, 'step_up_model is catalogued');
  assert.match(line, /default_level: "wait"/);
  assert.match(line, /touches: "money"/);
  assert.match(line, /person_only: false/);
  assert.match(t, /"step_up_model"\]/, 'it is in the display order');
});

test('UT-COP-13-B-02: the two copies differ ONLY in name, model, canonical/guid and the step-up tool (generated from one source)', () => {
  const norm = (src: string) =>
    src
      .split('\n')
      .filter((l) => !/^\s*\/\//.test(l))
      .filter((l) => !/^agent "/.test(l))
      .filter((l) => !/^\s*(model|canonical|guid)\s*[:=]/.test(l))
      .filter((l) => !/\{name: "request_step_up"\}/.test(l))
      .join('\n');
  const std = read(STD);
  const strong = read(STRONG);
  assert.equal(norm(strong), norm(std), 'regenerate with: python scripts/gen_strong_copilot.py');
  assert.match(std, /model\s*:\s*"claude-sonnet-5-5"/);
  assert.match(strong, /model\s*:\s*"claude-opus-5-5"/);
  assert.match(strong, /^agent "Emgram Copilot Strong"/m);
  assert.match(std, /\{name: "request_step_up"\}/, 'the standard copy can ask');
  assert.ok(!/\{name: "request_step_up"\}/.test(strong), 'the strong copy cannot ask again (no loop)');
  assert.ok(!/^\s*temperature\s*:/m.test(strong), 'newer models reject a fixed temperature');
});

test('UT-COP-13-B-03: the tool checks the daily cap BEFORE asking, then goes through the approval gate', () => {
  const t = read(TOOL);
  assert.match(t, /function\.run "usr\/tool_caller"/);
  assert.match(t, /E-COP-094/);
  assert.match(t, /act_type: "step_up_model"/);
  assert.ok(t.indexOf('E-COP-094') < t.indexOf('function.run "journey/tool_gate"'), 'the cap refuses before a waiting item is created');
  assert.match(t, /copilot\.step_up\.requested/);
  assert.match(t, /copilot\.step_up\.granted/);
  assert.match(t, /\$reason_len < 1 \|\| \$reason_len > 200/, 'a one-line reason is required');
});

test('UT-COP-13-B-04: the approval item shows the reason and the price difference', () => {
  const t = read(TOOL);
  assert.match(t, /about twice the price/);
  assert.match(t, /act_summary/);
});

test('UT-COP-13-B-05: the chat re-runs the SAME turn on the strong copy only when a step-up was granted in this turn of this conversation', () => {
  const ep = read('apis/journey_map/643_copilot_chat_POST.xs');
  assert.match(ep, /ai\.agent\.run "Emgram Copilot Strong"/);
  assert.match(ep, /copilot\.step_up\.granted/);
  assert.match(ep, /\$turn_started_ms/);
  assert.match(ep, /event_log\.entity_id == \$conv_id/);
  assert.match(ep, /stepped_up/, 'the run records that it stepped up');
});

test('UT-COP-13-B-06: E-COP-094 is catalogued with a plain message', () => {
  const entries = JSON.parse(read('webapp/protype-2/src/ops/errorCatalog.json')) as Record<string, {feature: string; user_message: string}>;
  assert.equal(entries['E-COP-094']?.feature, 'COP-13');
  assert.ok((entries['E-COP-094']?.user_message ?? '').length > 10);
});

test('UT-COP-13-B-08: the daily cap is an owner setting (default 5, 1-20), read by the tool and saved only by an admin', () => {
  const table = read('static/tables/166_copilot_library_setting.xs');
  assert.match(table, /int step_up_daily_cap\?/);
  const t = read(TOOL);
  assert.match(t, /db\.query copilot_library_setting \{/, 'the tool reads the owner setting');
  assert.match(t, /step_up_daily_cap/);
  assert.match(t, /\(\$cap_raw != 0\) \? \$cap_raw : 5/, 'no row or 0 = the default 5');
  assert.ok(!/value = 5\s*\n\s*\}/.test(t.slice(t.indexOf('var $cap '), t.indexOf('var $cap ') + 40)), 'the cap is no longer a fixed number');
  const save = read('apis/journey_map/668_copilot_library_settings_POST.xs');
  assert.match(save, /int step_up_daily_cap\?/);
  assert.match(save, /\$input\.step_up_daily_cap == 0 \|\| \(\$input\.step_up_daily_cap >= 1 && \$input\.step_up_daily_cap <= 20\)/);
  assert.match(save, /function\.run "copilot\/assert_person_only"/, 'never an AI');
  const meta = read('apis/journey_map/667_copilot_skill_meta_GET.xs');
  assert.match(meta, /step_up_daily_cap\s*:/);
});

test('UT-COP-13-B-09: the screen checks the cap the same way the server does', async () => {
  const {limitsProblem} = await import('./skillsModel');
  const base = {max_active_items: 50, max_load_words: 4000, stale_after_days: 30};
  assert.equal(limitsProblem({...base, step_up_daily_cap: 5}), null);
  assert.equal(limitsProblem({...base, step_up_daily_cap: 20}), null);
  assert.match(limitsProblem({...base, step_up_daily_cap: 0}) ?? '', /1 and 20/);
  assert.match(limitsProblem({...base, step_up_daily_cap: 21}) ?? '', /1 and 20/);
});

test('UT-COP-13-B-07: the copilot is told when to ask, in one line, and that a "no" means carry on', () => {
  const p = read(STD);
  assert.match(p, /request_step_up/);
  assert.match(p, /carry on/i);
});

test('UT-COP-13-B-10: before re-doing a turn on the strong copy, it is told which changes this turn already made', () => {
  const ep = read('apis/journey_map/643_copilot_chat_POST.xs');
  const rerun = ep.slice(ep.indexOf('COP-13 part B: a step-up allowed'));
  assert.match(rerun, /db\.query tool_call_log \{/, 'the turn\'s own writes are read from the audit trail');
  assert.match(rerun, /\$db\.tool_call_log\.kind == "write"/);
  assert.match(rerun, /\$db\.tool_call_log\.created_at >= \$turn_started_ms/);
  assert.match(rerun, /\$db\.tool_call_log\.tool != "request_step_up"/);
  assert.match(rerun, /Do not repeat them/);
  assert.match(rerun, /ai\.agent\.run "Emgram Copilot Strong" \{\s*args = \{\}\|set:"messages":\$strong_msgs/, 'the strong copy gets the messages with the note');
});
