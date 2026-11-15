import assert from 'node:assert/strict';
import test from 'node:test';
import {
  LEVEL_LABELS,
  TOUCHES_LABELS,
  undoState,
  UNDO_PENDING_NOTE,
  levelChangeNeedsConfirm,
  limitProblem,
  prettyPayload,
  parseEditedPayload,
  statusLabel,
  actionTypeLabel,
  isNewlyTold,
} from './approvalsModel';

test('COP-2 labels: levels and touches in plain words', () => {
  assert.equal(LEVEL_LABELS.own, 'Runs on its own');
  assert.equal(LEVEL_LABELS.tell, 'Runs, then tells you');
  assert.equal(LEVEL_LABELS.wait, 'Waits for you');
  assert.equal(TOUCHES_LABELS.internal, 'Stays inside the business');
  assert.equal(TOUCHES_LABELS.money, 'Moves money');
});

test('COP-2 undo: irreversible says cannot be undone, reversible shows a disabled Undo', () => {
  assert.deepEqual(undoState({reversible: false}), {kind: 'cannot', label: "Can't be undone"});
  const u = undoState({reversible: true});
  assert.equal(u.kind, 'undo');
  assert.equal(u.kind === 'undo' && u.disabled, true);
  assert.equal(u.kind === 'undo' && u.note, UNDO_PENDING_NOTE);
});

test('COP-2 confirm: mirrors the server rule (irreversible, leaves the business, not lowered to wait)', () => {
  const base = {reversible: false, touches: 'customer', level: 'tell'};
  assert.equal(levelChangeNeedsConfirm(base), true);
  assert.equal(levelChangeNeedsConfirm({...base, level: 'own'}), true);
  assert.equal(levelChangeNeedsConfirm({...base, level: 'wait'}), false);
  assert.equal(levelChangeNeedsConfirm({...base, reversible: true}), false);
  assert.equal(levelChangeNeedsConfirm({...base, touches: 'internal'}), false);
});

test('COP-2 limit: whole number >= 0, only when the type has a limit', () => {
  assert.equal(limitProblem('50', true), null);
  assert.equal(limitProblem('0', true), null);
  assert.ok(limitProblem('-1', true));
  assert.ok(limitProblem('2.5', true));
  assert.ok(limitProblem('abc', true));
  assert.ok(limitProblem('', true));
  assert.equal(limitProblem('abc', false), null);
});

test('COP-2 payload: pretty prints objects and tolerates plain text and null', () => {
  assert.equal(prettyPayload({a: 1}), '{\n  "a": 1\n}');
  assert.equal(prettyPayload(null), '');
  assert.equal(prettyPayload('hi'), 'hi');
});

test('COP-2 edit: only valid JSON is sent, bad JSON keeps the typing', () => {
  assert.deepEqual(parseEditedPayload('{"a": 1}'), {ok: true, value: {a: 1}});
  assert.equal(parseEditedPayload('{"a": ').ok, false);
  assert.equal(parseEditedPayload('   ').ok, false);
});

test('COP-2 status labels', () => {
  assert.equal(statusLabel('told'), 'Done, then told you');
  assert.equal(statusLabel('seen'), 'Seen');
  assert.equal(statusLabel('approved'), 'Approved');
  assert.equal(statusLabel('edited'), 'Approved with your edits');
  assert.equal(statusLabel('executed'), 'Done');
  assert.equal(statusLabel('rejected'), 'Rejected');
  assert.equal(statusLabel('expired'), 'Expired');
  assert.equal(statusLabel('failed'), 'Failed');
  assert.equal(statusLabel('weird'), 'weird');
  assert.equal(isNewlyTold('told'), true);
  assert.equal(isNewlyTold('seen'), false);
});

test('UT-COP-2-08: action types show their plain name; unknown keys show as-is', () => {
  assert.equal(actionTypeLabel('customer_message'), 'Send a message to a customer');
  assert.equal(actionTypeLabel('money_payment'), 'Charge, pay or refund money');
  assert.equal(actionTypeLabel('something_new'), 'something_new');
  assert.equal(actionTypeLabel(''), '');
  assert.equal(actionTypeLabel(null), '');
});
