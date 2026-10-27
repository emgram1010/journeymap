// ITEM-1 — Unit tests for the client-side mirror of
// functions/items/validate_items_cell.xs. See that function's own
// header for why a parenthesized |has was needed server-side; this
// file pins the SAME rules (minutes range, 2-decimal limit, dedupe,
// per_order drop) so a future change to one side that breaks parity
// with the other fails a test instead of shipping silently.

import assert from 'node:assert/strict';
import test from 'node:test';
import {validateItemsCell, itemsCellDraftChanged} from './itemsCellValidation';

const ALLOWED_ITEMS = new Set(['chair-resin', 'table-6ft']);
const ACTIVE_METHODS = new Set(['hard-goods', 'textiles']);

test('UT-ITEM-1-01a: bad scales_with -> E-ITM-003', () => {
  const result = validateItemsCell({
    scalesWith: 'bogus',
    lines: [],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, false);
  assert.equal(result.code, 'E-ITM-003');
});

test('UT-ITEM-1-01b: item not in this map\'s chosen set -> E-ITM-002', () => {
  const result = validateItemsCell({
    scalesWith: 'per_unit',
    lines: [{item_key: 'not-chosen', method_key: 'hard-goods', minutes_per_unit: 2}],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, false);
  assert.equal(result.code, 'E-ITM-002');
});

test('UT-ITEM-1-01c: method not active -> E-ITM-005', () => {
  const result = validateItemsCell({
    scalesWith: 'per_unit',
    lines: [{item_key: 'chair-resin', method_key: 'not-a-method', minutes_per_unit: 2}],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, false);
  assert.equal(result.code, 'E-ITM-005');
});

test('UT-ITEM-1-01d: minutes negative -> E-ITM-004', () => {
  const result = validateItemsCell({
    scalesWith: 'per_unit',
    lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: -1}],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, false);
  assert.equal(result.code, 'E-ITM-004');
});

test('UT-ITEM-1-01e: minutes over 1440 -> E-ITM-004', () => {
  const result = validateItemsCell({
    scalesWith: 'per_unit',
    lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 1441}],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, false);
  assert.equal(result.code, 'E-ITM-004');
});

test('UT-ITEM-1-01f: minutes with 3 decimals -> E-ITM-004', () => {
  const result = validateItemsCell({
    scalesWith: 'per_unit',
    lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 2.567}],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, false);
  assert.equal(result.code, 'E-ITM-004');
});

test('UT-ITEM-1-01g: minutes with exactly 2 decimals is fine', () => {
  const result = validateItemsCell({
    scalesWith: 'per_unit',
    lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 2.5}],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, true);
  assert.equal(result.normalizedLines[0].minutes_per_unit, 2.5);
});

test('UT-ITEM-1-01h: empty minutes is allowed (D-3) and stored as null', () => {
  const result = validateItemsCell({
    scalesWith: 'per_unit',
    lines: [{item_key: 'chair-resin', method_key: 'hard-goods'}],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, true);
  assert.equal(result.normalizedLines[0].minutes_per_unit, null);
});

test('UT-ITEM-1-02: duplicate (item, method) in one cell -> E-ITM-006', () => {
  const result = validateItemsCell({
    scalesWith: 'per_unit',
    lines: [
      {item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 1},
      {item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 2},
    ],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, false);
  assert.equal(result.code, 'E-ITM-006');
});

test('UT-ITEM-1-03: per_order with lines -> lines dropped, warn flag set, not an error', () => {
  const result = validateItemsCell({
    scalesWith: 'per_order',
    lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 2}],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.normalizedLines, []);
  assert.equal(result.droppedLinesWarn, true);
});

test('UT-ITEM-1-03b: per_order with no lines is the plain default, no warning', () => {
  const result = validateItemsCell({
    scalesWith: 'per_order',
    lines: [],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, true);
  assert.equal(result.droppedLinesWarn, false);
});

test('UT-ITEM-1-04: a valid per_unit cell with two distinct lines passes and normalizes both', () => {
  const result = validateItemsCell({
    scalesWith: 'per_flagged_unit',
    lines: [
      {item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 2},
      {item_key: 'table-6ft', method_key: 'textiles', minutes_per_unit: 4.25},
    ],
    allowedItemKeys: ALLOWED_ITEMS,
    activeMethodKeys: ACTIVE_METHODS,
  });
  assert.equal(result.ok, true);
  assert.equal(result.normalizedLines.length, 2);
});

// ── Junk corpus — every entry must be rejected (or, for scales_with
// values that ARE legitimate, accepted), matching the backend's own
// validator case for case. ──
const VALID_SCALES_WITH = new Set(['per_order', 'per_unit', 'per_flagged_unit']);
const SCALES_WITH_CASES = ['', 'PER_ORDER', 'per order', 'peR_unit', 'unit', null, undefined, 123, 'PER_FLAGGED_UNIT'];
test('UT-ITEM-1-G01: scales_with is accepted case-insensitively for the real 3, rejected otherwise', () => {
  for (const junk of SCALES_WITH_CASES) {
    const result = validateItemsCell({
      scalesWith: junk as string,
      lines: [],
      allowedItemKeys: ALLOWED_ITEMS,
      activeMethodKeys: ACTIVE_METHODS,
    });
    const normalizes = typeof junk === 'string' && VALID_SCALES_WITH.has(junk.trim().toLowerCase());
    if (normalizes) {
      assert.equal(result.ok, true, `expected "${junk}" to normalize to a valid value`);
    } else {
      assert.equal(result.ok, false, `expected "${String(junk)}" to be rejected`);
      assert.equal(result.code, 'E-ITM-003');
    }
  }
});

const MINUTES_JUNK: Array<number | null | undefined> = [-0.01, 1440.01, 99999, 0.001, 3.333, NaN];
test('UT-ITEM-1-G02: junk minutes values are all rejected', () => {
  for (const junk of MINUTES_JUNK) {
    const result = validateItemsCell({
      scalesWith: 'per_unit',
      lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: junk}],
      allowedItemKeys: ALLOWED_ITEMS,
      activeMethodKeys: ACTIVE_METHODS,
    });
    assert.equal(result.ok, false, `expected minutes_per_unit=${junk} to be rejected`);
    assert.equal(result.code, 'E-ITM-004');
  }
});

const MINUTES_OK: Array<number | null | undefined> = [0, 1440, 2.5, 2, 2.1, null, undefined];
test('UT-ITEM-1-G03: valid minutes boundary values are all accepted', () => {
  for (const ok of MINUTES_OK) {
    const result = validateItemsCell({
      scalesWith: 'per_unit',
      lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: ok}],
      allowedItemKeys: ALLOWED_ITEMS,
      activeMethodKeys: ACTIVE_METHODS,
    });
    assert.equal(result.ok, true, `expected minutes_per_unit=${ok} to be accepted`);
  }
});

// ── ITEM-1 bugfix (2026-10-25): "Save & Close" used to throw the Items
// draft away. It now commits the draft first, which needs this dirty
// test so an untouched cell still closes without firing a request.

test('UT-ITEM-1-08: an untouched Items draft is not dirty', () => {
  const saved = {scalesWith: 'per_unit', lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 5}]};
  assert.equal(itemsCellDraftChanged(saved, {scalesWith: 'per_unit', lines: [...saved.lines]}), false);
});

test('UT-ITEM-1-09: a changed minutes value makes the draft dirty', () => {
  const saved = {scalesWith: 'per_unit', lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 5}]};
  const draft = {scalesWith: 'per_unit', lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 9}]};
  assert.equal(itemsCellDraftChanged(saved, draft), true);
});

test('UT-ITEM-1-10: a changed scaling choice makes the draft dirty', () => {
  const saved = {scalesWith: 'per_order', lines: []};
  const draft = {scalesWith: 'per_unit', lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: null}]};
  assert.equal(itemsCellDraftChanged(saved, draft), true);
});

test('UT-ITEM-1-11: an added, removed, reordered or re-methoded line makes the draft dirty', () => {
  const a = {item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: 2};
  const b = {item_key: 'table-6ft', method_key: 'hard-goods', minutes_per_unit: 3};
  const saved = {scalesWith: 'per_unit', lines: [a, b]};
  assert.equal(itemsCellDraftChanged(saved, {scalesWith: 'per_unit', lines: [a]}), true, 'removed');
  assert.equal(itemsCellDraftChanged(saved, {scalesWith: 'per_unit', lines: [a, b, a]}), true, 'added');
  assert.equal(itemsCellDraftChanged(saved, {scalesWith: 'per_unit', lines: [b, a]}), true, 'reordered');
  assert.equal(
    itemsCellDraftChanged(saved, {scalesWith: 'per_unit', lines: [{...a, method_key: 'textiles'}, b]}),
    true,
    'method changed',
  );
});

// An unpriced line arrives from the server with the key missing, while the
// editor writes an explicit null for an empty box. Those are the same state,
// so a cell opened and closed without typing must not fire a save.
test('UT-ITEM-1-12: a missing minutes key equals an explicit null', () => {
  const saved = {scalesWith: 'per_unit', lines: [{item_key: 'chair-resin', method_key: 'hard-goods'}]};
  const draft = {scalesWith: 'per_unit', lines: [{item_key: 'chair-resin', method_key: 'hard-goods', minutes_per_unit: null}]};
  assert.equal(itemsCellDraftChanged(saved, draft), false);
});
