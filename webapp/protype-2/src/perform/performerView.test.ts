import assert from 'node:assert/strict';
import test from 'node:test';
import {
  availableActions,
  toPerformerItems,
  newClientEventId,
  optimisticReducer,
  mapActionError,
  type PerformerSnapshot,
  type StatusMap,
  type TaskStatus,
} from './performerView';

// ── UT-APP-1-01..04: availableActions ────────────────────────────────────

test('UT-APP-1-01: not_started offers Start, Done, Blocked, Skip', () => {
  assert.deepEqual(availableActions('not_started'), ['start', 'done', 'blocked', 'skip']);
});

test('UT-APP-1-02: in_progress offers Done, Blocked, Skip (no Start)', () => {
  assert.deepEqual(availableActions('in_progress'), ['done', 'blocked', 'skip']);
});

test('UT-APP-1-03: blocked offers Unblock, Skip', () => {
  assert.deepEqual(availableActions('blocked'), ['unblock', 'skip']);
});

test('UT-APP-1-04: done and skipped offer Reopen only', () => {
  assert.deepEqual(availableActions('done'), ['reopen']);
  assert.deepEqual(availableActions('skipped'), ['reopen']);
});

// ── UT-APP-1-05/06: toPerformerItems ──────────────────────────────────────

function statusEntry(workTaskId: number, status: TaskStatus, overrides: Partial<StatusMap[number]> = {}): StatusMap[number] {
  return {
    work_task_id: workTaskId,
    stage_key: 's1',
    lens_key: 'ops',
    status,
    started_at: null,
    completed_at: null,
    stage_label: 'Stage One',
    lens_label: 'Ops',
    task: 'Do the thing',
    done_when: 'The thing is done',
    expected_minutes: 30,
    ...overrides,
  };
}

test('UT-APP-1-05: items are ordered by planned start, computed from timeline start_time + cumulative seq-ordered durations', () => {
  const snapshot: PerformerSnapshot = {
    date: '2026-10-16',
    items: [
      // Second in seq order within its timeline, so its planned start is
      // 08:00 + 30min (the first item's duration) = 08:30.
      {
        item_ref: 'pt-2',
        planner_task_id: 2,
        timeline_id: 10,
        timeline_start_time: '08:00',
        seq: 2,
        scheduled_minutes: 20,
        assignee_agent_id: 5,
        assignee_name: 'Rhea',
        title: 'Second task',
        work_task_ids: [102],
      },
      {
        item_ref: 'pt-1',
        planner_task_id: 1,
        timeline_id: 10,
        timeline_start_time: '08:00',
        seq: 1,
        scheduled_minutes: 30,
        assignee_agent_id: 5,
        assignee_name: 'Rhea',
        title: 'First task',
        work_task_ids: [101],
      },
    ],
  };
  const statuses: StatusMap = {
    101: statusEntry(101, 'not_started'),
    102: statusEntry(102, 'not_started'),
  };

  const items = toPerformerItems(snapshot, statuses);

  assert.equal(items.length, 2);
  // Out-of-seq-order input is re-sorted by planned start.
  assert.equal(items[0].itemRef, 'pt-1');
  assert.equal(items[0].plannedStartLabel, '08:00');
  assert.equal(items[1].itemRef, 'pt-2');
  assert.equal(items[1].plannedStartLabel, '08:30');
});

test('UT-APP-1-05: a block (multiple work_task_ids) nests its sub-steps and derives one overall status', () => {
  const snapshot: PerformerSnapshot = {
    date: '2026-10-16',
    items: [
      {
        item_ref: 'pt-9',
        planner_task_id: 9,
        timeline_id: 10,
        timeline_start_time: '09:00',
        seq: 1,
        scheduled_minutes: 60,
        assignee_agent_id: 5,
        assignee_name: 'Rhea',
        title: 'Onboarding block',
        work_task_ids: [201, 202],
      },
    ],
  };
  const statuses: StatusMap = {
    201: statusEntry(201, 'done', {stage_key: 's1'}),
    202: statusEntry(202, 'in_progress', {stage_key: 's2'}),
  };

  const [item] = toPerformerItems(snapshot, statuses);

  assert.equal(item.subSteps.length, 2);
  assert.deepEqual(item.subSteps.map((s) => s.workTaskId), [201, 202]);
  // One done, one in progress → the block as a whole reads in_progress,
  // the same precedence jobModel.ts::deriveJobStatus uses.
  assert.equal(item.status, 'in_progress');
});

test('UT-APP-1-05: a block whose every sub-step is done or skipped reads done', () => {
  const snapshot: PerformerSnapshot = {
    date: '2026-10-16',
    items: [
      {
        item_ref: 'pt-9',
        planner_task_id: 9,
        timeline_id: 10,
        timeline_start_time: '09:00',
        seq: 1,
        scheduled_minutes: 60,
        assignee_agent_id: 5,
        assignee_name: 'Rhea',
        title: 'Onboarding block',
        work_task_ids: [201, 202],
      },
    ],
  };
  const statuses: StatusMap = {
    201: statusEntry(201, 'done'),
    202: statusEntry(202, 'skipped'),
  };

  const [item] = toPerformerItems(snapshot, statuses);
  assert.equal(item.status, 'done');
});

test('UT-APP-1-05: a block with one blocked sub-step reads blocked, regardless of the others', () => {
  const snapshot: PerformerSnapshot = {
    date: '2026-10-16',
    items: [
      {
        item_ref: 'pt-9',
        planner_task_id: 9,
        timeline_id: 10,
        timeline_start_time: '09:00',
        seq: 1,
        scheduled_minutes: 60,
        assignee_agent_id: 5,
        assignee_name: 'Rhea',
        title: 'Onboarding block',
        work_task_ids: [201, 202],
      },
    ],
  };
  const statuses: StatusMap = {
    201: statusEntry(201, 'done'),
    202: statusEntry(202, 'blocked'),
  };

  const [item] = toPerformerItems(snapshot, statuses);
  assert.equal(item.status, 'blocked');
});

test('UT-APP-1-06: an item whose sub-step has no entry in the live status map is still returned, not dropped', () => {
  // This is what "removed from the live plan but present in the snapshot"
  // means in practice: toPerformerItems never looks at planner_task at
  // all, only at the frozen snapshot plus whatever live status it is
  // handed. A sparse or stale statuses map must degrade, never drop.
  const snapshot: PerformerSnapshot = {
    date: '2026-10-16',
    items: [
      {
        item_ref: 'pt-3',
        planner_task_id: 3,
        timeline_id: 10,
        timeline_start_time: '08:00',
        seq: 1,
        scheduled_minutes: 15,
        assignee_agent_id: 5,
        assignee_name: 'Rhea',
        title: 'Orphaned-looking task',
        work_task_ids: [301],
      },
    ],
  };
  const statuses: StatusMap = {}; // nothing matches — simulates a stale/sparse join

  const items = toPerformerItems(snapshot, statuses);

  assert.equal(items.length, 1);
  assert.equal(items[0].itemRef, 'pt-3');
  assert.equal(items[0].subSteps.length, 1);
  assert.equal(items[0].subSteps[0].status, 'not_started'); // safe default, not a crash
  assert.equal(items[0].status, 'not_started');
});

test('toPerformerItems: multiple timelines on the same day are merged and sorted together', () => {
  const snapshot: PerformerSnapshot = {
    date: '2026-10-16',
    items: [
      {
        item_ref: 'pt-5',
        planner_task_id: 5,
        timeline_id: 20, // a different plan's timeline, later start
        timeline_start_time: '07:00',
        seq: 1,
        scheduled_minutes: 10,
        assignee_agent_id: 5,
        assignee_name: 'Rhea',
        title: 'Early task from plan B',
        work_task_ids: [501],
      },
      {
        item_ref: 'pt-1',
        planner_task_id: 1,
        timeline_id: 10,
        timeline_start_time: '08:00',
        seq: 1,
        scheduled_minutes: 30,
        assignee_agent_id: 5,
        assignee_name: 'Rhea',
        title: 'Task from plan A',
        work_task_ids: [101],
      },
    ],
  };
  const statuses: StatusMap = {501: statusEntry(501, 'not_started'), 101: statusEntry(101, 'not_started')};

  const items = toPerformerItems(snapshot, statuses);
  assert.deepEqual(items.map((i) => i.itemRef), ['pt-5', 'pt-1']);
});

// ── UT-APP-1-07: newClientEventId ─────────────────────────────────────────

test('UT-APP-1-07: newClientEventId returns a different value each call', () => {
  const a = newClientEventId();
  const b = newClientEventId();
  assert.notEqual(a, b);
  assert.ok(a.length > 0);
  assert.ok(b.length > 0);
});

// ── UT-APP-1-08: optimistic reducer ───────────────────────────────────────

test('UT-APP-1-08: optimistic apply updates the status immediately', () => {
  const state: StatusMap = {101: statusEntry(101, 'not_started')};
  const next = optimisticReducer(state, {type: 'apply', workTaskId: 101, nextStatus: 'in_progress', at: 1000});

  assert.equal(next[101].status, 'in_progress');
  assert.equal(next[101].started_at, 1000);
  // The original state is untouched (pure reducer).
  assert.equal(state[101].status, 'not_started');
});

test('UT-APP-1-08: confirm replaces the optimistic guess with the server truth', () => {
  const state: StatusMap = {101: statusEntry(101, 'not_started')};
  const applied = optimisticReducer(state, {type: 'apply', workTaskId: 101, nextStatus: 'in_progress', at: 1000});
  const confirmed = optimisticReducer(applied, {
    type: 'confirm',
    workTaskId: 101,
    entry: statusEntry(101, 'in_progress', {started_at: 999}), // server's own timestamp
  });

  assert.equal(confirmed[101].status, 'in_progress');
  assert.equal(confirmed[101].started_at, 999);
});

test('UT-APP-1-08: a failed tap reverts to exactly the prior state', () => {
  const before = statusEntry(101, 'not_started');
  const state: StatusMap = {101: before};
  const applied = optimisticReducer(state, {type: 'apply', workTaskId: 101, nextStatus: 'in_progress', at: 1000});

  assert.equal(applied[101].status, 'in_progress'); // the optimistic guess took effect

  const reverted = optimisticReducer(applied, {type: 'revert', workTaskId: 101, previous: before});
  assert.deepEqual(reverted[101], before);
});

// ── UT-APP-1-G01: error-to-message mapper covers every E-APP code ────────

test('UT-APP-1-G01: offline maps to E-APP-001', () => {
  const info = mapActionError({offline: true});
  assert.equal(info.code, 'E-APP-001');
  assert.match(info.message, /no connection/i);
});

test('UT-APP-1-G01: a 401 maps to E-APP-004', () => {
  const info = mapActionError({status: 401});
  assert.equal(info.code, 'E-APP-004');
  assert.match(info.message, /sign in again/i);
});

test('UT-APP-1-G01: a 403 or 404 maps to E-APP-003', () => {
  assert.equal(mapActionError({status: 403}).code, 'E-APP-003');
  assert.equal(mapActionError({status: 404}).code, 'E-APP-003');
  assert.match(mapActionError({status: 404}).message, /can't change this step/i);
});

test('UT-APP-1-G01: a 400/422 with a server message passes that message through as-is', () => {
  const info = mapActionError({status: 400, serverMessage: 'Pick a reason so the team knows why. (E-LOG-002)'});
  // The server's own message is already friendly (VAL-1) — shown as-is,
  // not remapped to a generic "didn't save" message.
  assert.equal(info.message, 'Pick a reason so the team knows why. (E-LOG-002)');
  assert.equal(info.code, 'E-LOG-002'); // the embedded code is extracted for logging
});

test('UT-APP-1-G01: a 5xx or transport failure maps to E-APP-002', () => {
  const info = mapActionError({status: 500});
  assert.equal(info.code, 'E-APP-002');
  assert.match(info.message, /didn't save/i);
});

test('UT-APP-1-G01: anything else falls through to E-APP-005', () => {
  const info = mapActionError({});
  assert.equal(info.code, 'E-APP-005');
  assert.match(info.message, /something went wrong/i);
});

// Never leaks raw technical text, matching the rest of the catalog.
test('UT-APP-1-G01: no mapped message contains jargon or a bare stack-ish token', () => {
  const infos = [
    mapActionError({offline: true}),
    mapActionError({status: 401}),
    mapActionError({status: 403}),
    mapActionError({status: 500}),
    mapActionError({}),
  ];
  for (const info of infos) {
    assert.doesNotMatch(info.message, /undefined|null|TypeError|stack trace/i);
  }
});
