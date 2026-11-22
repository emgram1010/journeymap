import assert from 'node:assert/strict';
import test from 'node:test';
import {
  actionLabel,
  actionsSummary,
  candidateLogins,
  managerChoices,
  memberStatus,
  planNames,
  profileProblem,
  todayLine,
  tokenState,
  toMs,
  type AimPerson,
  type AiProfileDraft,
} from './aimModel';

// AIM-1 — the AI-member rules the screen can know before the round trip.
// The server (functions/aim/*) is the authority and checks every one again.

const person = (id: number, over: Partial<AimPerson> = {}): AimPerson => ({
  id,
  name: `Person ${id}`,
  email: `p${id}@example.com`,
  role: 'member',
  is_active: true,
  is_owner: false,
  ...over,
});

const team: AimPerson[] = [
  person(1, {role: 'admin', is_owner: true}),
  person(2, {role: 'admin'}),
  person(3),
  person(4),
  person(5, {is_active: false}),
  person(6),
];

const goodDraft: AiProfileDraft = {
  user_id: 4,
  manager_user_id: 2,
  purpose: 'Drafts next week’s plan',
  allowed_actions: ['read', 'draft_plan'],
  plan_ids: [],
};

// A realistic time base, never 0 (0 means "no time" in this data).
const NOW = 1_800_000_000_000;
const HOUR = 3_600_000;

test('UT-AIM-01: the four actions read in plain words', () => {
  assert.equal(actionLabel('read'), 'Read maps and plans');
  assert.equal(actionLabel('draft_map'), 'Edit draft maps');
  assert.equal(actionLabel('draft_plan'), 'Draft plans');
  assert.equal(actionLabel('own_work'), 'Record its own work');
  assert.equal(actionLabel('something_new'), 'something_new');
  assert.equal(actionsSummary(['read', 'own_work']), 'Read maps and plans, Record its own work');
  assert.equal(actionsSummary(null), 'Nothing yet');
  assert.equal(actionsSummary([]), 'Nothing yet');
});

test('UT-AIM-02: a complete draft has no problem', () => {
  assert.equal(profileProblem(goodDraft), null);
});

test('UT-AIM-03: a draft with no manager is refused first', () => {
  assert.match(profileProblem({...goodDraft, manager_user_id: 0, purpose: '', allowed_actions: []}) ?? '', /manager/);
});

test('UT-AIM-04: the purpose must be there, short, and free of < and >', () => {
  assert.match(profileProblem({...goodDraft, purpose: '   '}) ?? '', /what this AI member is for/);
  assert.equal(profileProblem({...goodDraft, purpose: 'x'.repeat(200)}), null);
  assert.match(profileProblem({...goodDraft, purpose: 'x'.repeat(201)}) ?? '', /200 characters/);
  assert.match(profileProblem({...goodDraft, purpose: 'plans <b>fast</b>'}) ?? '', /< or >/);
  assert.match(profileProblem({...goodDraft, purpose: 'a > b'}) ?? '', /< or >/);
});

test('UT-AIM-05: at least one action must be ticked', () => {
  assert.match(profileProblem({...goodDraft, allowed_actions: []}) ?? '', /at least one/);
});

test('UT-AIM-06: an AI member cannot manage itself', () => {
  assert.match(profileProblem({...goodDraft, manager_user_id: 4}) ?? '', /its own manager/);
});

test('UT-AIM-07: candidates are ordinary members, not the owner, not you, not already AI', () => {
  assert.deepEqual(
    candidateLogins(team, [4], 3).map((m) => m.id),
    [5, 6],
  );
  // Admins and the owner are never offered, whoever is looking.
  assert.deepEqual(
    candidateLogins(team, [], 2).map((m) => m.id),
    [3, 4, 5, 6],
  );
  assert.deepEqual(candidateLogins(null, null, 2), []);
});

test('UT-AIM-08: managers are switched-on people who are not AI and not the target', () => {
  assert.deepEqual(
    managerChoices(team, [4], 3).map((m) => m.id),
    [1, 2, 6],
  );
  assert.deepEqual(managerChoices(undefined, undefined, 3), []);
});

test('UT-AIM-09: a token is live, revoked or expired, and revoked wins', () => {
  assert.equal(tokenState({revoked: false, expires_at: NOW + HOUR}, NOW), 'live');
  assert.equal(tokenState({revoked: false, expires_at: NOW - HOUR}, NOW), 'expired');
  assert.equal(tokenState({revoked: false, expires_at: NOW}, NOW), 'expired');
  assert.equal(tokenState({revoked: true, expires_at: NOW + HOUR}, NOW), 'revoked');
  assert.equal(tokenState({revoked: true, expires_at: NOW - HOUR}, NOW), 'revoked');
  // No expiry time stored (null, 0 or "") means it does not expire by the clock.
  assert.equal(tokenState({revoked: false, expires_at: null}, NOW), 'live');
  assert.equal(tokenState({revoked: false, expires_at: 0}, NOW), 'live');
  assert.equal(tokenState({revoked: false, expires_at: ''}, NOW), 'live');
  // A time sent as text is read the same way.
  assert.equal(tokenState({revoked: false, expires_at: String(NOW - HOUR)}, NOW), 'expired');
  assert.equal(tokenState({revoked: false, expires_at: new Date(NOW - HOUR).toISOString()}, NOW), 'expired');
});

test('UT-AIM-10: times are read as milliseconds, and "none" stays none', () => {
  assert.equal(toMs(NOW), NOW);
  assert.equal(toMs(String(NOW)), NOW);
  assert.equal(toMs(new Date(NOW).toISOString()), NOW);
  assert.equal(toMs(null), null);
  assert.equal(toMs(0), null);
  assert.equal(toMs(''), null);
  assert.equal(toMs('not a date'), null);
});

test('UT-AIM-11: status, most important reason first', () => {
  const m = {is_paused: false, needs_manager: false};
  assert.equal(memberStatus(m, false), 'Working');
  assert.equal(memberStatus({...m, needs_manager: true}, false), 'Needs a manager');
  assert.equal(memberStatus({is_paused: true, needs_manager: true}, false), 'Switched off');
  assert.equal(memberStatus({is_paused: true, needs_manager: true}, true), 'Paused for everyone');
  assert.equal(memberStatus(m, true), 'Paused for everyone');
});

test('UT-AIM-12: plan names and the "today" line survive missing data', () => {
  const plans = [
    {id: 7, name: 'Week 12'},
    {id: 9, name: 'Week 13'},
  ];
  assert.deepEqual(planNames([9, 7, 44], plans), ['Week 13', 'Week 12', 'Plan 44']);
  assert.deepEqual(planNames(null, plans), []);
  assert.deepEqual(planNames([7], null), ['Plan 7']);
  assert.equal(
    todayLine({calls_today: 3, writes_today: 1, refused_last_7_days: 0}),
    '3 calls, 1 change today · 0 refused this week',
  );
  assert.equal(
    todayLine({calls_today: 1, writes_today: 2, refused_last_7_days: 5}),
    '1 call, 2 changes today · 5 refused this week',
  );
});
