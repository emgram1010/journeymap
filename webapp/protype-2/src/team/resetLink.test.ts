import assert from 'node:assert/strict';
import test from 'node:test';
import {buildResetLink, newPasswordProblem, parseResetHash, resetBlockedBy} from './resetLink';

// SAFE-1 story 03 — the reset-link rules the screen can know before the round trip.
// The server (admin/user_reset_link) is the authority and checks every one again, in this order.

const member = {id: 3, role: 'member' as const, is_active: true, is_owner: false};
const admin2 = {id: 5, role: 'admin' as const, is_active: true, is_owner: false};
const owner = {id: 2, role: 'admin' as const, is_active: true, is_owner: true};
const off = {id: 4, role: 'member' as const, is_active: false, is_owner: false};
const adminViewer = {id: 9, role: 'admin'};
const ownerViewer = {id: 2, role: 'admin'};

test('T-SAFE-03-1: an admin may reset a member', () => {
  assert.equal(resetBlockedBy(adminViewer, false, member, false), null);
});

test('T-SAFE-03-2: a member may not reset anyone', () => {
  assert.equal(resetBlockedBy({id: 3, role: 'member'}, false, member, false), 'E-USR-001');
  assert.equal(resetBlockedBy(null, false, member, false), 'E-USR-001');
});

test('T-SAFE-03-8: only the owner resets an admin, and nobody resets the owner', () => {
  assert.equal(resetBlockedBy(adminViewer, false, admin2, false), 'E-SAFE-006');
  assert.equal(resetBlockedBy(ownerViewer, true, admin2, false), null);
  assert.equal(resetBlockedBy(adminViewer, false, owner, false), 'E-SAFE-007');
});

test('T-SAFE-03-13: resetting yourself, an AI or a switched-off person is refused', () => {
  assert.equal(resetBlockedBy({id: 3, role: 'admin'}, false, member, false), 'E-SAFE-009');
  assert.equal(resetBlockedBy(adminViewer, false, member, true), 'E-SAFE-010');
  assert.equal(resetBlockedBy(adminViewer, false, off, false), 'E-SAFE-004');
  // The owner resetting themself gets the "yourself" answer, not the "owner" one.
  assert.equal(resetBlockedBy(ownerViewer, true, owner, false), 'E-SAFE-009');
});

test('T-SAFE-03-14: the link keeps the token out of the path and the query (never sent to a server)', () => {
  const link = buildResetLink('https://app.example.com', 'abc-123', 'dana+x@example.com');
  assert.equal(link, 'https://app.example.com/set-password#token=abc-123&email=dana%2Bx%40example.com');
  assert.equal(new URL(link).search, '');
  assert.equal(new URL(link).pathname, '/set-password');
});

test('T-SAFE-03-15: the page reads the link back, and refuses a broken one', () => {
  assert.deepEqual(parseResetHash('#token=abc-123&email=dana%2Bx%40example.com'), {
    token: 'abc-123',
    email: 'dana+x@example.com',
  });
  assert.equal(parseResetHash(''), null);
  assert.equal(parseResetHash('#token=abc'), null);
  assert.equal(parseResetHash('#email=a@b.co'), null);
  assert.equal(parseResetHash('#token=&email=a@b.co'), null);
});

test('T-SAFE-03-16: the new password must meet the same rules as everywhere else', () => {
  assert.equal(newPasswordProblem('Abcdefg1', 'Abcdefg1'), null);
  assert.match(newPasswordProblem('short1', 'short1') ?? '', /8 characters/);
  assert.match(newPasswordProblem('abcdefgh', 'abcdefgh') ?? '', /number/);
  assert.match(newPasswordProblem('Abcdefg1', 'Abcdefg2') ?? '', /match/);
});
