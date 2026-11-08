import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {
  publishBlockers,
  blockerMessage,
  canonicalizePublication,
  canonicalizePublicationV2,
  canonicalizePublicationV3,
  diffPlan,
  itemRef,
  type PublicationItemV2,
  type PublicationItemV3,
  type PublishableItem,
} from './liveModel';

// Pinned once from this module; the server's v2 pin is the same string
// (functions/live/build_publication.xs header). Change only on purpose.
// SCHED-2: the same fixture string is produced by live/build_publication (verified live, EPIC-SCHED-2 §9).
const PINNED_V3_HASH = 'e80d17c578404311a100144b574bb9bb8bbe60f0c2ec4092da36be403f3f67ec';
const PINNED_V2_HASH ='c0d594020ab9716cd40b30043268d79a9fa0f3f7e1816f16625a98bd5aa7093e';
const PINNED_V1_HASH = 'a1062b14bbbc1783dd9a6696b8a4efc33aced6f5e7e0c0a32beabc20232584a4';

const item = (over: Partial<PublishableItem> = {}): PublishableItem => ({
  planner_task_id: 1,
  assignee_agent_id: 7,
  assignee_has_login: true,
  assignee_name: 'Dana',
  status: 'planned',
  seq: 1,
  planned_start: '08:00',
  scheduled_minutes: 30,
  expected_minutes: 30,
  work_task_ids: [10],
  stage_label: 'Enquiry',
  lens_label: 'Sales',
  ...over,
});

// ── publishBlockers ────────────────────────────────────────────────

test('UT-LIVE-1-01: an empty timeline reports only EMPTY', () => {
  const b = publishBlockers([]);
  assert.deepEqual(b.map((x) => x.code), ['EMPTY']);
});

test('UT-LIVE-1-02: a step with nobody assigned blocks publishing', () => {
  const b = publishBlockers([item(), item({planner_task_id: 2, assignee_agent_id: 0})]);
  const na = b.find((x) => x.code === 'NO_ASSIGNEE');
  assert.ok(na);
  assert.equal(na!.count, 1);
  assert.deepEqual(na!.detail, ['2']);
});

test('UT-LIVE-1-03: a step marked needs_info blocks publishing', () => {
  const b = publishBlockers([item({planner_task_id: 3, status: 'needs_info'})]);
  assert.equal(b.find((x) => x.code === 'NEEDS_INFO')?.count, 1);
});

test('UT-LIVE-1-04: a ready timeline has no blockers at all', () => {
  assert.deepEqual(publishBlockers([item(), item({planner_task_id: 2, seq: 2})]), []);
});

test('UT-LIVE-1-02: an assignee with no login blocks publishing, named once', () => {
  const b = publishBlockers([
    item({planner_task_id: 1, assignee_has_login: false, assignee_name: 'Rhea'}),
    item({planner_task_id: 2, assignee_has_login: false, assignee_name: 'Rhea'}),
  ]);
  const nl = b.find((x) => x.code === 'NO_LOGIN');
  assert.equal(nl!.count, 2);
  // Two steps, one person — the person is named once.
  assert.deepEqual(nl!.detail, ['Rhea']);
});

test('UT-LIVE-1-02: an unassigned step is not ALSO reported as having no login', () => {
  // Otherwise the planner sees two complaints about one problem.
  const b = publishBlockers([item({assignee_agent_id: 0, assignee_has_login: false})]);
  assert.deepEqual(b.map((x) => x.code), ['NO_ASSIGNEE']);
});

test('UT-LIVE-1-01: every blocker is returned at once, not one at a time', () => {
  const b = publishBlockers([
    item({planner_task_id: 1, assignee_agent_id: 0}),
    item({planner_task_id: 2, status: 'needs_info'}),
    item({planner_task_id: 3, assignee_has_login: false, assignee_name: 'Rhea'}),
  ]);
  assert.deepEqual(b.map((x) => x.code).sort(), ['NEEDS_INFO', 'NO_ASSIGNEE', 'NO_LOGIN']);
});

test('UT-LIVE-1-G01: blocker messages are plain language with correct counts', () => {
  assert.match(blockerMessage({code: 'EMPTY', count: 0, detail: []}), /nothing on this timeline/);
  assert.match(blockerMessage({code: 'NO_ASSIGNEE', count: 1, detail: []}), /1 step/);
  assert.match(blockerMessage({code: 'NO_ASSIGNEE', count: 3, detail: []}), /3 steps/);
  assert.match(blockerMessage({code: 'NEEDS_INFO', count: 2, detail: []}), /2 steps are marked/);
  assert.match(blockerMessage({code: 'NO_LOGIN', count: 1, detail: ['Rhea']}), /Rhea doesn't have a login/);

  // No codes, no jargon, nothing technical leaks into what a planner reads.
  for (const b of [
    {code: 'EMPTY' as const, count: 0, detail: []},
    {code: 'NO_ASSIGNEE' as const, count: 2, detail: ['11', '12']},
    {code: 'NEEDS_INFO' as const, count: 1, detail: ['9']},
    {code: 'NO_LOGIN' as const, count: 1, detail: ['Rhea']},
  ]) {
    assert.doesNotMatch(blockerMessage(b), /E-LIVE|planner_task|null|undefined/);
  }
});

// ── canonicalizePublication ────────────────────────────────────────

test('UT-LIVE-1-05: the same input hashes to the same string, twice', () => {
  const items = [item(), item({planner_task_id: 2, seq: 2, planned_start: '08:30'})];
  assert.equal(canonicalizePublication(items), canonicalizePublication(items));
});

test('UT-LIVE-1-05: input order does not matter, seq does', () => {
  const a = item({planner_task_id: 1, seq: 1});
  const b = item({planner_task_id: 2, seq: 2, planned_start: '08:30'});
  // Same items, handed over in the opposite order.
  assert.equal(canonicalizePublication([a, b]), canonicalizePublication([b, a]));
});

test('UT-LIVE-1-05: changing anything that matters changes the string', () => {
  const base = [item()];
  for (const changed of [
    [item({seq: 2})],
    [item({scheduled_minutes: 45})],
    [item({assignee_agent_id: 9})],
    [item({planned_start: '09:00'})],
    [item({work_task_ids: [10, 11]})],
    [item({stage_label: 'Quote'})],
  ]) {
    assert.notEqual(canonicalizePublication(base), canonicalizePublication(changed));
  }
});

test('UT-LIVE-1-05: a pipe or newline in a label cannot forge a field boundary', () => {
  const sneaky = canonicalizePublication([item({stage_label: 'Enquiry|999|0'})]);
  const honest = canonicalizePublication([item({stage_label: 'Enquiry'})]);
  assert.notEqual(sneaky, honest);
  // The raw separator never survives unescaped into the canonical form.
  assert.equal(sneaky.includes('Enquiry|999|0'), false);
});

test('UT-LIVE-1-05: work task ids are order-independent within an item', () => {
  assert.equal(
    canonicalizePublication([item({work_task_ids: [11, 10]})]),
    canonicalizePublication([item({work_task_ids: [10, 11]})]),
  );
});

// ── diffPlan ───────────────────────────────────────────────────────

test('UT-LIVE-1-06: a reordered item is `moved`', () => {
  const before = [item({planner_task_id: 1, seq: 1}), item({planner_task_id: 2, seq: 2})];
  const after = [item({planner_task_id: 1, seq: 2}), item({planner_task_id: 2, seq: 1})];
  const d = diffPlan(before, after);
  assert.deepEqual(d.map((x) => x.change_type), ['moved', 'moved']);
});

test('UT-LIVE-1-06: added, removed, duration_changed and reassigned', () => {
  const before = [item({planner_task_id: 1}), item({planner_task_id: 2, seq: 2})];
  const after = [
    item({planner_task_id: 1, scheduled_minutes: 90}),
    item({planner_task_id: 3, seq: 3}),
  ];
  const d = diffPlan(before, after);
  const byType = d.map((x) => `${x.change_type}:${x.item_ref}`).sort();
  assert.deepEqual(byType, ['added:pt-3', 'duration_changed:pt-1', 'removed:pt-2']);
});

test('UT-LIVE-1-06: one item can produce several changes at once', () => {
  const before = [item({planner_task_id: 1, seq: 1, scheduled_minutes: 30, assignee_agent_id: 7})];
  const after = [item({planner_task_id: 1, seq: 4, scheduled_minutes: 60, assignee_agent_id: 9})];
  const d = diffPlan(before, after);
  assert.deepEqual(d.map((x) => x.change_type).sort(), ['duration_changed', 'moved', 'reassigned']);
  // Each is recorded separately so a report can count reassignments
  // without untangling them from moves.
  assert.equal(d.every((x) => x.item_ref === 'pt-1'), true);
});

test('UT-LIVE-1-06: an unchanged plan produces no changes', () => {
  const items = [item(), item({planner_task_id: 2, seq: 2})];
  assert.deepEqual(diffPlan(items, items), []);
});

test('itemRef is stable and points at the published item, not the row', () => {
  assert.equal(itemRef({planner_task_id: 42}), 'pt-42');
});

// ── canonicalizePublicationV2 (TW-1) ───────────────────────────────

const v2 = (over: Partial<PublicationItemV2> = {}): PublicationItemV2 => ({
  planner_task_id: 1,
  seq: 1,
  scheduled_minutes: 30,
  assignee_agent_id: 7,
  title: 'Visit',
  work_task_ids: [10],
  time_window: null,
  ...over,
});

const sha = (s: string) => createHash('sha256').update(s, 'utf8').digest('hex');

test('UT-TW-1-04-01: v2 line shape — the server line plus five window fields', () => {
  const s = canonicalizePublicationV2([
    v2({time_window: {start_date: '2026-11-03', start_time: '09:00', end_date: '2026-11-03', end_time: '11:00', note: 'Site opens at 9'}}),
  ]);
  assert.equal(
    s,
    'publication|v2\n' + 'item|pt-1|1|30|7|Visit|10|2026-11-03|09:00|2026-11-03|11:00|Site opens at 9\n',
  );
});

test('UT-TW-1-04-01: no window serialises as five empty fields, deterministically', () => {
  const s = canonicalizePublicationV2([v2()]);
  assert.equal(s, 'publication|v2\nitem|pt-1|1|30|7|Visit|10|||||\n');
  assert.equal(s, canonicalizePublicationV2([v2()]));
});

test('UT-TW-1-04-01: changing the window changes the string; a pipe in the note cannot forge a field', () => {
  const base = v2({time_window: {start_date: '2026-11-03', start_time: '09:00', end_date: '2026-11-03', end_time: '11:00', note: ''}});
  const moved = v2({time_window: {start_date: '2026-11-03', start_time: '09:00', end_date: '2026-11-03', end_time: '12:00', note: ''}});
  assert.notEqual(canonicalizePublicationV2([base]), canonicalizePublicationV2([moved]));
  assert.notEqual(canonicalizePublicationV2([base]), canonicalizePublicationV2([v2()]));

  const sneaky = canonicalizePublicationV2([v2({time_window: {...base.time_window!, note: 'a|b'}})]);
  assert.equal(sneaky.includes('a|b'), false);
});

test('UT-TW-1-04-01: order follows seq, then planner task id — the server query order', () => {
  const a = v2({planner_task_id: 2, seq: 1});
  const b = v2({planner_task_id: 1, seq: 1});
  const c = v2({planner_task_id: 3, seq: 0});
  assert.equal(canonicalizePublicationV2([a, b, c]), canonicalizePublicationV2([c, b, a]));
  assert.match(canonicalizePublicationV2([a, b, c]), /^publication\|v2\nitem\|pt-3\|.*\nitem\|pt-1\|.*\nitem\|pt-2\|/);
});

test('UT-TW-1-04-01: pinned v2 hash — drift on either side fails here', () => {
  const s = canonicalizePublicationV2([
    v2({time_window: {start_date: '2026-11-03', start_time: '09:00', end_date: '2026-11-03', end_time: '11:00', note: 'Site opens at 9'}}),
    v2({planner_task_id: 2, seq: 2, title: 'Report', work_task_ids: [11, 12]}),
  ]);
  assert.equal(sha(s), PINNED_V2_HASH);
});

// ── canonicalizePublicationV3 (SCHED-2) ────────────────────────────

const v3 = (over: Partial<PublicationItemV3> = {}): PublicationItemV3 => ({...v2(), start_override: '', ...over});

test('UT-SCHED-2-04-01: v3 line shape — the v2 line plus the start override', () => {
  const s = canonicalizePublicationV3([
    v3({
      start_override: '14:30',
      time_window: {start_date: '2026-11-03', start_time: '09:00', end_date: '2026-11-03', end_time: '11:00', note: 'Site opens at 9'},
    }),
    v3({planner_task_id: 2, seq: 2, title: 'Report', work_task_ids: [11, 12]}),
  ]);
  assert.equal(
    s,
    'publication|v3\n' +
      'item|pt-1|1|30|7|Visit|10|2026-11-03|09:00|2026-11-03|11:00|Site opens at 9|14:30\n' +
      'item|pt-2|2|30|7|Report|11,12||||||\n',
  );
});

test('UT-SCHED-2-04-01: a v3 item with no override is the v2 line plus one empty field', () => {
  const v2Line = canonicalizePublicationV2([v2()]).split('\n')[1];
  const v3Line = canonicalizePublicationV3([v3()]).split('\n')[1];
  assert.equal(v3Line, `${v2Line}|`);
});

test('UT-SCHED-2-04-01: setting or changing the override changes the string', () => {
  assert.notEqual(canonicalizePublicationV3([v3()]), canonicalizePublicationV3([v3({start_override: '14:30'})]));
  assert.notEqual(
    canonicalizePublicationV3([v3({start_override: '14:30'})]),
    canonicalizePublicationV3([v3({start_override: '14:45'})]),
  );
});

test('UT-SCHED-2-04-01: pinned v3 hash — drift on either side fails here', () => {
  const s = canonicalizePublicationV3([
    v3({
      start_override: '14:30',
      time_window: {start_date: '2026-11-03', start_time: '09:00', end_date: '2026-11-03', end_time: '11:00', note: 'Site opens at 9'},
    }),
    v3({planner_task_id: 2, seq: 2, title: 'Report', work_task_ids: [11, 12]}),
  ]);
  assert.equal(sha(s), PINNED_V3_HASH);
});

test('UT-SCHED-2-04-01: v2 is untouched by v3', () => {
  const s = canonicalizePublicationV2([
    v2({time_window: {start_date: '2026-11-03', start_time: '09:00', end_date: '2026-11-03', end_time: '11:00', note: 'Site opens at 9'}}),
    v2({planner_task_id: 2, seq: 2, title: 'Report', work_task_ids: [11, 12]}),
  ]);
  assert.equal(sha(s), PINNED_V2_HASH);
});

test('UT-TW-1-04-01: the v1 canonical form is untouched', () => {
  assert.match(canonicalizePublication([item()]), /^publication\|v1\n/);
  assert.equal(sha(canonicalizePublication([item()])), PINNED_V1_HASH);
});
