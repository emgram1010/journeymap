import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// COP-13 part A - which model each agent runs on. The model is a setting in each agent's file
// (and in Xano); these tests keep the repo's files honest and guard the one known hazard: the
// newer models reject a fixed `temperature`, so an agent on one must not set it.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const AGENT_DIR = repo('ai/agent');

// The model each agent is MEANT to run on right now. Change a line here only together with the agent's
// file AND a passing run of its test scenarios (see EPIC-COP-13 Test results).
const EXPECTED: Record<string, string> = {
  'emgram_copilot.xs': 'claude-sonnet-5-5',
  'journey_map_chat_agent.xs': 'claude-sonnet-5-5',
  'journey_map_builder.xs': 'claude-sonnet-4-5',
  'journey_map_assistant.xs': 'claude-sonnet-4-5',
  'journey_map_orchestrator.xs': 'claude-sonnet-4-5',
  'journey_compare_analyst.xs': 'claude-sonnet-4-5',
  'emgram_copilot_researcher.xs': 'claude-sonnet-4-5',
  // COP-13 part B: the strong twin, generated from emgram_copilot.xs; runs only after a step-up is allowed.
  'emgram_copilot_strong.xs': 'claude-opus-5-5',
};

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
