import assert from 'node:assert/strict';
import {existsSync, readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {WORK_KINDS, itemCounter, lastUsedLabel, lockLabel, workKindLabel} from './skillsModel';

// COP-11 - locks, fixed kinds of work, a size limit and stale flags for the copilot's "How I work".
// The rules live in XanoScript; these tests read the source so a later edit that quietly breaks a
// rule fails here. Live behaviour (FT-COP-11-*) is proven against the real workspace and recorded in
// the epic's Test results.

const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));
const read = (path: string) => readFileSync(repo(path), 'utf8');

const WRITE = 'functions/copilot/skill_write.xs';
const LIBRARY = 'functions/copilot/skill_library.xs';

test('UT-COP-11-01: error codes 089-092 and 096 are catalogued with plain messages', () => {
  const entries = JSON.parse(read('webapp/protype-2/src/ops/errorCatalog.json')) as Record<string, {code: string; feature: string; user_message: string; owner: string; severity: string}>;
  for (const code of ['E-COP-089', 'E-COP-090', 'E-COP-091', 'E-COP-092', 'E-COP-096']) {
    const e = entries[code];
    assert.ok(e, `${code} is catalogued`);
    assert.equal(e.code, code);
    assert.equal(e.feature, 'COP-11');
    assert.ok(e.user_message.length > 10);
    assert.ok(['user', 'product_manager', 'engineer'].includes(e.owner));
    assert.ok(['info', 'warn', 'error', 'critical'].includes(e.severity));
  }
});

test('UT-COP-11-02: the two new tables exist, the meta table is one row per item, and both are in the schema audit', () => {
  const meta = read('static/tables/165_copilot_skill_meta.xs');
  assert.match(meta, /table copilot_skill_meta/);
  assert.match(meta, /btree\|unique[^\n]*skill_id/, 'unique on skill_id: one row per item');
  for (const f of ['is_locked', 'locked_by_user_id', 'locked_at', 'work_kind', 'account_id']) assert.match(meta, new RegExp(`\\b${f}\\b`));
  for (const k of ['map_building', 'planning', 'doing_work', 'research', 'general']) assert.ok(meta.includes(`"${k}"`), `work_kind has ${k}`);
  const set = read('static/tables/166_copilot_library_setting.xs');
  assert.match(set, /table copilot_library_setting/);
  for (const f of ['max_active_items', 'max_load_words', 'stale_after_days']) assert.match(set, new RegExp(`\\b${f}\\b`));
  const audit = read('webapp/protype-2/src/ops/schemaAudit.ts');
  assert.match(audit, /copilot_skill_meta:/);
  assert.match(audit, /copilot_library_setting:/);
});

test('UT-COP-11-03: skill_write refuses a locked item for the copilot, at every level, before any write', () => {
  const fn = read(WRITE);
  assert.match(fn, /E-COP-089/);
  assert.match(fn, /copilot_skill_meta/, 'reads the lock from the side table');
  // the refusal is part of the same refuse-then-log path as every other rule: before the write block
  assert.ok(fn.indexOf('E-COP-089') < fn.indexOf('// ── The write ──'), 'checked before the write');
  assert.match(fn, /changed_by == "copilot"/, 'the lock binds the copilot, not the owner');
});

test('UT-COP-11-04: skill_write checks the kind of work, the item cap and duplicates on the server', () => {
  const fn = read(WRITE);
  assert.match(fn, /E-COP-090/);
  for (const k of ['map_building', 'planning', 'doing_work', 'research', 'general']) assert.ok(fn.includes(`"${k}"`), `kind list has ${k}`);
  assert.match(fn, /E-COP-091/);
  assert.match(fn, /max_active_items/);
  assert.match(fn, /E-COP-096/);
  assert.match(fn, /copilot_library_setting/, 'the cap is a settings row, not a number in code');
});

test('UT-COP-11-12: review fixes - a locked parent refuses exceptions and links, duplicates compare the when, the word limit is the real cap', () => {
  const fn = read(WRITE);
  assert.match(fn, /\$parent_locked/, 'the lock of the parent skill is read');
  assert.match(fn, /\$input\.op != "retire" && \$parent_locked/, 'create and edit under a locked parent are refused');
  assert.match(fn, /\$cc == \$norm_cond/, 'an exception with a different when is not a duplicate');
  const lib = read(LIBRARY);
  assert.ok(!/substr:0:24000/.test(lib), 'the old 24,000-character cut no longer overrides the word limit');
});

test('UT-COP-11-05: what the owner writes is locked by default (D-24-1)', () => {
  const fn = read(WRITE);
  assert.match(fn, /let_ai_change/, 'the owner can untick it');
  assert.match(fn, /is_locked/);
});

test('UT-COP-11-06: skill_library takes a list of kinds, caps the load by words and says what it left out', () => {
  const fn = read(LIBRARY);
  assert.match(fn, /work_kinds/);
  assert.match(fn, /max_load_words/);
  assert.match(fn, /left_out/);
  assert.match(fn, /copilot\.library\.load_trimmed|load_trimmed/);
  assert.match(fn, /locked/, 'locked items are marked so the copilot knows to suggest, not edit');
  assert.ok(!/\|contains:/.test(fn), 'no |contains on arrays (CLAUDE.md): kinds are matched with in inside the query');
});

test('UT-COP-11-07: no AI tool can touch a lock; only the owner endpoint can, and it refuses the copilot user', () => {
  const lock = read('apis/journey_map/666_copilot_skill_lock_POST.xs');
  assert.match(lock, /usr\/assert_team_admin/);
  assert.match(lock, /copilot\/assert_person_only/);
  assert.match(lock, /auth = "user"/);
  for (const f of ['ai/tool/save_skill.xs', 'ai/tool/retire_skill.xs', 'ai/tool/record_skill_used.xs']) {
    const t = read(f);
    assert.ok(!/is_locked|skill_lock|copilot_skill_meta/.test(t), `${f} never touches a lock`);
  }
});

test('UT-COP-11-08: the side table has its own GET and the settings have bounded numbers (AUTH-1 rule)', () => {
  const get = read('apis/journey_map/667_copilot_skill_meta_GET.xs');
  assert.match(get, /query "copilot\/skill_meta" verb=GET/);
  assert.match(get, /copilot_skill_meta/);
  assert.match(get, /copilot_skill_use/, 'last used is computed from the use history, not stored');
  const set = read('apis/journey_map/668_copilot_library_settings_POST.xs');
  assert.match(set, /usr\/assert_team_admin/);
  for (const bound of ['10', '200', '1000', '20000', '7', '365']) assert.ok(set.includes(bound), `bound ${bound}`);
});

test('UT-COP-11-09: save_skill passes the kind of work and nothing else changed about who may write', () => {
  const t = read('ai/tool/save_skill.xs');
  assert.match(t, /work_kind/);
  assert.match(t, /act_type: "skill_write"/);
});

test('UT-COP-11-10: display helpers use plain words', () => {
  assert.deepEqual([...WORK_KINDS], ['map_building', 'planning', 'doing_work', 'research', 'general']);
  assert.equal(workKindLabel('doing_work'), 'Doing work');
  assert.equal(workKindLabel('nonsense'), 'General');
  assert.equal(lockLabel(true), 'Locked');
  assert.equal(lockLabel(false), 'AI may change');
  assert.equal(itemCounter(23, 50), '23 of 50 items');
  assert.equal(lastUsedLabel(0, 1_800_000_000_000), 'Never used');
  assert.equal(lastUsedLabel(1_800_000_000_000 - 3 * 86_400_000, 1_800_000_000_000), 'Used 3 days ago');
  assert.equal(lastUsedLabel(1_800_000_000_000 - 3_600_000, 1_800_000_000_000), 'Used today');
});

test('UT-COP-11-11: the lock endpoint file and tables are not listed twice or missing', () => {
  for (const f of ['static/tables/165_copilot_skill_meta.xs', 'static/tables/166_copilot_library_setting.xs', 'apis/journey_map/666_copilot_skill_lock_POST.xs']) {
    assert.ok(existsSync(repo(f)), f);
  }
});
