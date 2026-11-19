import assert from 'node:assert/strict';
import test from 'node:test';
import {
  changedFields,
  isOffFor,
  kindLabel,
  scopeLabel,
  splitByStatus,
  statusLabel,
  undoTarget,
  versionLine,
  visibleLevelRows,
} from './skillsModel';
import type {XanoCopilotLevelRow, XanoCopilotSkill} from '../xano';

const item = (over: Partial<XanoCopilotSkill>): XanoCopilotSkill => ({
  id: 1, updated_at: 0, journey_map_id: 10, kind: 'skill', status: 'trial', title: 't', body: 'b',
  condition_text: '', parent_skill_id: 0, link_to_skill_id: 0, scope_type: 'all', scope_ref_id: 0,
  scope_text: '', version_no: 1, ...over,
});

test('UT-COP-9-10: kinds and statuses read in plain words', () => {
  assert.equal(kindLabel('exception'), 'Exception');
  assert.equal(statusLabel('trial'), 'On trial');
  assert.equal(statusLabel('retired'), 'Retired');
  assert.equal(kindLabel('unknown'), 'unknown');
});

test('UT-COP-9-11: scope says where an item applies', () => {
  assert.equal(scopeLabel(item({scope_type: 'all'})), 'Every business');
  assert.equal(scopeLabel(item({scope_type: ''})), 'Every business');
  assert.equal(scopeLabel(item({scope_type: 'business', scope_ref_id: 49}), (id) => (id === 49 ? 'Shop A' : undefined)), 'Only in Shop A');
  assert.equal(scopeLabel(item({scope_type: 'business', scope_ref_id: 7})), 'Only in business 7');
  assert.equal(scopeLabel(item({scope_type: 'map', scope_ref_id: 3})), 'Only on map 3');
  assert.equal(scopeLabel(item({scope_type: 'work_kind', scope_text: 'repairs'})), 'Only for: repairs');
});

test('UT-COP-9-12: switched off for one business only', () => {
  const off = [{skill_id: 3, journey_architecture_id: 49}];
  assert.equal(isOffFor(off, 3, 49), true);
  assert.equal(isOffFor(off, 3, 50), false, 'still on in every other business');
  assert.equal(isOffFor(off, 4, 49), false);
});

test('UT-COP-9-13: retired items are listed apart, after the live ones', () => {
  const {live, retired} = splitByStatus([item({id: 3, status: 'retired'}), item({id: 2}), item({id: 1, status: 'trusted'})]);
  assert.deepEqual(live.map((i) => i.id), [1, 2]);
  assert.deepEqual(retired.map((i) => i.id), [3]);
});

test('UT-COP-9-14: each history line says who did what, and why', () => {
  assert.equal(versionLine({version_no: 1, change: 'create', changed_by: 'copilot', reason: 'jobs ran long', undo_of_version_no: 0}), 'v1 · The copilot created it — jobs ran long');
  assert.equal(versionLine({version_no: 3, change: 'retire', changed_by: 'copilot', reason: '', undo_of_version_no: 0}), 'v3 · The copilot retired it');
  assert.equal(versionLine({version_no: 4, change: 'undo', changed_by: 'owner', reason: '', undo_of_version_no: 2}), 'v4 · You put back version 2');
});

test('UT-COP-9-15: Undo on a change puts back the version before it; the creation has none', () => {
  assert.equal(undoTarget({version_no: 5}), 4);
  assert.equal(undoTarget({version_no: 2}), 1);
  assert.equal(undoTarget({version_no: 1}), 0);
});

test('UT-COP-9-16: what changed between two versions, in plain words', () => {
  assert.deepEqual(changedFields({title: 'a', body: 'x'}, {title: 'a', body: 'y'}), ['what to do']);
  assert.deepEqual(changedFields({status: 'trial'}, {status: 'retired'}), ['status']);
  assert.deepEqual(changedFields({scope_type: 'all', scope_ref_id: 0}, {scope_type: 'business', scope_ref_id: 49}), ['where it applies']);
  assert.deepEqual(changedFields(null, {title: 'a'}), []);
});

test('UT-COP-9-17: "write its own skills" shows only on the copilot\'s own business', () => {
  const rows = [{key: 'map_read'}, {key: 'skill_write'}] as XanoCopilotLevelRow[];
  assert.deepEqual(visibleLevelRows(rows, 54, 54).map((r) => r.key), ['map_read', 'skill_write']);
  assert.deepEqual(visibleLevelRows(rows, 49, 54).map((r) => r.key), ['map_read'], 'hidden in an ordinary business, where it would do nothing');
  assert.deepEqual(visibleLevelRows(rows, 0, 0).map((r) => r.key), ['map_read'], 'hidden when there is no copilot home');
});

// ── COP-11 story 05: the lock, kind of work, last used and filters on the Playbook screen ──
test('UT-COP-11-20: skillInfo joins the side table to an item, and a missing row reads as unlocked + general', async () => {
  const {skillInfo} = await import('./skillsModel');
  const meta = {
    items: [{skill_id: 1, last_used_at: 1_800_000_000_000, not_used_in_days: false}, {skill_id: 2, last_used_at: 0, not_used_in_days: true}],
    metas: [{skill_id: 1, is_locked: true, locked_by_user_id: 22, locked_at: 1, work_kind: 'planning'}],
    active_count: 2,
    max_active_items: 50,
    max_load_words: 4000,
    stale_after_days: 30,
  };
  assert.deepEqual(skillInfo(meta, 1), {locked: true, workKind: 'planning', lastUsedAt: 1_800_000_000_000, stale: false});
  assert.deepEqual(skillInfo(meta, 2), {locked: false, workKind: 'general', lastUsedAt: 0, stale: true});
  assert.deepEqual(skillInfo(null, 9), {locked: false, workKind: 'general', lastUsedAt: 0, stale: false});
  // an untouched enum comes back as "" (CLAUDE.md), which must still read as general
  assert.equal(skillInfo({...meta, metas: [{skill_id: 2, is_locked: false, locked_by_user_id: 0, locked_at: 0, work_kind: ''}]}, 2).workKind, 'general');
});

test('UT-COP-11-21: filterSkills keeps by kind of work and by "not used", and "all" keeps everything', async () => {
  const {filterSkills} = await import('./skillsModel');
  const meta = {
    items: [{skill_id: 1, last_used_at: 5, not_used_in_days: false}, {skill_id: 2, last_used_at: 0, not_used_in_days: true}, {skill_id: 3, last_used_at: 0, not_used_in_days: true}],
    metas: [{skill_id: 1, is_locked: true, locked_by_user_id: 22, locked_at: 1, work_kind: 'planning'}, {skill_id: 3, is_locked: false, locked_by_user_id: 0, locked_at: 0, work_kind: 'research'}],
    active_count: 3,
    max_active_items: 50,
    max_load_words: 4000,
    stale_after_days: 30,
  };
  const items = [{id: 1}, {id: 2}, {id: 3}];
  assert.deepEqual(filterSkills(items, meta, {kind: 'all', staleOnly: false}).map((i) => i.id), [1, 2, 3]);
  assert.deepEqual(filterSkills(items, meta, {kind: 'planning', staleOnly: false}).map((i) => i.id), [1]);
  assert.deepEqual(filterSkills(items, meta, {kind: 'general', staleOnly: false}).map((i) => i.id), [2]);
  assert.deepEqual(filterSkills(items, meta, {kind: 'all', staleOnly: true}).map((i) => i.id), [2, 3]);
  assert.deepEqual(filterSkills(items, meta, {kind: 'research', staleOnly: true}).map((i) => i.id), [3]);
});

test('UT-COP-11-22: limitsProblem gives a plain sentence for a number outside the server bounds, and null when fine', async () => {
  const {limitsProblem} = await import('./skillsModel');
  assert.equal(limitsProblem({max_active_items: 50, max_load_words: 4000, stale_after_days: 30}), null);
  assert.match(limitsProblem({max_active_items: 5, max_load_words: 4000, stale_after_days: 30}) ?? '', /10 and 200/);
  assert.match(limitsProblem({max_active_items: 50, max_load_words: 500, stale_after_days: 30}) ?? '', /1,000 and 20,000/);
  assert.match(limitsProblem({max_active_items: 50, max_load_words: 4000, stale_after_days: 400}) ?? '', /7 and 365/);
  assert.match(limitsProblem({max_active_items: Number.NaN, max_load_words: 4000, stale_after_days: 30}) ?? '', /10 and 200/);
});
