import assert from 'node:assert/strict';
import test from 'node:test';
import {splitLines, type ParentLine, type MovedLine} from './splitLines';
import golden from '../fixtures/exception-split-golden.json';

const parent = golden.parentLines as ParentLine[];

for (const c of golden.cases) {
  test(`${c.id}: ${c.name}`, () => {
    const result = splitLines(parent, c.moved as MovedLine[]);
    assert.deepEqual(result, c.expected);
  });
}

test('splitLines never mutates its inputs', () => {
  const p = structuredClone(parent);
  const moved: MovedLine[] = [{item_type_id: 11, quantity: 2}];
  const m = structuredClone(moved);
  splitLines(p, moved);
  assert.deepEqual(p, parent);
  assert.deepEqual(moved, m);
});

test('UT-EXC-1-G01 (lines): junk quantities are all E-EXC-006, junk ids E-EXC-005', () => {
  // The same corpus was run through the backend twin live (FT-EXC-1-G01):
  // it JSON-encodes before matching digits, so a numeric string keeps its
  // quotes and is refused on both sides.
  const junkQuantities: unknown[] = ['2', '', 'two', null, undefined, NaN, Infinity, -0.5, 1e9, {}, []];
  for (const q of junkQuantities) {
    const r = splitLines(parent, [{item_type_id: 11, quantity: q as number}]);
    assert.equal(r.ok, false, `quantity ${String(q)} should be refused`);
    if (!r.ok) assert.equal(r.code, 'E-EXC-006', `quantity ${String(q)}`);
  }
  const junkIds: unknown[] = ['11', null, 0, -11, 11.5, 'table'];
  for (const id of junkIds) {
    const r = splitLines(parent, [{item_type_id: id as number, quantity: 1}]);
    assert.equal(r.ok, false, `id ${String(id)} should be refused`);
    if (!r.ok) assert.equal(r.code, 'E-EXC-005', `id ${String(id)}`);
  }
});
