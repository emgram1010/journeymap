import assert from 'node:assert/strict';
import test from 'node:test';
import {mergeTeam, roleLabel, type RawMember} from './teamModel';

// SAFE-1 story 03 / D-10 — the account owner shows as "Owner" on the Team page.
// The owner lives in the `account_owner` side table (GET account_owner), not in user.role,
// so it is merged in like user_status and user_module_access.

const jav: RawMember = {id: 2, name: 'Jav', email: 'jav@example.com', account_id: 2, role: 'admin'};
const ada: RawMember = {id: 5, name: 'Ada', email: 'ada@example.com', account_id: 2, role: 'admin'};
const sam: RawMember = {id: 3, name: 'Sam', email: 'sam@example.com', account_id: 2, role: 'member'};

test('UT-SAFE-03-OWN-1: the owner is marked and labelled Owner', () => {
  const team = mergeTeam([jav, ada, sam], [], [], 2);
  assert.equal(team[0].is_owner, true);
  assert.equal(roleLabel(team[0]), 'Owner');
});

test('UT-SAFE-03-OWN-2: other admins and members keep their labels', () => {
  const team = mergeTeam([jav, ada, sam], [], [], 2);
  assert.equal(team[1].is_owner, false);
  assert.equal(roleLabel(team[1]), 'Admin');
  assert.equal(roleLabel(team[2]), 'Member');
});

test('UT-SAFE-03-OWN-3: no owner known (0 or left out) means nobody is the owner', () => {
  for (const team of [mergeTeam([jav, sam], [], [], 0), mergeTeam([jav, sam], [])]) {
    assert.equal(team.some((m) => m.is_owner), false);
    assert.equal(roleLabel(team[0]), 'Admin');
  }
});

test('UT-SAFE-03-OWN-4: the owner keeps role admin underneath, so admin counts are unchanged', () => {
  const team = mergeTeam([jav], [], [], 2);
  assert.equal(team[0].role, 'admin');
});
