import assert from 'node:assert/strict';
import test from 'node:test';
import {
  publishBlockers,
  blockerMessage,
  canonicalizePublication,
  diffPlan,
  itemRef,
  type PublishableItem,
} from './liveModel';

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
