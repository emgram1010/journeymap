import assert from 'node:assert/strict';
import test from 'node:test';
import {toSessions, nextItemToWork, canFinishSession, type Session} from './sessionModel';
import type {PerformerItem, PerformerSubStep, SessionInfo, TaskStatus} from './performerView';

// ── Fixtures ───────────────────────────────────────────────────────────

function session(overrides: Partial<SessionInfo> = {}): SessionInfo {
  return {
    workItemId: 8,
    title: 'Quote for the Garcia party',
    flowTitle: 'Quote Request Handling',
    versionNo: 1,
    planId: 14,
    planName: 'Quotes week of Oct 19',
    ...overrides,
  };
}

function subStep(overrides: Partial<PerformerSubStep> = {}): PerformerSubStep {
  return {
    workTaskId: 1,
    stageKey: 's1',
    lensKey: 'lens-2',
    status: 'not_started',
    startedAt: null,
    completedAt: null,
    stageLabel: 'Log the request',
    lensLabel: 'Sales Coordinator',
    task: 'Log the request in the sheet',
    doneWhen: 'Customer name, event date and contact are recorded',
    expectedMinutes: 10,
    session: session(),
    notes: [],
    ...overrides,
  };
}

function item(overrides: Partial<PerformerItem> = {}, subStepOverrides: Partial<PerformerSubStep> = {}): PerformerItem {
  const sub = subStep(subStepOverrides);
  return {
    itemRef: `pt-${sub.workTaskId}`,
    plannerTaskId: sub.workTaskId,
    title: '',
    assigneeAgentId: 21,
    assigneeName: 'Rochelle',
    scheduledMinutes: sub.expectedMinutes ?? 0,
    plannedStartMinutes: 540, // 09:00
    plannedStartLabel: '09:00',
    status: sub.status,
    subSteps: [sub],
    ...overrides,
  };
}

// ── UT-APP-2-01..: toSessions groups by work_item_id, not by timeline ────

test('UT-APP-2-S01: items from the same job group into one session', () => {
  const items = [
    item({plannedStartMinutes: 540, plannedStartLabel: '09:00'}, {workTaskId: 1, stageKey: 's1'}),
    item({plannedStartMinutes: 550, plannedStartLabel: '09:10'}, {workTaskId: 2, stageKey: 's2'}),
    item({plannedStartMinutes: 575, plannedStartLabel: '09:35'}, {workTaskId: 3, stageKey: 's3'}),
  ];
  const sessions = toSessions(items);
  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].workItemId, 8);
  assert.equal(sessions[0].items.length, 3);
});

test('UT-APP-2-S02: two jobs on the same flow produce two separate sessions', () => {
  const items = [
    item({plannedStartMinutes: 540, plannedStartLabel: '09:00'}, {workTaskId: 1, session: session({workItemId: 8, title: 'Quote for the Garcia party'})}),
    item({plannedStartMinutes: 660, plannedStartLabel: '11:00'}, {workTaskId: 4, session: session({workItemId: 9, title: 'Quote for the Nguyen wedding'})}),
  ];
  const sessions = toSessions(items);
  assert.equal(sessions.length, 2);
  const titles = sessions.map((s) => s.title).sort();
  assert.deepEqual(titles, ['Quote for the Garcia party', 'Quote for the Nguyen wedding']);
});

test('UT-APP-2-S03: sessions are ordered by their earliest item\'s planned start', () => {
  const items = [
    item({plannedStartMinutes: 660, plannedStartLabel: '11:00'}, {workTaskId: 4, session: session({workItemId: 9, title: 'Second'})}),
    item({plannedStartMinutes: 540, plannedStartLabel: '09:00'}, {workTaskId: 1, session: session({workItemId: 8, title: 'First'})}),
  ];
  const sessions = toSessions(items);
  assert.deepEqual(sessions.map((s) => s.title), ['First', 'Second']);
});

test('UT-APP-2-S04: items within a session are ordered by planned start, regardless of input order', () => {
  const items = [
    item({plannedStartMinutes: 575, plannedStartLabel: '09:35'}, {workTaskId: 3, stageKey: 's3'}),
    item({plannedStartMinutes: 540, plannedStartLabel: '09:00'}, {workTaskId: 1, stageKey: 's1'}),
    item({plannedStartMinutes: 550, plannedStartLabel: '09:10'}, {workTaskId: 2, stageKey: 's2'}),
  ];
  const sessions = toSessions(items);
  assert.deepEqual(sessions[0].items.map((i) => i.subSteps[0].stageKey), ['s1', 's2', 's3']);
});

test('UT-APP-2-S05: a session with no provenance (missing session) still appears, never dropped', () => {
  const items = [item({}, {workTaskId: 1, session: null})];
  const sessions = toSessions(items);
  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].items.length, 1);
});

test('UT-APP-2-S06: two sessionless items are NOT merged into one bucket', () => {
  const items = [
    item({plannedStartMinutes: 540}, {workTaskId: 1, session: null}),
    item({plannedStartMinutes: 600}, {workTaskId: 2, session: null}),
  ];
  const sessions = toSessions(items);
  assert.equal(sessions.length, 2);
});

// ── UT-APP-2-S07..: session status, derived the same way a block's is ───

function statusesOf(statuses: TaskStatus[]): Session {
  const items = statuses.map((status, i) =>
    item({plannedStartMinutes: 540 + i * 10, status}, {workTaskId: i + 1, status}),
  );
  return toSessions(items)[0];
}

test('UT-APP-2-S07: all not_started -> session is not_started', () => {
  assert.equal(statusesOf(['not_started', 'not_started']).status, 'not_started');
});

test('UT-APP-2-S08: any in_progress -> session is in_progress', () => {
  assert.equal(statusesOf(['done', 'in_progress', 'not_started']).status, 'in_progress');
});

test('UT-APP-2-S09: any blocked -> session is blocked, wins over in_progress', () => {
  assert.equal(statusesOf(['in_progress', 'blocked']).status, 'blocked');
});

test('UT-APP-2-S10: every step done or skipped -> session is done', () => {
  assert.equal(statusesOf(['done', 'skipped', 'done']).status, 'done');
});

// ── UT-APP-2-S11..: progress + duration totals ───────────────────────────

test('UT-APP-2-S11: doneCount counts done and skipped; totalCount is every item', () => {
  const s = statusesOf(['done', 'skipped', 'not_started', 'in_progress']);
  assert.equal(s.doneCount, 2);
  assert.equal(s.totalCount, 4);
});

test('UT-APP-2-S12: totalScheduledMinutes sums every item\'s scheduled minutes', () => {
  const items = [
    item({plannedStartMinutes: 540, scheduledMinutes: 10}, {workTaskId: 1}),
    item({plannedStartMinutes: 550, scheduledMinutes: 25}, {workTaskId: 2}),
    item({plannedStartMinutes: 575, scheduledMinutes: 10}, {workTaskId: 3}),
  ];
  assert.equal(toSessions(items)[0].totalScheduledMinutes, 45);
});

test('UT-APP-2-S13: plannedStartLabel/Minutes come from the session\'s first (earliest) item', () => {
  const items = [
    item({plannedStartMinutes: 550, plannedStartLabel: '09:10'}, {workTaskId: 2}),
    item({plannedStartMinutes: 540, plannedStartLabel: '09:00'}, {workTaskId: 1}),
  ];
  const s = toSessions(items)[0];
  assert.equal(s.plannedStartMinutes, 540);
  assert.equal(s.plannedStartLabel, '09:00');
});

// ── UT-APP-2-S14..: nextItemToWork (D-4: no strict order, just a suggestion) ──

test('UT-APP-2-S14: nextItemToWork returns the first not-done, not-skipped item in planned order', () => {
  const s = statusesOf(['done', 'not_started', 'in_progress']);
  const next = nextItemToWork(s);
  assert.equal(next?.subSteps[0].workTaskId, 2);
});

test('UT-APP-2-S15: nextItemToWork returns null once every item is done or skipped', () => {
  const s = statusesOf(['done', 'skipped']);
  assert.equal(nextItemToWork(s), null);
});

test('UT-APP-2-S16: nextItemToWork does not require strict order -- an out-of-order done step is skipped over', () => {
  // Step 2 finished before step 1 (D-4: order is a suggestion, not a lock).
  const s = statusesOf(['not_started', 'done', 'not_started']);
  const next = nextItemToWork(s);
  assert.equal(next?.subSteps[0].workTaskId, 1);
});

// ── UT-APP-2-S17..: canFinishSession (D-2: every step done or skipped) ──

test('UT-APP-2-S17: canFinishSession is false while any step is open', () => {
  assert.equal(canFinishSession(statusesOf(['done', 'in_progress'])), false);
  assert.equal(canFinishSession(statusesOf(['done', 'not_started'])), false);
  assert.equal(canFinishSession(statusesOf(['done', 'blocked'])), false);
});

test('UT-APP-2-S18: canFinishSession is true once every step is done or skipped', () => {
  assert.equal(canFinishSession(statusesOf(['done', 'skipped', 'done'])), true);
});

// ── UT-APP-2-S19: missing title/flow/plan text degrades to a safe default, never throws ──

test('UT-APP-2-S19: null session text fields degrade to safe defaults', () => {
  const items = [item({}, {workTaskId: 1, session: session({title: null, flowTitle: null, planName: null})})];
  const s = toSessions(items)[0];
  assert.equal(typeof s.title, 'string');
  assert.equal(typeof s.flowTitle, 'string');
  assert.equal(typeof s.planName, 'string');
});
