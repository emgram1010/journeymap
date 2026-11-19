import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {AGENT_MODELS, isCurrentModel, modelLabel, agentModelsSummary} from './agentModels';

// COP-13 story 02 - Health lists each AI agent with its model, so an old one is visible. The list
// is a manifest kept in the app; these tests keep it equal to the real agent files.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const AGENT_DIR = repo('ai/agent');
const modelOf = (src: string) => /^\s*model\s*:\s*"([^"]+)"/m.exec(src)?.[1] ?? '';
const nameOf = (src: string) => /^agent "([^"]+)"/m.exec(src)?.[1] ?? '';

test('UT-COP-13-02-01: every manifest row matches its agent file (name and model)', () => {
  for (const a of AGENT_MODELS) {
    const src = readFileSync(`${AGENT_DIR}/${a.file}`, 'utf8');
    assert.equal(modelOf(src), a.model, `${a.file}: model`);
    assert.equal(nameOf(src), a.name, `${a.file}: name`);
  }
});

test('UT-COP-13-02-02: every agent file is in the manifest (the Xano example is the only exception)', () => {
  const files = readdirSync(AGENT_DIR).filter((f) => f.endsWith('.xs') && f !== 'xano_example_agent.xs');
  const listed = new Set(AGENT_MODELS.map((a) => a.file));
  for (const f of files) assert.ok(listed.has(f), `${f} is not in the Health manifest: add it`);
  assert.equal(listed.size, AGENT_MODELS.length, 'no file listed twice');
});

test('UT-COP-13-02-03: each row says in plain words what the agent does', () => {
  for (const a of AGENT_MODELS) assert.ok(a.does.length >= 10 && a.does.length <= 90, `${a.name}: one short line`);
});

test('UT-COP-13-02-04: a Claude 5 model is current; a Claude 4 one is flagged as older', () => {
  assert.equal(isCurrentModel('claude-sonnet-5-5'), true);
  assert.equal(isCurrentModel('claude-opus-5-5'), true);
  assert.equal(isCurrentModel('claude-sonnet-4-5'), false);
  assert.equal(isCurrentModel(''), false);
});

test('UT-COP-13-02-05: model names are shown in plain words', () => {
  assert.equal(modelLabel('claude-sonnet-5-5'), 'Sonnet 5.5');
  assert.equal(modelLabel('claude-opus-5-5'), 'Opus 5.5');
  assert.equal(modelLabel('claude-sonnet-4-5'), 'Sonnet 4.5');
  assert.equal(modelLabel('something-odd'), 'something-odd');
});

test('UT-COP-13-02-06: the summary counts agents on an older model', () => {
  assert.match(agentModelsSummary([{model: 'claude-sonnet-5-5'}, {model: 'claude-sonnet-4-5'}, {model: 'claude-sonnet-4-5'}]), /2 of 3 .*older/);
  assert.match(agentModelsSummary([{model: 'claude-sonnet-5-5'}]), /All 1 .*current/);
});
