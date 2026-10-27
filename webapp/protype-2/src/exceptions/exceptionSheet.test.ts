import assert from 'node:assert/strict';
import test from 'node:test';
import {
  NOTE_MAX,
  buildExceptionRequest,
  clampCount,
  emptySheet,
  isAlreadySent,
  optionsForStep,
  sentToast,
  validateSheet,
  type SheetLine,
  type SendOption,
} from './exceptionSheet';

const lines: SheetLine[] = [
  {item_type_id: 11, label: 'tables', quantity: 3},
  {item_type_id: 12, label: 'chairs', quantity: 100},
];

const options: SendOption[] = [
  {work_task_id: 226, stage_key: 's2', stage_label: 'Triage', target_map_id: 220, target_map_title: 'Repair', published: true},
  {work_task_id: 226, stage_key: 's2', stage_label: 'Triage', target_map_id: 222, target_map_title: 'Draft map', published: false},
  {work_task_id: 999, stage_key: 's4', stage_label: 'Other', target_map_id: 220, target_map_title: 'Repair', published: true},
];

test('optionsForStep keeps only this step, published first', () => {
  const o = optionsForStep(options, 226);
  assert.deepEqual(o.map((x) => x.target_map_id), [220, 222]);
  assert.deepEqual(optionsForStep(options, 1), []);
});

test('emptySheet: the only published target is pre-picked; counts start at 0; parent not blocked (D-1)', () => {
  const s = emptySheet(optionsForStep(options, 226), lines);
  assert.equal(s.targetMapId, 220);
  assert.deepEqual(s.counts, {11: 0, 12: 0});
  assert.equal(s.blockParent, false);
  assert.equal(s.reasonCode, '');
});

test('clampCount: the stepper never goes past the line or below 0, whole numbers only', () => {
  assert.equal(clampCount(5, 3), 3);
  assert.equal(clampCount(-1, 3), 0);
  assert.equal(clampCount(2.7, 3), 2);
  assert.equal(clampCount(Number.NaN, 3), 0);
});

test('validateSheet: a reason is required (E-EXC-010) and the target must be published (E-EXC-003)', () => {
  const s = emptySheet(optionsForStep(options, 226), lines);
  assert.equal(validateSheet(s, lines, optionsForStep(options, 226))?.code, 'E-EXC-010');
  assert.equal(validateSheet({...s, reasonCode: 'other', targetMapId: 222}, lines, optionsForStep(options, 226))?.code, 'E-EXC-003');
  assert.equal(validateSheet({...s, reasonCode: 'other'}, lines, optionsForStep(options, 226)), null);
});

test('UT-EXC-1-G01: junk reason, note and counts are all refused with the right code', () => {
  const opts = optionsForStep(options, 226);
  const base = {...emptySheet(opts, lines), reasonCode: 'other'};
  for (const reason of ['', 'broken', '<b>other</b>', 'OTHER']) {
    assert.equal(validateSheet({...base, reasonCode: reason}, lines, opts)?.code, 'E-EXC-010', `reason ${reason}`);
  }
  for (const note of ['x'.repeat(NOTE_MAX + 1), '<script>alert(1)</script>', 'see <a href="x">this</a>']) {
    assert.equal(validateSheet({...base, note}, lines, opts)?.code, 'E-EXC-011');
  }
  assert.equal(validateSheet({...base, note: 'x'.repeat(NOTE_MAX)}, lines, opts), null, 'exactly 500 is fine');
  for (const n of [4, -1, 2.5, Number.NaN]) {
    assert.equal(validateSheet({...base, counts: {11: n, 12: 0}}, lines, opts)?.code, 'E-EXC-006', `count ${n}`);
  }
});

test('buildExceptionRequest sends only the counts that move, trims the note, and the block toggle', () => {
  const s = {...emptySheet(optionsForStep(options, 226), lines), reasonCode: 'something_went_wrong', note: '  torn  ', counts: {11: 2, 12: 0}};
  assert.deepEqual(buildExceptionRequest(s, 'c-1'), {
    target_map_id: 220,
    reason_code: 'something_went_wrong',
    note: 'torn',
    lines: [{item_type_id: 11, quantity: 2}],
    also_block_parent: false,
    correlation_id: 'c-1',
  });
  const whole = {...s, counts: {11: 0, 12: 0}, note: '', blockParent: true};
  assert.deepEqual(buildExceptionRequest(whole, 'c-2'), {
    target_map_id: 220,
    reason_code: 'something_went_wrong',
    lines: [],
    also_block_parent: true,
    correlation_id: 'c-2',
  });
});

test('sentToast names what moved, where, and the new job number', () => {
  assert.equal(sentToast('Repair', 491, [{label: 'tables', quantity: 2}]), 'Sent 2 tables to Repair (#491)');
  assert.equal(sentToast('Repair', 491, [{label: 'tables', quantity: 2}, {label: 'chairs', quantity: 3}]), 'Sent 5 items to Repair (#491)');
  assert.equal(sentToast('Repair', 491, []), 'Sent to Repair (#491)');
});

test('isAlreadySent: only E-EXC-013 (a retry of a send that already saved) counts as sent', () => {
  assert.equal(isAlreadySent('This was already sent. Reopen the job to see it. (E-EXC-013)'), true);
  assert.equal(isAlreadySent('The order changed while you were sending. Close this and try again. (E-EXC-012)'), false);
  assert.equal(isAlreadySent("That didn't send. Try again."), false);
});
