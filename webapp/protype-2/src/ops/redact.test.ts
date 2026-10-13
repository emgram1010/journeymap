import assert from 'node:assert/strict';
import test from 'node:test';
import {redact} from './redact';

test('UT-OBS-1-05: removes a value whose key name looks sensitive', () => {
  const result = redact({email: 'jane@example.com', password: 'secret123', token: 'abc.def.ghi'}) as Record<string, unknown>;
  assert.equal(result.email, '[redacted]');
  assert.equal(result.password, '[redacted]');
  assert.equal(result.token, '[redacted]');
});

test('keeps ids and short id-like keys/values', () => {
  const result = redact({work_item_id: 42, stage_key: 's3', is_active: true}) as Record<string, unknown>;
  assert.equal(result.work_item_id, 42);
  assert.equal(result.stage_key, 's3');
  assert.equal(result.is_active, true);
});

test('redacts long free text and notes even without a sensitive key name', () => {
  const result = redact({notes: 'The customer said their address was wrong and called twice about it.'}) as Record<string, unknown>;
  assert.equal(result.notes, '[redacted]');
});

test('redacts nested objects and arrays, keeping their keys', () => {
  const result = redact({
    attributes: {item_type: 'sofa', customer_email: 'x@y.com'},
    history: [{note: 'long free text goes here'}, {id: 7}],
  }) as any;
  assert.equal(result.attributes.item_type, 'sofa');
  assert.equal(result.attributes.customer_email, '[redacted]');
  assert.equal(result.history[0].note, '[redacted]');
  assert.equal(result.history[1].id, 7);
});

test('passes through null, undefined, and primitives that look like ids', () => {
  assert.equal(redact(null), null);
  assert.equal(redact(undefined), undefined);
  assert.equal(redact(5), 5);
  assert.equal(redact('ok'), 'ok');
  assert.equal(redact(true), true);
});

test('redacts a bare long string value', () => {
  assert.equal(redact('this looks like a sentence, not an id'), '[redacted]');
});

test('does not mutate the input', () => {
  const input = {password: 'secret', id: 1};
  const frozen = Object.freeze({...input});
  assert.doesNotThrow(() => redact(frozen));
  assert.equal(frozen.password, 'secret');
});
