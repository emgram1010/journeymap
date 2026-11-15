import assert from 'node:assert/strict';
import test from 'node:test';
import {
  messageText,
  screenContextSummary,
  pickConversation,
  readLastBusiness,
  writeLastBusiness,
  type StorageLike,
} from './copilotChatModel';

test('messageText joins text parts and ignores other types', () => {
  assert.equal(messageText([{type: 'text', text: 'Hello'}, {type: 'tool_use', name: 'x'}, {type: 'text', text: 'there'}]), 'Hello\nthere');
  assert.equal(messageText('plain'), 'plain');
  assert.equal(messageText(null), '');
  assert.equal(messageText([{type: 'text'}]), '');
});

test('screenContextSummary: planner job, maps, approvals, unknown', () => {
  assert.equal(screenContextSummary('/planner', '?job=412'), 'Planner, job 412');
  assert.equal(screenContextSummary('/planner', ''), 'Planner');
  assert.equal(screenContextSummary('/maps/77', ''), 'Journey map 77');
  assert.equal(screenContextSummary('/architectures/5', ''), 'Business 5');
  assert.equal(screenContextSummary('/architectures', ''), 'Businesses');
  assert.equal(screenContextSummary('/approvals', ''), 'Approvals');
  assert.equal(screenContextSummary('/perform', ''), 'Perform');
  assert.equal(screenContextSummary('/reports/plan-vs-action', ''), 'Reports, plan vs action');
  assert.equal(screenContextSummary('/something/odd', ''), '/something/odd');
});

test('pickConversation: most recent for the business, or none', () => {
  assert.equal(pickConversation([]), null);
  assert.equal(pickConversation(undefined), null);
  assert.equal(
    pickConversation([
      {id: 1, last_message_at: 100, created_at: 50},
      {id: 2, last_message_at: 300, created_at: 60},
      {id: 3, last_message_at: null, created_at: 200},
    ]),
    2,
  );
});

test('last business is remembered per user and survives broken storage', () => {
  const m = new Map<string, string>();
  const st: StorageLike = {getItem: (k) => m.get(k) ?? null, setItem: (k, v) => void m.set(k, v)};
  writeLastBusiness(st, 9, 42);
  assert.equal(readLastBusiness(st, 9), 42);
  assert.equal(readLastBusiness(st, 10), null);
  const bad: StorageLike = {
    getItem: () => {
      throw new Error('no');
    },
    setItem: () => {
      throw new Error('no');
    },
  };
  assert.equal(readLastBusiness(bad, 9), null);
  writeLastBusiness(bad, 9, 1);
  assert.equal(readLastBusiness(undefined, 9), null);
});
