import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {HISTORY_TABLE_NAMES, findHistoryDeletes} from '../ops/historyTables';
import {TABLE_MANIFEST} from '../ops/schemaAudit';

// COP-9 stories 01-04 and 06 - the copilot's skill library. The rules live in XanoScript; these
// tests read the source so a later edit that quietly drops a rule fails here. Live behaviour
// (FT-COP-9-*) is proven against the real workspace and recorded in the epic's Test results.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

// ── Governance: tables, history, error codes ────────────────────────────────

test('UT-COP-9-01: the four tables exist with their unique keys; history tables are append-only', () => {
  const skill = read('static/tables/161_copilot_skill.xs');
  assert.match(skill, /table copilot_skill \{/);
  assert.match(skill, /values = \["skill", "exception", "lesson", "link"\]/);
  assert.match(skill, /values = \["trial", "trusted", "retired"\]/);
  assert.match(skill, /values = \["all", "business", "map", "work_kind"\]/);
  assert.match(skill, /\{type: "btree\|unique", field: \[\{name: "journey_map_id"/);
  const ver = read('static/tables/162_copilot_skill_version.xs');
  assert.match(ver, /\{type: "btree\|unique", field: \[\{name: "skill_id", op: "asc"\}, \{name: "version_no"/, 'a race on the same number fails at the database');
  const off = read('static/tables/163_copilot_skill_off.xs');
  assert.match(off, /\{type: "btree\|unique", field: \[\{name: "skill_id", op: "asc"\}, \{name: "journey_architecture_id"/);
  const use = read('static/tables/164_copilot_skill_use.xs');
  for (const t of [ver, use]) assert.ok(!t.includes('updated_at'), 'append-only: no updated_at');
  assert.ok(HISTORY_TABLE_NAMES.has('copilot_skill_version'), 'versions can never be deleted from');
  assert.ok(HISTORY_TABLE_NAMES.has('copilot_skill_use'));
  for (const name of ['copilot_skill', 'copilot_skill_version', 'copilot_skill_off', 'copilot_skill_use']) {
    assert.ok(TABLE_MANIFEST[name], `${name} is in the schema manifest`);
  }
});

test('UT-COP-9-02: every COP-9 error code is in the catalog with a plain message', () => {
  const entries = JSON.parse(read('webapp/protype-2/src/ops/errorCatalog.json')) as Record<string, {code: string; user_message: string; severity: string}>;
  for (const code of ['E-COP-080', 'E-COP-081', 'E-COP-082', 'E-COP-083', 'E-COP-084', 'E-COP-085', 'E-COP-086', 'E-COP-087']) {
    assert.ok(entries[code], `${code} is catalogued`);
    assert.equal(entries[code].code, code);
    assert.ok(entries[code].user_message.length > 10);
    assert.ok(['info', 'warn', 'error', 'critical'].includes(entries[code].severity), `${code} severity`);
  }
});

test('UT-COP-9-03: nothing in the skill code deletes from a history table', () => {
  for (const f of ['functions/copilot/skill_write.xs', 'functions/copilot/skill_undo.xs', 'functions/copilot/skill_library.xs']) {
    assert.deepEqual(findHistoryDeletes(read(f), f), [], f);
  }
  for (const f of ['functions/copilot/skill_write.xs', 'functions/copilot/skill_undo.xs', 'ai/tool/retire_skill.xs']) {
    assert.ok(!/db\.del copilot_skill\b/.test(read(f)), `${f}: the copilot retires, never deletes`);
  }
});

// ── Story 01: the copilot reads "how I work" every time ─────────────────────

test('COP9-01: chat and scheduled runs both load the library through the ONE function', () => {
  for (const f of ['apis/journey_map/643_copilot_chat_POST.xs', 'functions/copilot/run_for_business.xs']) {
    const src = read(f);
    assert.match(src, /function\.run "copilot\/skill_library"/, `${f} loads the library`);
    assert.match(src, /## How I work/, `${f} puts the skills in the copilot's context`);
  }
});

test('COP9-01: the library skips retired items, switched-off items and items scoped elsewhere', () => {
  const src = read('functions/copilot/skill_library.xs');
  assert.match(src, /\$db\.copilot_skill\.status != "retired"/, 'retired items are never loaded');
  assert.match(src, /db\.query copilot_skill_off \{/, 'per-business switches are read');
  assert.match(src, /not in \$off_ids/, 'switched-off items are excluded, written `not in`');
  assert.match(src, /var \$off_ids \{\s*value = \[-1\]/, 'the exclusion list is seeded with a sentinel');
  assert.match(src, /scope_type == "business"/);
  assert.match(src, /scope_type == "map"/);
  assert.match(src, /trial/, 'trial items are marked in the text');
});

test('COP9-01: a library that cannot be read never stops the copilot and is logged (E-COP-080)', () => {
  const src = read('functions/copilot/skill_library.xs');
  assert.match(src, /try_catch \{/);
  assert.match(src, /error_code\s*: "E-COP-080"/);
  assert.match(src, /outcome\s*: "failure"/);
});

test('COP9-01: the copilot records which skill (and exception) it used', () => {
  const tool = read('ai/tool/record_skill_used.xs');
  assert.match(tool, /db\.add copilot_skill_use \{/);
  assert.match(tool, /was_trial/);
  assert.match(tool, /function\.run "journey\/tool_gate"/, 'it passes the gate like every tool');
});

// ── Story 02: create, edit and retire - only in its own business ────────────

test('COP9-02: the tools pass the gate with the skill_write action type, then call the one writer', () => {
  for (const f of ['ai/tool/save_skill.xs', 'ai/tool/retire_skill.xs']) {
    const src = read(f);
    assert.match(src, /function\.run "journey\/tool_gate"/, f);
    assert.match(src, /act_type: "skill_write"/, `${f} declares its action type so the owner's level applies`);
    assert.match(src, /function\.run "copilot\/skill_write"/, `${f} writes only through copilot/skill_write`);
    assert.match(src, /function\.run "copilot\/action_close"/, `${f} reports how it ended to Approvals`);
    assert.ok(!/db\.(add|patch) copilot_skill\b/.test(src), `${f} never writes the table itself`);
  }
});

test('COP9-02: the writer only writes in the account\'s own copilot home (E-COP-081)', () => {
  const src = read('functions/copilot/skill_write.xs');
  assert.match(src, /db\.query copilot_home \{/);
  assert.match(src, /E-COP-081/);
  assert.match(src, /E-COP-086/, 'no copilot home yet');
  assert.match(src, /home_architecture_id/);
});

test('COP9-02: the agent has the three skill tools and is told to retire, never delete', () => {
  const agent = read('ai/agent/emgram_copilot.xs');
  for (const t of ['save_skill', 'retire_skill', 'record_skill_used']) assert.match(agent, new RegExp(`\\{name: "${t}"\\}`), t);
  assert.match(agent, /## How you learn/);
});

// ── Story 03: hard limits on the server ─────────────────────────────────────

test('COP9-03: limits are checked by the writer itself, before anything is stored, at every level', () => {
  const src = read('functions/copilot/skill_write.xs');
  const limitsAt = src.indexOf('function.run "copilot/skill_limits"');
  const firstWrite = src.search(/db\.(add|patch) (copilot_skill|journey_map)\b/);
  assert.ok(limitsAt > 0, 'the writer runs the limits');
  assert.ok(firstWrite > limitsAt, 'limits run before the first write');
  assert.ok(!/action_level|\$level/.test(src.slice(0, firstWrite)), 'no approval level is consulted around the limits');
});

test('COP9-03: the limits name both codes and cover permissions, approvals, secrets and personal data', () => {
  const src = read('functions/copilot/skill_limits.xs');
  assert.match(src, /E-COP-082/);
  assert.match(src, /E-COP-083/);
  for (const word of ['approval', 'permission', 'password', 'token']) assert.match(src, new RegExp(word, 'i'), word);
  assert.match(src, /regex_matches/, 'patterns (emails, phone and card numbers, keys) are matched, not just words');
});

test('COP9-08 (part of 02): an exception without a "when" is refused (E-COP-084)', () => {
  const src = read('functions/copilot/skill_write.xs');
  assert.match(src, /E-COP-084/);
  assert.match(src, /An exception needs a 'when'/);
});

// ── Story 04: versions and one-click undo ───────────────────────────────────

test('COP9-04: every write stores a full version in the same transaction as the change', () => {
  const src = read('functions/copilot/skill_write.xs');
  const tx = src.slice(src.indexOf('db.transaction {'));
  assert.ok(src.includes('db.transaction {'), 'one transaction');
  assert.match(tx, /db\.add copilot_skill_version \{/);
  assert.match(src, /changed_by/);
  assert.match(src, /copilot_run_id/);
});

test('COP9-04: undo puts an earlier version back as a NEW version, owner only', () => {
  const src = read('functions/copilot/skill_undo.xs');
  assert.match(src, /change\s*: "undo"/);
  assert.match(src, /undo_of_version_no/);
  assert.match(src, /E-COP-085/, 'a failed write');
  assert.match(src, /E-COP-087/, 'a version that is not in the history, or is the current one');
  const api = read('apis/journey_map/664_copilot_skill_undo_POST.xs');
  assert.match(api, /function\.run "usr\/assert_team_admin"/, 'a signed-in admin, never an AI');
  assert.match(api, /function\.run "copilot\/assert_person_only"/);
});

// ── Story 06: the owner chooses the level once ──────────────────────────────

test('COP9-06: "write its own skills" is in the one catalogue, default tell, not locked', () => {
  const src = read('functions/copilot/action_types.xs');
  const row = src.match(/skill_write\s*: \{([^}]*)\}/);
  assert.ok(row, 'skill_write is catalogued');
  assert.match(row![1], /default_level: "tell"/);
  assert.match(row![1], /locked: false/);
  assert.match(row![1], /person_only: false/);
  assert.match(src, /"skill_write"\]/, 'listed in the order the screen shows');
});

test('COP9-06: the level for skill writes is read from the copilot\'s own business, set once', () => {
  const src = read('functions/copilot/action_gate.xs');
  assert.match(src, /if \(\$input\.act_type == "skill_write"\)/);
  assert.match(src, /db\.query copilot_home \{/);
});
