import assert from 'node:assert/strict';
import test from 'node:test';
import {
  mergeTeam,
  activeAdminCount,
  isValidRole,
  canManageTeam,
  roleChangeBlockedBy,
  statusChangeBlockedBy,
  createBlockedBy,
  profileUpdateBlockedBy,
  deleteBlockedBy,
  emailLooksRight,
  passwordMeetsRules,
  grantChangeBlockedBy,
  hasAnyModule,
  hasModule,
  isValidModule,
  noModules,
  MODULES,
  MODULE_LABELS,
  type NewPersonDraft,
  type RawGrant,
  type RawMember,
  type RawStatus,
} from './teamModel';

// USR-1 — the Team page's pure logic.
//
// Every rule tested here is ALSO enforced on the server, which is the only
// authority. This module exists so the UI can grey a control out before the
// user clicks it, not so the browser can decide. The two copies are kept
// honest by using the same cases on both sides — the LOG-1 lesson, where an
// audit holding its own copy of a rule eventually disagreed with the engine
// and sounded equally certain either way.

const admin: RawMember = {id: 1, name: 'Jav', email: 'jav@example.com', account_id: 2, role: 'admin'};
const admin2: RawMember = {id: 2, name: 'Ada', email: 'ada@example.com', account_id: 2, role: 'admin'};
const member: RawMember = {id: 3, name: 'Sam', email: 'sam@example.com', account_id: 2, role: 'member'};
const outsider: RawMember = {id: 9, name: 'Nope', email: 'nope@example.com', account_id: 7, role: 'admin'};

// ── mergeTeam ────────────────────────────────────────────────────────────────

test('UT-USR-1-01: a member with no status row is active', () => {
  const merged = mergeTeam([member], []);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].is_active, true);
});

test('UT-USR-1-02: a status row marks a member inactive', () => {
  const statuses: RawStatus[] = [{user_id: 3, account_id: 2, is_active: false}];
  assert.equal(mergeTeam([member], statuses)[0].is_active, false);
});

test('UT-USR-1-03: an explicit active status row keeps the member active', () => {
  const statuses: RawStatus[] = [{user_id: 3, account_id: 2, is_active: true}];
  assert.equal(mergeTeam([member], statuses)[0].is_active, true);
});

// An untouched bool column reads back as `false`, and `false == null` is true
// in the Xano engine (CLAUDE.md, VAR-1). The merge must never infer "active"
// from a falsy value — only from an ABSENT row.
test('UT-USR-1-04: a status row whose is_active is null is treated as inactive, not active', () => {
  const statuses = [{user_id: 3, account_id: 2, is_active: null}] as unknown as RawStatus[];
  assert.equal(mergeTeam([member], statuses)[0].is_active, false);
});

test('UT-USR-1-05: a status row for someone not in the list is ignored', () => {
  const statuses: RawStatus[] = [{user_id: 999, account_id: 2, is_active: false}];
  assert.equal(mergeTeam([member], statuses)[0].is_active, true);
});

test('UT-USR-1-06: an inactive member is still listed, never dropped', () => {
  const statuses: RawStatus[] = [{user_id: 3, account_id: 2, is_active: false}];
  assert.equal(mergeTeam([admin, member], statuses).length, 2);
});

test('UT-USR-1-07: a missing role reads as member, never as admin', () => {
  const noRole = {id: 4, name: 'Blank', email: 'b@example.com', account_id: 2, role: null} as RawMember;
  assert.equal(mergeTeam([noRole], [])[0].role, 'member');
});

test('UT-USR-1-08: an empty-string role reads as member', () => {
  // An untouched enum column comes back as "" rather than null (CLAUDE.md).
  const blank = {id: 5, name: 'Blank', email: 'c@example.com', account_id: 2, role: ''} as RawMember;
  assert.equal(mergeTeam([blank], [])[0].role, 'member');
});

// ── activeAdminCount ─────────────────────────────────────────────────────────

test('UT-USR-1-09: counts only admins', () => {
  assert.equal(activeAdminCount(mergeTeam([admin, admin2, member], [])), 2);
});

test('UT-USR-1-10: a deactivated admin does not count', () => {
  const statuses: RawStatus[] = [{user_id: 2, account_id: 2, is_active: false}];
  assert.equal(activeAdminCount(mergeTeam([admin, admin2], statuses)), 1);
});

// ── isValidRole ──────────────────────────────────────────────────────────────

test('UT-USR-1-11: only admin and member are valid roles', () => {
  assert.equal(isValidRole('admin'), true);
  assert.equal(isValidRole('member'), true);
  assert.equal(isValidRole('superuser'), false);
  assert.equal(isValidRole(''), false);
  assert.equal(isValidRole('Admin'), false);
});

// ── canManageTeam ────────────────────────────────────────────────────────────

test('UT-USR-1-12: only an admin may manage the team', () => {
  assert.equal(canManageTeam(admin), true);
  assert.equal(canManageTeam(member), false);
  assert.equal(canManageTeam(null), false);
});

// ── roleChangeBlockedBy ──────────────────────────────────────────────────────

test('UT-USR-1-13: a member cannot change anyone', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(roleChangeBlockedBy(member, admin.id, 'member', team), 'E-USR-001');
});

test('UT-USR-1-14: you cannot change your own role, even with another admin present', () => {
  const team = mergeTeam([admin, admin2], []);
  assert.equal(roleChangeBlockedBy(admin, admin.id, 'member', team), 'E-USR-004');
});

test('UT-USR-1-15: someone in another account is not found', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(roleChangeBlockedBy(admin, outsider.id, 'member', team), 'E-USR-002');
});

test('UT-USR-1-16: an unknown role is refused', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(roleChangeBlockedBy(admin, member.id, 'superuser', team), 'E-USR-009');
});

// Precedence matters: when the sole admin tries to demote themselves BOTH the
// last-admin rule and the no-self-change rule apply. The last-admin reason is
// the more useful one to show, so it is checked first.
test('UT-USR-1-17: the sole admin self-demoting is refused as last-admin, not as self-change', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(roleChangeBlockedBy(admin, admin.id, 'member', team), 'E-USR-003');
});

test('UT-USR-1-17b: a deactivated admin does not keep the account out of last-admin', () => {
  const statuses: RawStatus[] = [{user_id: 2, account_id: 2, is_active: false}];
  const team = mergeTeam([admin, admin2, member], statuses);
  assert.equal(roleChangeBlockedBy(admin, admin.id, 'member', team), 'E-USR-003');
});

test('UT-USR-1-18: demoting another admin succeeds while one remains', () => {
  const team = mergeTeam([admin, admin2, member], []);
  assert.equal(roleChangeBlockedBy(admin, admin2.id, 'member', team), null);
});

test('UT-USR-1-19: promoting a member is always allowed for an admin', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(roleChangeBlockedBy(admin, member.id, 'admin', team), null);
});

// ── statusChangeBlockedBy ────────────────────────────────────────────────────

test('UT-USR-1-20: a member cannot deactivate anyone', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(statusChangeBlockedBy(member, admin.id, false, team), 'E-USR-001');
});

test('UT-USR-1-21: you cannot deactivate yourself, even with another admin present', () => {
  const team = mergeTeam([admin, admin2], []);
  assert.equal(statusChangeBlockedBy(admin, admin.id, false, team), 'E-USR-004');
});

test('UT-USR-1-22: the sole admin cannot deactivate themselves', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(statusChangeBlockedBy(admin, admin.id, false, team), 'E-USR-003');
});

test('UT-USR-1-22b: deactivating another admin is fine while one remains', () => {
  const team = mergeTeam([admin, admin2, member], []);
  assert.equal(statusChangeBlockedBy(admin, admin2.id, false, team), null);
});

test('UT-USR-1-23: deactivating a member is allowed', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(statusChangeBlockedBy(admin, member.id, false, team), null);
});

test('UT-USR-1-24: reactivating is never blocked by the last-admin rule', () => {
  const statuses: RawStatus[] = [{user_id: 2, account_id: 2, is_active: false}];
  const team = mergeTeam([admin, admin2], statuses);
  assert.equal(statusChangeBlockedBy(admin, admin2.id, true, team), null);
});

test('UT-USR-1-25: someone in another account is not found', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(statusChangeBlockedBy(admin, outsider.id, false, team), 'E-USR-002');
});

// ── Full CRUD, added 2026-10-22 ──────────────────────────────────────────────

const GOOD_PASSWORD = 'correct9horse';

function draft(over: Partial<NewPersonDraft> = {}): NewPersonDraft {
  return {name: 'New Person', email: 'new@example.com', password: GOOD_PASSWORD, role: 'member', ...over};
}

// ── emailLooksRight / passwordMeetsRules ─────────────────────────────────────

test('UT-USR-1-26: an email needs an at-sign, a dot after it, and no spaces', () => {
  assert.equal(emailLooksRight('sam@example.com'), true);
  assert.equal(emailLooksRight('  sam@example.com  '), true, 'trimmed, like the server filter');
  assert.equal(emailLooksRight('sam.o-brien+tag@sub.example.co.uk'), true, 'a real address is not rejected');
  assert.equal(emailLooksRight('sam@example'), false, 'no dot after the at-sign');
  assert.equal(emailLooksRight('sam.example.com'), false, 'no at-sign');
  assert.equal(emailLooksRight('sam @example.com'), false, 'a space inside');
  assert.equal(emailLooksRight('a@b@example.com'), false, 'two at-signs');
  assert.equal(emailLooksRight(''), false);
});

test('UT-USR-1-27: a password needs 8 characters, a letter and a number', () => {
  assert.equal(passwordMeetsRules('correct9horse'), true);
  assert.equal(passwordMeetsRules('abc12345'), true, 'exactly eight is enough');
  assert.equal(passwordMeetsRules('abc1234'), false, 'seven is not');
  assert.equal(passwordMeetsRules('alllettersnodigit'), false, 'no digit');
  assert.equal(passwordMeetsRules('12345678'), false, 'no letter');
  assert.equal(passwordMeetsRules(''), false);
});

// ── createBlockedBy ──────────────────────────────────────────────────────────

test('UT-USR-1-28: an admin can add a well-formed person', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(createBlockedBy(admin, draft(), team), null);
  assert.equal(createBlockedBy(admin, draft({role: 'admin'}), team), null, 'adding an admin is allowed');
});

test('UT-USR-1-29: a member cannot add anyone', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(createBlockedBy(member, draft(), team), 'E-USR-001');
});

test('UT-USR-1-30: a blank name or email is refused, and blank reads the same as missing', () => {
  const team = mergeTeam([admin], []);
  assert.equal(createBlockedBy(admin, draft({name: ''}), team), 'E-USR-011');
  assert.equal(createBlockedBy(admin, draft({name: '   '}), team), 'E-USR-011', 'whitespace is blank');
  assert.equal(createBlockedBy(admin, draft({email: ''}), team), 'E-USR-011');
});

test('UT-USR-1-31: a malformed email is refused before the password is looked at', () => {
  const team = mergeTeam([admin], []);
  // Both fields are wrong; the code returned is the email's, matching the
  // endpoint's own check order.
  assert.equal(createBlockedBy(admin, draft({email: 'not-an-email', password: 'short'}), team), 'E-USR-014');
});

test('UT-USR-1-32: a weak password is refused', () => {
  const team = mergeTeam([admin], []);
  assert.equal(createBlockedBy(admin, draft({password: 'short1'}), team), 'E-USR-012');
  assert.equal(createBlockedBy(admin, draft({password: 'nodigitshere'}), team), 'E-USR-012');
});

test('UT-USR-1-33: an unknown role is refused before anything is sent', () => {
  const team = mergeTeam([admin], []);
  assert.equal(createBlockedBy(admin, draft({role: 'owner'}), team), 'E-USR-009');
  assert.equal(createBlockedBy(admin, draft({role: ''}), team), 'E-USR-009');
});

test('UT-USR-1-34: an email already in this account is caught before the round trip', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(createBlockedBy(admin, draft({email: 'sam@example.com'}), team), 'E-USR-008');
  assert.equal(
    createBlockedBy(admin, draft({email: '  SAM@EXAMPLE.COM '}), team),
    'E-USR-008',
    'case and padding do not hide a clash, because the server lowers and trims too',
  );
});

test('UT-USR-1-35: a clash outside this account is NOT predicted here', () => {
  // The client can only see its own account's people. `outsider` is in
  // account 7 and is not in this team, so nothing local can know the address
  // is taken — the server refuses it, and that is the correct division.
  const team = mergeTeam([admin, member], []);
  assert.equal(createBlockedBy(admin, draft({email: outsider.email}), team), null);
});

// ── profileUpdateBlockedBy ───────────────────────────────────────────────────

test('UT-USR-1-36: an admin can correct a name, an email, or both', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(profileUpdateBlockedBy(admin, member.id, {name: 'Samantha', email: ''}, team), null);
  assert.equal(profileUpdateBlockedBy(admin, member.id, {name: '', email: 'sam2@example.com'}, team), null);
  assert.equal(profileUpdateBlockedBy(admin, member.id, {name: 'S', email: 's@example.com'}, team), null);
});

test('UT-USR-1-37: an admin may correct their OWN name and email', () => {
  // Unlike role and status. E-USR-004 exists to stop the sole admin stepping
  // down or switching themselves off; fixing your own surname cannot strand
  // an account, and the endpoint has no self-check either.
  const team = mergeTeam([admin], []);
  assert.equal(profileUpdateBlockedBy(admin, admin.id, {name: 'Javier', email: ''}, team), null);
});

test('UT-USR-1-38: an update with nothing in it is refused', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(profileUpdateBlockedBy(admin, member.id, {name: '', email: ''}, team), 'E-USR-011');
  assert.equal(profileUpdateBlockedBy(admin, member.id, {name: '  ', email: '  '}, team), 'E-USR-011');
});

test('UT-USR-1-39: an empty email means leave-it, not that-is-invalid', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(profileUpdateBlockedBy(admin, member.id, {name: 'Sam', email: ''}, team), null);
  assert.equal(profileUpdateBlockedBy(admin, member.id, {name: 'Sam', email: 'nope'}, team), 'E-USR-014');
});

test('UT-USR-1-40: taking another email is refused, resaving your own is not', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(profileUpdateBlockedBy(admin, member.id, {name: '', email: admin.email}, team), 'E-USR-008');
  assert.equal(
    profileUpdateBlockedBy(admin, member.id, {name: '', email: member.email}, team),
    null,
    'an admin resaving the same address unchanged must not be refused',
  );
});

test('UT-USR-1-41: a member cannot correct anyone, and an outsider is not found', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(profileUpdateBlockedBy(member, admin.id, {name: 'X', email: ''}, team), 'E-USR-001');
  assert.equal(profileUpdateBlockedBy(admin, outsider.id, {name: 'X', email: ''}, team), 'E-USR-002');
});

// ── deleteBlockedBy ──────────────────────────────────────────────────────────

test('UT-USR-1-42: an admin can remove a member', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(deleteBlockedBy(admin, member.id, team), null);
});

test('UT-USR-1-43: a member cannot remove anyone', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(deleteBlockedBy(member, admin.id, team), 'E-USR-001');
});

test('UT-USR-1-44: you cannot remove yourself, even with another admin present', () => {
  // E-USR-015, not E-USR-004. Removal is its own action with its own remedy,
  // and one code means one thing (GUARD-1-01) — the registry test caught
  // the first version of this endpoint reusing E-USR-004 here.
  const team = mergeTeam([admin, admin2], []);
  assert.equal(deleteBlockedBy(admin, admin.id, team), 'E-USR-015');
});

test('UT-USR-1-45: removing the last active admin is refused as a lockout, not a self-change', () => {
  // The sole admin removing themselves trips both rules. The lockout reason
  // is the one worth showing, and it is checked first — the same ordering as
  // role changes and deactivations, and the same ordering as the server.
  const team = mergeTeam([admin], []);
  assert.equal(deleteBlockedBy(admin, admin.id, team), 'E-USR-003');
});

test('UT-USR-1-46: removing another admin is fine while one remains active', () => {
  const team = mergeTeam([admin, admin2], []);
  assert.equal(deleteBlockedBy(admin, admin2.id, team), null);
});

test('UT-USR-1-47: a second admin who is switched off does not make a removal safe', () => {
  // admin2 exists but cannot sign in, so removing admin would leave the
  // account with nobody able to administer it. The count that matters is
  // active admins, never rows in `user` with role 'admin'.
  const statuses: RawStatus[] = [{user_id: admin2.id, account_id: 2, is_active: false}];
  const team = mergeTeam([admin, admin2, member], statuses);
  assert.equal(deleteBlockedBy(member, admin.id, team), 'E-USR-001', 'a member still cannot');
  assert.equal(deleteBlockedBy(admin2, admin.id, team), 'E-USR-003');
});

test('UT-USR-1-48: removing an already switched-off admin cannot strand the account', () => {
  const statuses: RawStatus[] = [{user_id: admin2.id, account_id: 2, is_active: false}];
  const team = mergeTeam([admin, admin2], statuses);
  assert.equal(deleteBlockedBy(admin, admin2.id, team), null);
});

test('UT-USR-1-49: someone in another account is not found', () => {
  const team = mergeTeam([admin, member], []);
  assert.equal(deleteBlockedBy(admin, outsider.id, team), 'E-USR-002');
});

test('UT-USR-1-50: has-work is never predicted here, only the server knows', () => {
  // E-USR-013 is deliberately absent from BlockCode. The client cannot see
  // the architectures, planner agents, agent profiles and performed steps
  // that decide it, so a member with work still reads as removable here and
  // the server is what refuses. A greyed-out button the client guessed wrong
  // about would be worse than an honest refusal.
  const team = mergeTeam([admin, member], []);
  assert.equal(deleteBlockedBy(admin, member.id, team), null);
});

/* ────────────────────────────────────────────────────────────────────────────
 * USR-2 — module access.
 *
 * Same standing caveat as everything above: the server re-checks all of this
 * and is the only authority. These cases exist so the two copies can be held
 * to the same answers.
 *
 * The cases that matter most are the falsy ones. `granted` is a bool, an
 * untouched bool column reads back as `false`, and `false == null` is TRUE in
 * the Xano engine (CLAUDE.md, VAR-1) — so "is this granted?" can only ever be
 * `=== true`, and every other shape must land on "no".
 * ──────────────────────────────────────────────────────────────────────────── */

const grantRow = (user_id: number, module: string, granted: boolean): RawGrant => ({
  user_id,
  module,
  granted,
  account_id: 2,
});

// ── mergeGrants, through mergeTeam ───────────────────────────────────────────

test('UT-USR-2-01: a person with no grant rows holds nothing', () => {
  const merged = mergeTeam([member], [], []);
  assert.deepEqual(merged[0].modules, {intelligence: false, planning: false, execution: false});
});

test('UT-USR-2-02: a granted row grants exactly that module', () => {
  const merged = mergeTeam([member], [], [grantRow(3, 'execution', true)]);
  assert.deepEqual(merged[0].modules, {intelligence: false, planning: false, execution: true});
});

test('UT-USR-2-03: a revoked row reads as not granted', () => {
  const merged = mergeTeam([member], [], [grantRow(3, 'execution', false)]);
  assert.equal(merged[0].modules.execution, false);
});

// The VAR-1 rule, the one that has cost this project the most time. A null,
// missing or non-true `granted` is a NO. The safe reading of a broken
// permission row is locked, never open.
test('UT-USR-2-04: a grant row whose granted is null is not a grant', () => {
  const rows = [{user_id: 3, module: 'planning', granted: null}] as unknown as RawGrant[];
  assert.equal(mergeTeam([member], [], rows)[0].modules.planning, false);
});

test('UT-USR-2-05: a grant row with granted missing entirely is not a grant', () => {
  const rows = [{user_id: 3, module: 'planning'}] as unknown as RawGrant[];
  assert.equal(mergeTeam([member], [], rows)[0].modules.planning, false);
});

test('UT-USR-2-06: a truthy-but-not-true granted value is not a grant', () => {
  const rows = [{user_id: 3, module: 'planning', granted: 1}] as unknown as RawGrant[];
  assert.equal(mergeTeam([member], [], rows)[0].modules.planning, false);
});

test('UT-USR-2-07: two granted modules for one person both merge', () => {
  const merged = mergeTeam([member], [], [
    grantRow(3, 'planning', true),
    grantRow(3, 'execution', true),
  ]);
  assert.deepEqual(merged[0].modules, {intelligence: false, planning: true, execution: true});
});

// A row naming a module nobody has heard of is ignored, not fatal. It cannot be
// clicked and so cannot be fixed from this page either, and a blank Team page
// would hide the rows that are fine.
test('UT-USR-2-08: an unknown module key is ignored and the valid rows still merge', () => {
  const merged = mergeTeam([member], [], [
    grantRow(3, 'teleportation', true),
    grantRow(3, 'planning', true),
  ]);
  assert.deepEqual(merged[0].modules, {intelligence: false, planning: true, execution: false});
});

test('UT-USR-2-09: a grant row for somebody not in the list is ignored', () => {
  const merged = mergeTeam([member], [], [grantRow(999, 'planning', true)]);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].modules.planning, false);
});

test('UT-USR-2-10: the last row for a module wins', () => {
  const merged = mergeTeam([member], [], [
    grantRow(3, 'planning', true),
    grantRow(3, 'planning', false),
  ]);
  assert.equal(merged[0].modules.planning, false);
});

// Each person must get their OWN grants object. One shared default would mean
// granting one person a module granted it to everybody with no rows — silently,
// and only on screen, which is the worst place to find it.
test('UT-USR-2-11: two people with no grants do not share one object', () => {
  const merged = mergeTeam([member, admin2], [], []);
  merged[0].modules.planning = true;
  assert.equal(merged[1].modules.planning, false);
});

test('UT-USR-2-12: grants merge alongside statuses without disturbing them', () => {
  const merged = mergeTeam([member], [{user_id: 3, account_id: 2, is_active: false}], [
    grantRow(3, 'execution', true),
  ]);
  assert.equal(merged[0].is_active, false);
  assert.equal(merged[0].modules.execution, true);
});

// Omitting the argument entirely is how every caller written before USR-2
// behaves, and it must keep working — "no grants passed" is "nothing granted".
test('UT-USR-2-13: mergeTeam with no grants argument still returns all three keys', () => {
  const merged = mergeTeam([member], []);
  assert.deepEqual(merged[0].modules, {intelligence: false, planning: false, execution: false});
});

// ── the allow-list ───────────────────────────────────────────────────────────

test('UT-USR-2-14: there are exactly three modules, and each has a label', () => {
  assert.deepEqual([...MODULES], ['intelligence', 'planning', 'execution']);
  for (const key of MODULES) {
    assert.equal(typeof MODULE_LABELS[key], 'string');
    assert.ok(MODULE_LABELS[key].length > 0);
  }
});

test('UT-USR-2-15: isValidModule accepts the three and nothing else', () => {
  assert.ok(isValidModule('intelligence'));
  assert.ok(isValidModule('planning'));
  assert.ok(isValidModule('execution'));
  const junkValues: unknown[] = ['', ' planning', 'Planning', 'PLANNING', 'plan', null, undefined, 0, false, []];
  for (const junk of junkValues) {
    assert.equal(isValidModule(junk), false, JSON.stringify(junk) + ' was accepted');
  }
});

// ── hasModule / hasAnyModule ─────────────────────────────────────────────────

test('UT-USR-2-16: hasModule reads one module', () => {
  const viewer = {modules: {intelligence: false, planning: true, execution: false}};
  assert.equal(hasModule(viewer, 'planning'), true);
  assert.equal(hasModule(viewer, 'execution'), false);
});

test('UT-USR-2-17: hasModule on a viewer with no modules at all is false, not a crash', () => {
  assert.equal(hasModule(null, 'planning'), false);
  assert.equal(hasModule(undefined, 'planning'), false);
  assert.equal(hasModule({}, 'planning'), false);
  assert.equal(hasModule({modules: null}, 'planning'), false);
});

test('UT-USR-2-18: hasAnyModule is false for somebody with nothing', () => {
  assert.equal(hasAnyModule({modules: noModules()}), false);
  assert.equal(hasAnyModule(null), false);
});

test('UT-USR-2-19: hasAnyModule is true as soon as one module is held', () => {
  assert.equal(hasAnyModule({modules: {intelligence: false, planning: false, execution: true}}), true);
});

// ── grantChangeBlockedBy ─────────────────────────────────────────────────────

const teamOf = (...members: RawMember[]) => mergeTeam(members, [], []);

test('UT-USR-2-20: an admin may grant a module to a member', () => {
  const team = teamOf(admin, member);
  assert.equal(grantChangeBlockedBy(admin, 3, [{module: 'execution', granted: true}], team), null);
});

test('UT-USR-2-21: an admin may revoke a module from a member', () => {
  const team = teamOf(admin, member);
  assert.equal(grantChangeBlockedBy(admin, 3, [{module: 'execution', granted: false}], team), null);
});

test('UT-USR-2-22: a member cannot grant anything', () => {
  const team = teamOf(admin, member);
  assert.equal(grantChangeBlockedBy(member, 1, [{module: 'execution', granted: true}], team), 'E-USR-001');
});

test('UT-USR-2-23: granting to somebody in another account is refused as not-found', () => {
  const team = teamOf(admin, member, outsider);
  assert.equal(grantChangeBlockedBy(admin, 9, [{module: 'execution', granted: true}], team), 'E-USR-002');
});

test('UT-USR-2-24: granting to a user who is not in the list at all is refused as not-found', () => {
  const team = teamOf(admin, member);
  assert.equal(grantChangeBlockedBy(admin, 404, [{module: 'execution', granted: true}], team), 'E-USR-002');
});

test('UT-USR-2-25: an unknown module key is refused with E-USR-007', () => {
  const team = teamOf(admin, member);
  assert.equal(grantChangeBlockedBy(admin, 3, [{module: 'teleportation', granted: true}], team), 'E-USR-007');
});

test('UT-USR-2-26: one bad key in a list of good ones refuses the whole list', () => {
  const team = teamOf(admin, member);
  const changes = [
    {module: 'planning', granted: true},
    {module: 'nonsense', granted: true},
  ];
  assert.equal(grantChangeBlockedBy(admin, 3, changes, team), 'E-USR-007');
});

// Nobody edits their own access. The sole admin revoking their own Intelligent
// Layer is the lockout this prevents, and E-USR-020 is its own code because
// E-USR-004 already says something else to somebody else (GUARD-1-01).
test('UT-USR-2-27: an admin cannot change their own module access', () => {
  const team = teamOf(admin, admin2, member);
  assert.equal(grantChangeBlockedBy(admin, 1, [{module: 'intelligence', granted: false}], team), 'E-USR-020');
});

test('UT-USR-2-28: the self rule applies to granting yourself too, not only revoking', () => {
  const team = teamOf(admin, admin2);
  assert.equal(grantChangeBlockedBy(admin, 1, [{module: 'execution', granted: true}], team), 'E-USR-020');
});

// Key validation runs BEFORE the self rule, on both sides, so the same bad form
// gets the same code whoever it was aimed at.
test('UT-USR-2-29: a bad key aimed at yourself still reports the key', () => {
  const team = teamOf(admin, admin2);
  assert.equal(grantChangeBlockedBy(admin, 1, [{module: 'nonsense', granted: true}], team), 'E-USR-007');
});

test('UT-USR-2-30: an empty list of changes is a no-op, not a refusal', () => {
  const team = teamOf(admin, member);
  assert.equal(grantChangeBlockedBy(admin, 3, [], team), null);
});

test('UT-USR-2-31: a signed-out caller is refused before anything else is read', () => {
  const team = teamOf(admin, member);
  assert.equal(grantChangeBlockedBy(null, 3, [{module: 'execution', granted: true}], team), 'E-USR-001');
});

// A switched-off person can still have their access changed — the two rules are
// independent, and an admin preparing somebody's return should not have to
// reactivate them first.
test('UT-USR-2-32: a deactivated person may still be granted a module', () => {
  const team = mergeTeam([admin, member], [{user_id: 3, account_id: 2, is_active: false}], []);
  assert.equal(grantChangeBlockedBy(admin, 3, [{module: 'planning', granted: true}], team), null);
});
