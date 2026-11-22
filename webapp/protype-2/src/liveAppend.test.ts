// DEMAND-1 story 01 (decision D-11) — the add-only rule for a live day.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {appendToLiveDay, canonicalItems, isAddOnly, type LiveItem} from './liveAppend';

const item = (over: Partial<LiveItem>): LiveItem => ({
  item_ref: `pt-${over.planner_task_id ?? 1}`,
  planner_task_id: 1,
  seq: 1,
  scheduled_minutes: 30,
  assignee_agent_id: 7,
  title: '',
  work_task_ids: [11],
  work_item_id: 100,
  assignee_has_login: true,
  status: 'planned',
  time_window: null,
  start_override: '',
  ...over,
});

const frozen: LiveItem[] = [
  item({planner_task_id: 1, seq: 1, work_item_id: 100, work_task_ids: [11, 12]}),
  item({planner_task_id: 2, seq: 2, work_item_id: 101, work_task_ids: [13], scheduled_minutes: 45}),
];

test('UT-LIVEADD-01: the new job goes after the last frozen block, in order', () => {
  const live = [...frozen, item({planner_task_id: 9, seq: 1, work_item_id: 200, work_task_ids: [21]}), item({planner_task_id: 10, seq: 2, work_item_id: 200, work_task_ids: [22]})];
  const res = appendToLiveDay(frozen, live, 200);
  assert.deepEqual(res.added.map((i) => [i.item_ref, i.seq]), [['pt-9', 3], ['pt-10', 4]]);
  assert.equal(res.items.length, 4);
  assert.equal(res.addedMinutes, 60);
  assert.deepEqual(res.problems, []);
});

test('UT-LIVEADD-02: frozen blocks are copied unchanged, even when the live plan was rearranged since', () => {
  // The planner swapped the order and re-timed a block after publishing.
  const live = [
    item({planner_task_id: 2, seq: 1, work_item_id: 101, work_task_ids: [13], scheduled_minutes: 90}),
    item({planner_task_id: 1, seq: 2, work_item_id: 100, work_task_ids: [11, 12]}),
    item({planner_task_id: 9, seq: 3, work_item_id: 200, work_task_ids: [21]}),
  ];
  const res = appendToLiveDay(frozen, live, 200);
  assert.deepEqual(res.items.slice(0, 2), frozen);
  assert.equal(isAddOnly(frozen, res.items), true);
});

test('UT-LIVEADD-03: running it twice adds nothing the second time', () => {
  const live = [...frozen, item({planner_task_id: 9, seq: 3, work_item_id: 200, work_task_ids: [21]})];
  const first = appendToLiveDay(frozen, live, 200);
  const second = appendToLiveDay(first.items, live, 200);
  assert.equal(second.added.length, 0);
  assert.deepEqual(second.items, first.items);
});

test('UT-LIVEADD-04: other unpublished changes on the day are NOT swept in', () => {
  const live = [...frozen, item({planner_task_id: 8, seq: 3, work_item_id: 150}), item({planner_task_id: 9, seq: 4, work_item_id: 200})];
  const res = appendToLiveDay(frozen, live, 200);
  assert.deepEqual(res.added.map((i) => i.item_ref), ['pt-9']);
});

test('UT-LIVEADD-05: a block with nobody, no login or "needs info" is a problem', () => {
  const noOne = appendToLiveDay(frozen, [item({planner_task_id: 9, work_item_id: 200, assignee_agent_id: 0})], 200);
  assert.deepEqual(noOne.problems, ['NO_ASSIGNEE']);
  const noLogin = appendToLiveDay(frozen, [item({planner_task_id: 9, work_item_id: 200, assignee_has_login: false})], 200);
  assert.deepEqual(noLogin.problems, ['NO_LOGIN']);
  const info = appendToLiveDay(frozen, [item({planner_task_id: 9, work_item_id: 200, status: 'needs_info'})], 200);
  assert.deepEqual(info.problems, ['NEEDS_INFO']);
});

test('UT-LIVEADD-06: isAddOnly refuses a change, a removal or a reorder of frozen blocks', () => {
  const extra = item({planner_task_id: 9, seq: 3, work_item_id: 200});
  assert.equal(isAddOnly(frozen, [...frozen, extra]), true);
  assert.equal(isAddOnly(frozen, [{...frozen[0], scheduled_minutes: 31}, frozen[1], extra]), false);
  assert.equal(isAddOnly(frozen, [frozen[0], extra]), false);
  assert.equal(isAddOnly(frozen, [{...frozen[1], seq: 1}, {...frozen[0], seq: 2}, extra]), false);
  assert.equal(isAddOnly(frozen, [frozen[0]]), false);
});

test('UT-LIVEADD-07: an old snapshot with no window and no manual start still serialises', () => {
  const old: LiveItem[] = [{item_ref: 'pt-1', planner_task_id: 1, seq: 1, scheduled_minutes: 30, assignee_agent_id: 7, title: 'A|b', work_task_ids: [11]}];
  assert.equal(canonicalItems(old), 'publication|v3\nitem|pt-1|1|30|7|A\\pb|11||||||\n');
});

test('UT-LIVEADD-08: the canonical text is pinned (the server must produce the same hash)', () => {
  const day = appendToLiveDay(
    frozen,
    [item({planner_task_id: 9, seq: 1, work_item_id: 200, work_task_ids: [21, 22], scheduled_minutes: 75, title: 'Order #7', time_window: {start_date: '2026-11-22', start_time: '16:00', end_date: '2026-11-22', end_time: '18:00', note: 'gate code'}})],
    200,
  ).items;
  const text = canonicalItems(day);
  assert.equal(
    text,
    'publication|v3\n' +
      'item|pt-1|1|30|7||11,12||||||\n' +
      'item|pt-2|2|45|7||13||||||\n' +
      'item|pt-9|3|75|7|Order #7|21,22|2026-11-22|16:00|2026-11-22|18:00|gate code|\n',
  );
  assert.equal(createHash('sha256').update(text).digest('hex').length, 64);
});
