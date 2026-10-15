import assert from 'node:assert/strict';
import test from 'node:test';
import {
  canTransition,
  replay,
  stageComplete,
  transitionMessage,
  REASON_CODES,
  type EventType,
  type TaskStatus,
} from './logModel';

const STATUSES: TaskStatus[] = ['not_started', 'in_progress', 'blocked', 'done', 'skipped'];
const EVENTS: EventType[] = [
  'started',
  'completed',
  'blocked',
  'unblocked',
  'skipped',
  'reopened',
  'note',
];

/** The epic's table, transcribed independently of the implementation. */
const ALLOWED: Record<string, TaskStatus> = {
  'not_started|started': 'in_progress',
  'not_started|blocked': 'blocked',
  'not_started|skipped': 'skipped',
  'not_started|completed': 'done',
  'in_progress|completed': 'done',
  'in_progress|blocked': 'blocked',
  'in_progress|skipped': 'skipped',
  'blocked|unblocked': 'in_progress',
  'blocked|skipped': 'skipped',
  'done|reopened': 'in_progress',
  'skipped|reopened': 'in_progress',
};

test('UT-LOG-1-01: every (status, event) pair matches the epic table exactly', () => {
  for (const from of STATUSES) {
    for (const event of EVENTS) {
      // `note` is allowed everywhere and changes nothing — handled separately.
      if (event === 'note') continue;

      const key = `${from}|${event}`;
      const expected = ALLOWED[key];
      // `blocked` needs a reason; supply a valid one so this test is
      // about the transition table, not the reason rule.
      const r = canTransition(from, event, 'other');

      if (expected) {
        assert.equal(r.allowed, true, `${key} should be allowed`);
        assert.equal(r.to, expected, `${key} should end at ${expected}`);
      } else {
        assert.equal(r.allowed, false, `${key} should be refused`);
        assert.equal(r.code, 'E-LOG-001');
      }
    }
  }
});

test('UT-LOG-1-01: a note is allowed from every status and changes nothing', () => {
  for (const from of STATUSES) {
    const r = canTransition(from, 'note');
    assert.equal(r.allowed, true);
    assert.equal(r.to, from);
  }
});

test('UT-LOG-1-02: blocked without a reason is refused', () => {
  for (const from of ['not_started', 'in_progress'] as TaskStatus[]) {
    assert.deepEqual(canTransition(from, 'blocked'), {allowed: false, to: null, code: 'E-LOG-002'});
    assert.equal(canTransition(from, 'blocked', '').code, 'E-LOG-002');
    assert.equal(canTransition(from, 'blocked', null).code, 'E-LOG-002');
  }
});

test('UT-LOG-1-03: blocked is accepted with each of the four reasons', () => {
  for (const reason of REASON_CODES) {
    const r = canTransition('in_progress', 'blocked', reason);
    assert.equal(r.allowed, true, `${reason} should be accepted`);
    assert.equal(r.to, 'blocked');
  }
  assert.equal(REASON_CODES.length, 4);
});

test('UT-LOG-1-05 / E-LOG-005: an invented reason is refused', () => {
  assert.equal(canTransition('in_progress', 'blocked', 'because_i_said_so').code, 'E-LOG-005');
});

test('UT-LOG-1-08: completed straight from not_started is allowed, with no start time', () => {
  const r = canTransition('not_started', 'completed');
  assert.equal(r.allowed, true);
  assert.equal(r.to, 'done');

  const state = replay([{event_type: 'completed', occurred_at: 500}]);
  assert.equal(state.status, 'done');
  // The honest answer: we do not know when it started.
  assert.equal(state.started_at, null);
  assert.equal(state.completed_at, 500);
});

test('UT-LOG-1-04: replaying a mixed sequence gives the right status and times', () => {
  const state = replay([
    {event_type: 'started', occurred_at: 100},
    {event_type: 'blocked', occurred_at: 200, reason_code: 'waiting_on_someone'},
    {event_type: 'unblocked', occurred_at: 300},
    {event_type: 'note', occurred_at: 350},
    {event_type: 'completed', occurred_at: 400},
  ]);
  assert.deepEqual(state, {
    status: 'done',
    started_at: 100,
    completed_at: 400,
    rejected: [],
  });
});

test('UT-LOG-1-05: reopen then complete keeps the FIRST start, updates completion', () => {
  const state = replay([
    {event_type: 'started', occurred_at: 100},
    {event_type: 'completed', occurred_at: 200},
    {event_type: 'reopened', occurred_at: 300},
    {event_type: 'started', occurred_at: 310},
    {event_type: 'completed', occurred_at: 400},
  ]);
  assert.equal(state.status, 'done');
  // The work really did begin at 100; overwriting that would erase
  // how long it actually spanned.
  assert.equal(state.started_at, 100);
  assert.equal(state.completed_at, 400);
});

test('UT-LOG-1-04: reopening clears the completion time until it completes again', () => {
  const state = replay([
    {event_type: 'started', occurred_at: 100},
    {event_type: 'completed', occurred_at: 200},
    {event_type: 'reopened', occurred_at: 300},
  ]);
  assert.equal(state.status, 'in_progress');
  assert.equal(state.completed_at, null);
  assert.equal(state.started_at, 100);
});

test('UT-LOG-1-04: an invalid event in the history is skipped and reported', () => {
  // A replay must survive bad history in order to report it.
  const state = replay([
    {event_type: 'started', occurred_at: 100},
    {event_type: 'started', occurred_at: 150}, // already in progress
    {event_type: 'completed', occurred_at: 200},
  ]);
  assert.equal(state.status, 'done');
  assert.deepEqual(state.rejected, [1]);
});

test('UT-LOG-1-04: an empty log replays to not_started', () => {
  assert.deepEqual(replay([]), {
    status: 'not_started',
    started_at: null,
    completed_at: null,
    rejected: [],
  });
});

test('UT-LOG-1-04: skipping records a completion time too', () => {
  const state = replay([{event_type: 'skipped', occurred_at: 700}]);
  assert.equal(state.status, 'skipped');
  assert.equal(state.completed_at, 700);
});

test('UT-LOG-1-06: stageComplete under the MVP fixed rule', () => {
  const rule = 'all_required_done' as const;
  assert.equal(stageComplete(rule, [{status: 'done'}, {status: 'done'}]), true);
  assert.equal(stageComplete(rule, [{status: 'done'}, {status: 'skipped'}]), true);
  assert.equal(stageComplete(rule, [{status: 'done'}, {status: 'in_progress'}]), false);
  assert.equal(stageComplete(rule, [{status: 'done'}, {status: 'blocked'}]), false);
  assert.equal(stageComplete(rule, [{status: 'not_started'}]), false);
});

test('UT-LOG-1-06: the deferred rules behave as specified', () => {
  assert.equal(stageComplete('any_done', [{status: 'done'}, {status: 'not_started'}]), true);
  assert.equal(stageComplete('any_done', [{status: 'skipped'}, {status: 'not_started'}]), false);
  // Manual never auto-advances, whatever the tasks say.
  assert.equal(stageComplete('manual', [{status: 'done'}, {status: 'done'}]), false);
});

test('UT-LOG-1-06: an empty stage is never complete', () => {
  // "every task is finished" is vacuously true for an empty list, so
  // this is the case a naive implementation gets wrong — it would
  // advance a stage nobody has worked.
  assert.equal(stageComplete('all_required_done', []), false);
  assert.equal(stageComplete('any_done', []), false);
});

test('transitionMessage says what state it is in and what to do next', () => {
  assert.match(transitionMessage('done', 'started'), /already done.*Reopen/);
  assert.match(transitionMessage('skipped', 'completed'), /skipped.*Reopen/);
  assert.match(transitionMessage('blocked', 'completed'), /blocked.*Unblock/);
  assert.match(transitionMessage('in_progress', 'started'), /already in progress/);

  // Nothing technical ever reaches the performer.
  for (const from of STATUSES) {
    const m = transitionMessage(from, 'started');
    assert.doesNotMatch(m, /E-LOG|work_task|null|undefined|status=/);
  }
});
