import assert from 'node:assert/strict';
import test from 'node:test';
import {
  COPILOT_OFF_MESSAGE,
  agentUserIdToSave,
  aiAgentState,
  isCopilotAgent,
  isSwitchedOffCopilot,
  pickedPersonMember,
  splitCapacity,
  type CopilotInfo,
} from './aiAgentModel';

// COP-5 story 06 - the copilot as someone on the plan.

const on: CopilotInfo = {has_copilot: true, user_id: 26, name: 'Copilot', is_active: true};
const off: CopilotInfo = {...on, is_active: false};
const none: CopilotInfo = {has_copilot: false, user_id: 0, name: '', is_active: false};

test('a person is a person, whatever the copilot is doing', () => {
  assert.equal(aiAgentState({kind: 'person', userId: '22'}, on), 'person');
  assert.equal(aiAgentState({kind: 'person', userId: undefined}, off), 'person');
  assert.equal(aiAgentState({kind: 'person', userId: '22'}, null), 'person');
});

test('an AI column with no login behind it is an unlinked AI (it can be planned, nothing does the work)', () => {
  assert.equal(aiAgentState({kind: 'ai', userId: undefined}, on), 'ai_unlinked');
  assert.equal(aiAgentState({kind: 'ai', userId: ''}, on), 'ai_unlinked');
  assert.equal(aiAgentState({kind: 'ai', userId: undefined}, none), 'ai_unlinked');
  assert.equal(aiAgentState({kind: 'ai', userId: undefined}, null), 'ai_unlinked');
});

test('an AI column linked to the account copilot follows the copilot: on or switched off', () => {
  assert.equal(aiAgentState({kind: 'ai', userId: '26'}, on), 'copilot_on');
  assert.equal(aiAgentState({kind: 'ai', userId: '26'}, off), 'copilot_off');
  assert.equal(isCopilotAgent({kind: 'ai', userId: '26'}, on), true);
  assert.equal(isSwitchedOffCopilot({kind: 'ai', userId: '26'}, off), true);
  assert.equal(isSwitchedOffCopilot({kind: 'ai', userId: '26'}, on), false);
});

test('a column linked to the copilot login is the copilot even if someone set its kind to person', () => {
  assert.equal(aiAgentState({kind: 'person', userId: '26'}, off), 'copilot_off');
  assert.equal(aiAgentState({kind: 'person', userId: '26'}, on), 'copilot_on');
});

test('until the copilot is known, nothing is treated as switched off (never block on a guess)', () => {
  assert.equal(isSwitchedOffCopilot({kind: 'ai', userId: '26'}, null), false);
  assert.equal(isSwitchedOffCopilot({kind: 'ai', userId: '26'}, none), false);
  // user id 0 is "no copilot", never a match for an unlinked column
  assert.equal(isCopilotAgent({kind: 'ai', userId: '0'}, {...on, user_id: 0}), false);
});

test('an AI column linked to some other login is not the copilot', () => {
  assert.equal(aiAgentState({kind: 'ai', userId: '99'}, off), 'ai_unlinked');
});

test('what login is saved: a person keeps the picked login; an AI is the copilot or nothing', () => {
  assert.equal(agentUserIdToSave('person', '22', false, on), 22);
  assert.equal(agentUserIdToSave('person', '', false, on), 0);
  assert.equal(agentUserIdToSave('ai', '', true, on), 26);
  assert.equal(agentUserIdToSave('ai', '26', true, off), 26); // linking is allowed while it is off; assigning is not
  assert.equal(agentUserIdToSave('ai', '26', false, on), 0); // unticked = unlink
  assert.equal(agentUserIdToSave('ai', '22', false, on), 0); // an AI is never linked to a person login
  assert.equal(agentUserIdToSave('ai', '', true, none), 0); // no copilot to link
  assert.equal(agentUserIdToSave('ai', '', true, null), 0);
  // a person can never be saved as the copilot login
  assert.equal(agentUserIdToSave('person', '26', false, on), 0);
});

// Final Fable review R3 - `null` means "leave the login exactly as it is" (the save omits it).
test('R3: when the copilot could not be checked, saving an existing AI column leaves its login alone', () => {
  const linked = {kind: 'ai' as const, userId: '26'};
  assert.equal(agentUserIdToSave('ai', '26', false, null, linked), null);
  assert.equal(agentUserIdToSave('ai', '26', true, null, linked), null);
  // the account reports no copilot, yet the column has a login: not ours to clear on a capacity edit
  assert.equal(agentUserIdToSave('ai', '26', false, none, linked), null);
  // an unlinked AI column stays unlinked either way
  assert.equal(agentUserIdToSave('ai', '', false, null, {kind: 'ai', userId: ''}), null);
});

test('R3: a known copilot still links and unlinks on purpose', () => {
  const linked = {kind: 'ai' as const, userId: '26'};
  assert.equal(agentUserIdToSave('ai', '26', true, on, linked), 26);
  assert.equal(agentUserIdToSave('ai', '26', false, on, linked), 0); // unticked = unlink
  assert.equal(agentUserIdToSave('ai', '', true, on, {kind: 'ai', userId: ''}), 26);
});

test('R3: turning a person column into an AI column never keeps the person login', () => {
  const person = {kind: 'person' as const, userId: '22'};
  assert.equal(agentUserIdToSave('ai', '22', false, null, person), 0);
  assert.equal(agentUserIdToSave('ai', '22', false, on, person), 0);
  assert.equal(agentUserIdToSave('ai', '22', true, on, person), 26);
});

test('R12: an AI column linked to some other login is left alone unless the copilot is ticked', () => {
  const other = {kind: 'ai' as const, userId: '99'};
  assert.equal(agentUserIdToSave('ai', '99', false, on, other), null);
  assert.equal(agentUserIdToSave('ai', '99', true, on, other), 26);
});

test('R4: a person column already linked to the copilot login keeps it on an ordinary edit', () => {
  const legacy = {kind: 'person' as const, userId: '26'};
  assert.equal(agentUserIdToSave('person', '26', false, on, legacy), null);
  assert.equal(agentUserIdToSave('person', '26', false, off, legacy), null);
  // picking a real person instead still works
  assert.equal(agentUserIdToSave('person', '22', false, on, legacy), 22);
  // a NEW person, or one linked to somebody else, can still never be set to the copilot login
  assert.equal(agentUserIdToSave('person', '26', false, on, {kind: 'person', userId: '22'}), 0);
  assert.equal(agentUserIdToSave('person', '26', false, on, null), 0);
});

test('R4: the copilot login never renames a person column', () => {
  const members = [{id: 22, name: 'Ana'}, {id: 26, name: 'Copilot'}];
  assert.equal(pickedPersonMember(members, '22', on)?.name, 'Ana');
  assert.equal(pickedPersonMember(members, '26', on), undefined);
  assert.equal(pickedPersonMember(members, '', on), undefined);
  assert.equal(pickedPersonMember(members, '26', null)?.name, 'Copilot'); // unknown copilot: cannot tell
});

test('capacity: people and AI are added up apart', () => {
  const rows = [
    {agent: {kind: 'person' as const}, capacityHours: 8, plannedHours: 6},
    {agent: {kind: 'person' as const}, capacityHours: 8, plannedHours: 10},
    {agent: {kind: 'ai' as const}, capacityHours: 24, plannedHours: 3},
  ];
  const s = splitCapacity(rows);
  assert.deepEqual(s.people, {capacityHours: 16, plannedHours: 16, openHours: 0, count: 2});
  assert.deepEqual(s.ai, {capacityHours: 24, plannedHours: 3, openHours: 21, count: 1});
});

test('capacity: no AI columns gives an empty AI part, and rounding stays at one decimal', () => {
  const s = splitCapacity([{agent: {kind: 'person' as const}, capacityHours: 7.5, plannedHours: 0.1 + 0.2}]);
  assert.deepEqual(s.ai, {capacityHours: 0, plannedHours: 0, openHours: 0, count: 0});
  assert.deepEqual(s.people, {capacityHours: 7.5, plannedHours: 0.3, openHours: 7.2, count: 1});
});

test('the switched-off message says what happened and what to do', () => {
  assert.match(COPILOT_OFF_MESSAGE, /switched off/i);
  assert.match(COPILOT_OFF_MESSAGE, /Manage users/);
});
