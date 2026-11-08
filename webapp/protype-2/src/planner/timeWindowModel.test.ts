import assert from 'node:assert/strict';
import test from 'node:test';
import {
  formatWindow,
  formatDayShort,
  daysInsideWindow,
  compareByWindow,
  windowChipState,
  indexWindowsByJob,
  isPlacementOutsideWindow,
  validateWindow,
  type TimeWindow,
} from './timeWindowModel';

const win = (over: Partial<TimeWindow> = {}): TimeWindow => ({
  start_date: '2026-11-03',
  start_time: '09:00',
  end_date: '2026-11-03',
  end_time: '11:00',
  note: '',
  ...over,
});

// ── validateWindow ─────────────────────────────────────────────────

test('UT-TW-1-03-01: a good window passes', () => {
  assert.deepEqual(validateWindow(win()), {ok: true});
});

test('UT-TW-1-03-01: a badly written time is E-TW-001, on the right field', () => {
  for (const [field, value] of [
    ['start_time', '9:5'],
    ['start_time', '25:00'],
    ['start_time', ''],
    ['end_time', '11:60'],
    ['end_time', '1100'],
  ] as const) {
    const r = validateWindow(win({[field]: value}));
    assert.equal(r.ok, false, `${field}=${value}`);
    if (r.ok === false) {
      assert.equal(r.code, 'E-TW-001');
      assert.equal(r.field, field);
    }
  }
});

test('UT-TW-1-03-01: a missing or malformed date is E-TW-001', () => {
  for (const [field, value] of [
    ['start_date', ''],
    ['end_date', '3 Nov'],
    ['end_date', '2026-13-01'],
  ] as const) {
    const r = validateWindow(win({[field]: value}));
    assert.equal(r.ok, false, `${field}=${value}`);
    if (r.ok === false) assert.equal(r.code, 'E-TW-001');
  }
});

test('UT-TW-1-03-01: an end before, or equal to, the start is E-TW-002', () => {
  for (const w of [
    win({end_time: '08:59'}),
    win({end_time: '09:00'}),
    win({end_date: '2026-11-02', end_time: '23:00'}),
  ]) {
    const r = validateWindow(w);
    assert.equal(r.ok, false);
    if (r.ok === false) {
      assert.equal(r.code, 'E-TW-002');
      assert.equal(r.field, 'end_time');
      assert.match(r.message, /end after it starts/);
    }
  }
});

test('UT-TW-1-03-01: a window wholly outside the plan window is E-TW-003; overlap is fine', () => {
  const plan = {start: '2026-11-02', end: '2026-11-06'};
  const outside = validateWindow(win({start_date: '2026-11-10', end_date: '2026-11-10'}), plan);
  assert.equal(outside.ok, false);
  if (outside.ok === false) assert.equal(outside.code, 'E-TW-003');

  // Q-3 default: partial overlap is allowed.
  const straddles = validateWindow(win({start_date: '2026-11-01', end_date: '2026-11-02'}), plan);
  assert.deepEqual(straddles, {ok: true});

  // A plan with no window set constrains nothing.
  assert.deepEqual(validateWindow(win({start_date: '2030-01-01', end_date: '2030-01-01'}), {start: null, end: null}), {ok: true});
});

test('UT-TW-1-03-01: a note over 200 characters is E-TW-006', () => {
  const r = validateWindow(win({note: 'x'.repeat(201)}));
  assert.equal(r.ok, false);
  if (r.ok === false) assert.equal(r.code, 'E-TW-006');
  assert.deepEqual(validateWindow(win({note: 'x'.repeat(200)})), {ok: true});
});

test('UT-TW-1-03-01: messages are plain language, no codes or jargon', () => {
  for (const w of [win({start_time: 'x'}), win({end_time: '08:00'}), win({note: 'x'.repeat(201)})]) {
    const r = validateWindow(w);
    assert.equal(r.ok, false);
    if (r.ok === false) assert.doesNotMatch(r.message, /E-TW|null|undefined|HH:MM/);
  }
});

// ── crossing midnight (D-4) ────────────────────────────────────────

test('UT-TW-1-03-02: a window crossing midnight is valid', () => {
  assert.deepEqual(
    validateWindow(win({start_time: '18:00', end_date: '2026-11-04', end_time: '06:00'})),
    {ok: true},
  );
});

// ── isPlacementOutsideWindow ───────────────────────────────────────

test('UT-TW-1-03-03: inside, outside and both boundary days', () => {
  const multi = win({start_date: '2026-11-03', end_date: '2026-11-05'});
  assert.equal(isPlacementOutsideWindow(multi, '2026-11-03'), false);
  assert.equal(isPlacementOutsideWindow(multi, '2026-11-04'), false);
  assert.equal(isPlacementOutsideWindow(multi, '2026-11-05'), false);
  assert.equal(isPlacementOutsideWindow(multi, '2026-11-02'), true);
  assert.equal(isPlacementOutsideWindow(multi, '2026-11-06'), true);
});

test('UT-TW-1-03-03: no window, or an unplaced card, never warns', () => {
  assert.equal(isPlacementOutsideWindow(null, '2026-11-09'), false);
  assert.equal(isPlacementOutsideWindow(win(), null), false);
  assert.equal(isPlacementOutsideWindow(win(), ''), false);
});

// ── formatWindow ───────────────────────────────────────────────────

test('UT-TW-1-03-05: indexWindowsByJob looks up by work_item_id', () => {
  const rows = [
    {...win(), work_item_id: 10},
    {...win({start_time: '14:00'}), work_item_id: 42},
  ];
  const map = indexWindowsByJob(rows);
  assert.equal(map.size, 2);
  assert.equal(map.get(42)?.start_time, '14:00');
  assert.equal(map.get(999), undefined);
});

test('UT-TW-1-03-04: same-day, multi-day and null', () => {
  assert.equal(formatWindow(win()), '09:00–11:00, 3 Nov');
  assert.equal(
    formatWindow(win({start_time: '18:00', end_date: '2026-11-04', end_time: '06:00'})),
    '3 Nov 18:00 – 4 Nov 06:00',
  );
  assert.equal(formatWindow(null), '');
});

// ── PUX-1 / PUX-2 ──────────────────────────────────────────────────────

test('UT-PUX-1-03: formatDayShort reads like a planner talks', () => {
  assert.equal(formatDayShort('2026-11-04'), 'Wed 4 Nov');
  assert.equal(formatDayShort('2026-10-27'), 'Tue 27 Oct');
  assert.equal(formatDayShort('bad'), 'bad');
});

test('UT-PUX-2-01: daysInsideWindow — single day inside the plan', () => {
  assert.deepEqual(daysInsideWindow(win({start_date: '2026-11-07', end_date: '2026-11-07'}), '2026-11-01', '2026-11-07'), ['2026-11-07']);
});

test('UT-PUX-2-01: daysInsideWindow — multi-day, crosses midnight, clipped to the plan', () => {
  const w = win({start_date: '2026-10-30', start_time: '18:00', end_date: '2026-11-02', end_time: '06:00'});
  assert.deepEqual(daysInsideWindow(w, '2026-11-01', '2026-11-07'), ['2026-11-01', '2026-11-02']);
});

test('UT-PUX-2-01: daysInsideWindow — entirely outside the plan, or no window, or no plan', () => {
  assert.deepEqual(daysInsideWindow(win({start_date: '2026-12-01', end_date: '2026-12-02'}), '2026-11-01', '2026-11-07'), []);
  assert.deepEqual(daysInsideWindow(null, '2026-11-01', '2026-11-07'), []);
  assert.deepEqual(daysInsideWindow(win({start_date: '2026-11-03', end_date: '2026-11-04'}), null, null), ['2026-11-03', '2026-11-04']);
});

test('UT-PUX-2-02: compareByWindow — earliest window end first, no window last', () => {
  const a = win({start_date: '2026-11-05', end_date: '2026-11-06'});
  const b = win({start_date: '2026-11-02', end_date: '2026-11-03'});
  const sorted = [a, null, b].sort(compareByWindow);
  assert.deepEqual(sorted, [b, a, null]);
});

test('UT-PUX-2-03: windowChipState — none / fine / outside', () => {
  const w = win({start_date: '2026-11-07', end_date: '2026-11-07'});
  assert.equal(windowChipState(null, ['2026-11-04']), 'none');
  assert.equal(windowChipState(w, []), 'fine');
  assert.equal(windowChipState(w, ['2026-11-07']), 'fine');
  assert.equal(windowChipState(w, ['2026-11-07', '2026-11-04']), 'outside');
});
