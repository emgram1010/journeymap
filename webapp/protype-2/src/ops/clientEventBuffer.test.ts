import assert from 'node:assert/strict';
import test from 'node:test';
import {ClientEventGate, OfflineEventBuffer, createMemoryStorage} from './clientEventBuffer';

// ── ClientEventGate: dedup + rate cap (UT-OBS-1-07) ──────────────────────

test('UT-OBS-1-07: the first send for a key is always allowed', () => {
  const gate = new ClientEventGate();
  assert.equal(gate.shouldSend('k1', 1000), true);
});

test('UT-OBS-1-07: an identical key is suppressed within the dedup window', () => {
  const gate = new ClientEventGate({dedupMs: 5000});
  assert.equal(gate.shouldSend('k1', 1000), true);
  assert.equal(gate.shouldSend('k1', 2000), false); // 1s later, inside the 5s window
});

test('UT-OBS-1-07: the same key is allowed again after the dedup window passes', () => {
  const gate = new ClientEventGate({dedupMs: 5000});
  assert.equal(gate.shouldSend('k1', 1000), true);
  assert.equal(gate.shouldSend('k1', 7000), true); // 6s later, past the 5s window
});

test('UT-OBS-1-07: a flood collapses to the rate cap, regardless of key', () => {
  const gate = new ClientEventGate({maxPerWindow: 3, windowMs: 60_000, dedupMs: 0});
  const results = [
    gate.shouldSend('a', 0),
    gate.shouldSend('b', 1),
    gate.shouldSend('c', 2),
    gate.shouldSend('d', 3), // 4th distinct key within the same window — capped
    gate.shouldSend('e', 4),
  ];
  assert.deepEqual(results, [true, true, true, false, false]);
});

test('UT-OBS-1-07: the rate cap frees up as the window slides', () => {
  const gate = new ClientEventGate({maxPerWindow: 2, windowMs: 1000, dedupMs: 0});
  assert.equal(gate.shouldSend('a', 0), true);
  assert.equal(gate.shouldSend('b', 100), true);
  assert.equal(gate.shouldSend('c', 200), false); // capped
  assert.equal(gate.shouldSend('d', 1001), true); // the first event (t=0) has aged out
});

// ── OfflineEventBuffer (UT-OBS-1-09) ─────────────────────────────────────

test('UT-OBS-1-09: add then drain returns the buffered event', () => {
  const buffer = new OfflineEventBuffer(createMemoryStorage());
  buffer.add({feature: 'APP-1', step: 'load_today', outcome: 'failure', errorCode: 'E-APP-005'});
  const drained = buffer.drain();
  assert.equal(drained.length, 1);
  assert.equal(drained[0].feature, 'APP-1');
});

test('UT-OBS-1-09: drain clears the buffer', () => {
  const buffer = new OfflineEventBuffer(createMemoryStorage());
  buffer.add({feature: 'APP-1', step: 'load_today', outcome: 'failure'});
  buffer.drain();
  assert.deepEqual(buffer.peek(), []);
});

test('UT-OBS-1-09: caps at 50 entries, dropping the oldest', () => {
  const buffer = new OfflineEventBuffer(createMemoryStorage(), {maxEntries: 50});
  for (let i = 0; i < 55; i++) {
    buffer.add({feature: 'APP-1', step: `step-${i}`, outcome: 'failure'}, 1000 + i);
  }
  const all = buffer.peek(2000);
  assert.equal(all.length, 50);
  assert.equal(all[0].step, 'step-5'); // the first 5 were dropped
  assert.equal(all[49].step, 'step-54');
});

test('UT-OBS-1-09: entries older than 7 days are dropped on read', () => {
  const buffer = new OfflineEventBuffer(createMemoryStorage(), {maxAgeMs: 7 * 24 * 60 * 60 * 1000});
  const eightDaysMs = 8 * 24 * 60 * 60 * 1000;
  buffer.add({feature: 'APP-1', step: 'old', outcome: 'failure'}, 0);
  buffer.add({feature: 'APP-1', step: 'recent', outcome: 'failure'}, eightDaysMs - 1000);
  const remaining = buffer.peek(eightDaysMs);
  assert.equal(remaining.length, 1);
  assert.equal(remaining[0].step, 'recent');
});

test('UT-OBS-1-09: never holds sensitive metadata values — only ids/field names survive', () => {
  const buffer = new OfflineEventBuffer(createMemoryStorage());
  buffer.add({
    feature: 'APP-1',
    step: 'load_today',
    outcome: 'failure',
    metadata: {email: 'jane@example.com', work_item_id: 9},
  });
  const [entry] = buffer.drain();
  const metadata = entry.metadata as Record<string, unknown>;
  assert.equal(metadata.email, '[redacted]');
  assert.equal(metadata.work_item_id, 9);
});

test('UT-OBS-1-09: survives corrupted storage content without throwing', () => {
  const storage = createMemoryStorage();
  storage.setItem('ops_offline_event_buffer', 'not valid json{{{');
  const buffer = new OfflineEventBuffer(storage);
  assert.doesNotThrow(() => buffer.add({feature: 'APP-1', step: 'x', outcome: 'failure'}));
  assert.equal(buffer.peek().length, 1);
});
