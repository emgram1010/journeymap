import assert from 'node:assert/strict';
import test from 'node:test';
import {refusalMeaning, refusalWho, toolCallsSummary} from './toolCallsModel';

test('COP-1-04 Health: the summary says how many calls, from where, allowed and refused', () => {
  assert.equal(toolCallsSummary({total: 0, allowed: 0, refused: 0, outside: 0, since_hours: 24}), 'No AI tool calls in the last 24 hours.');
  assert.equal(
    toolCallsSummary({total: 166, allowed: 139, refused: 27, outside: 2, since_hours: 24}),
    '166 AI tool calls in the last 24 hours, 2 from an outside assistant: 139 allowed, 27 refused.',
  );
});

test('COP-1-04 Health: a refusal is explained from the catalog, never left as a bare code when known', () => {
  assert.equal(refusalMeaning({code: 'E-SEC-020'}), 'Sign in to use these tools.');
  assert.equal(refusalMeaning({code: 'E-NOT-999'}), 'E-NOT-999');
  assert.match(refusalMeaning({code: ''}), /no reason code/);
  assert.equal(refusalWho({user_id: 0, account_id: 0, context: 'outside'}), 'Unknown caller, outside assistant');
  assert.equal(refusalWho({user_id: 26, account_id: 13, context: 'inapp'}), 'User 26, account 13, inside Emgram');
});
