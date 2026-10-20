import assert from 'node:assert/strict';
import test from 'node:test';
import {anchorForSeam, moveOneStep, seamTitle} from './matrixOrder';

// ── moveOneStep: the arrows ────────────────────────────────────────────────

test('UT-ORD-1-05a: moving right swaps with the next item', () => {
  assert.deepEqual(moveOneStep([11, 12, 13], 11, 1), [12, 11, 13]);
});

test('UT-ORD-1-05b: moving left swaps with the previous item', () => {
  assert.deepEqual(moveOneStep([11, 12, 13], 13, -1), [11, 13, 12]);
});

test('UT-ORD-1-05c: the ends are honest — no move past the first or last', () => {
  assert.equal(moveOneStep([11, 12, 13], 11, -1), null);
  assert.equal(moveOneStep([11, 12, 13], 13, 1), null);
});

test('UT-ORD-1-05d: an unknown id moves nothing', () => {
  assert.equal(moveOneStep([11, 12, 13], 99, 1), null);
});

test('UT-ORD-1-05e: a move is always a permutation — same ids, each once', () => {
  const before = [5, 9, 2, 7];
  const after = moveOneStep(before, 9, 1);
  assert.ok(after);
  assert.deepEqual([...after].sort(), [...before].sort());
  assert.equal(new Set(after).size, before.length);
});

test('UT-ORD-1-05f: the input array is not mutated', () => {
  const before = [1, 2, 3];
  moveOneStep(before, 1, 1);
  assert.deepEqual(before, [1, 2, 3]);
});

// ── anchorForSeam: the + on the line between two items ─────────────────────

test('UT-ORD-1-05g: the leading seam inserts first (anchor 0)', () => {
  assert.equal(anchorForSeam([11, 12, 13], 0), 0);
});

test('UT-ORD-1-05h: an inner seam inserts after the item to its left', () => {
  assert.equal(anchorForSeam([11, 12, 13], 1), 11);
  assert.equal(anchorForSeam([11, 12, 13], 2), 12);
});

test('UT-ORD-1-05i: the trailing seam is a plain append (no anchor) — same as the old add button', () => {
  assert.equal(anchorForSeam([11, 12, 13], 3), undefined);
});

test('UT-ORD-1-05j: N items give N+1 distinct seams', () => {
  const ids = [11, 12, 13];
  const anchors = [0, 1, 2, 3].map((seam) => anchorForSeam(ids, seam));
  assert.equal(new Set(anchors).size, ids.length + 1);
});

test('UT-ORD-1-05k: an empty list has one seam, which inserts first', () => {
  assert.equal(anchorForSeam([], 0), 0);
});

test('UT-ORD-1-05l: seam titles say where the new item will land', () => {
  assert.equal(seamTitle('column', 0, 3), 'Insert a column at the start');
  assert.equal(seamTitle('column', 3, 3), 'Insert a column at the end');
  assert.equal(seamTitle('row', 1, 3), 'Insert a row here');
});
