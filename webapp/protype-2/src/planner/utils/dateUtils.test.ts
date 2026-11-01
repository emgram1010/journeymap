import assert from 'node:assert/strict';
import test from 'node:test';
import {getWindowBounds, getWindowDays, getWindowPage, isDateOutOfWindow} from './dateUtils';

// ── getWindowDays ────────────────────────────────────────────────────
// WIN-1 (US-WIN-1-02). The grid used to render a fixed spanWeeks*7 days
// from the window start, so a 3-day plan still drew a fortnight of
// droppable columns outside its own window. These cover the real length.

test('UT-WIN-1-02-01: a 3-day window is 3 days of columns, not 7', () => {
  assert.deepEqual(getWindowDays('2026-11-01', '2026-11-03'), [
    '2026-11-01',
    '2026-11-02',
    '2026-11-03',
  ]);
});

test('UT-WIN-1-02-02: both window ends are included (D-6)', () => {
  const days = getWindowDays('2026-11-01', '2026-11-07');
  assert.equal(days.length, 7);
  assert.equal(days[0], '2026-11-01');
  assert.equal(days[6], '2026-11-07');
});

test('UT-WIN-1-02-03: a one-day window is one column', () => {
  assert.deepEqual(getWindowDays('2026-10-14', '2026-10-14'), ['2026-10-14']);
});

test('UT-WIN-1-02-04: a window spanning a month boundary rolls over correctly', () => {
  assert.deepEqual(getWindowDays('2026-10-30', '2026-11-02'), [
    '2026-10-30',
    '2026-10-31',
    '2026-11-01',
    '2026-11-02',
  ]);
});

test('UT-WIN-1-02-05: a missing window yields no columns rather than a guessed fortnight', () => {
  assert.deepEqual(getWindowDays('', '2026-11-07'), []);
  assert.deepEqual(getWindowDays('2026-11-01', ''), []);
});

test('UT-WIN-1-02-06: a backwards window degrades to its start day, never to zero columns', () => {
  // Plan 34 in the live data is archived with odd bounds; a grid that
  // renders nothing at all is harder to diagnose than one bad column.
  assert.deepEqual(getWindowDays('2026-11-07', '2026-11-01'), ['2026-11-07']);
});

// ── getWindowPage ────────────────────────────────────────────────────

test('UT-WIN-1-02-07: a page never runs past the end of the window', () => {
  const page = getWindowPage('2026-11-01', '2026-11-03', 14, 0);
  assert.deepEqual(page.days, ['2026-11-01', '2026-11-02', '2026-11-03']);
  assert.equal(page.rangeStart, '2026-11-01');
  assert.equal(page.rangeEnd, '2026-11-03');
  assert.equal(page.canPagePrev, false);
  assert.equal(page.canPageNext, false);
});

test('UT-WIN-1-02-08: a window longer than one page still pages', () => {
  const first = getWindowPage('2026-11-01', '2026-11-21', 7, 0);
  assert.equal(first.days.length, 7);
  assert.equal(first.rangeEnd, '2026-11-07');
  assert.equal(first.canPagePrev, false);
  assert.equal(first.canPageNext, true);

  const second = getWindowPage('2026-11-01', '2026-11-21', 7, 7);
  assert.equal(second.rangeStart, '2026-11-08');
  assert.equal(second.canPagePrev, true);
  assert.equal(second.canPageNext, true);

  const last = getWindowPage('2026-11-01', '2026-11-21', 7, 14);
  assert.equal(last.rangeEnd, '2026-11-21');
  assert.equal(last.canPageNext, false);
});

test('UT-WIN-1-02-09: a final short page is short, not padded past the window', () => {
  const last = getWindowPage('2026-11-01', '2026-11-10', 7, 7);
  assert.deepEqual(last.days, ['2026-11-08', '2026-11-09', '2026-11-10']);
  assert.equal(last.canPageNext, false);
});

test('UT-WIN-1-02-10: a stale offset is clamped back inside a window that shrank', () => {
  // The grid keeps its page offset in component state. If the plan's
  // window is edited down while the user sits on page 3, the offset is
  // suddenly past the end — clamp rather than render an empty grid.
  const page = getWindowPage('2026-11-01', '2026-11-03', 7, 21);
  assert.equal(page.days.length, 1);
  assert.equal(page.rangeStart, '2026-11-03');
  assert.equal(page.canPageNext, false);
  assert.equal(page.canPagePrev, true);
});

test('UT-WIN-1-02-11: a negative offset is treated as the first page', () => {
  const page = getWindowPage('2026-11-01', '2026-11-07', 7, -7);
  assert.equal(page.rangeStart, '2026-11-01');
  assert.equal(page.canPagePrev, false);
});

test('UT-WIN-1-02-12: no window means no page, and no paging controls', () => {
  const page = getWindowPage('', '', 7, 0);
  assert.deepEqual(page.days, []);
  assert.equal(page.rangeStart, '');
  assert.equal(page.rangeEnd, '');
  assert.equal(page.canPagePrev, false);
  assert.equal(page.canPageNext, false);
});

// ── getWindowBounds ──────────────────────────────────────────────────
// What a date picker's min/max attributes get. Both ends or neither:
// a half-bounded picker would refuse valid days on the unbounded side.

test('UT-WIN-1-02-13: a complete window becomes picker bounds', () => {
  assert.deepEqual(getWindowBounds('2026-11-01', '2026-11-07'), {
    min: '2026-11-01',
    max: '2026-11-07',
  });
});

test('UT-WIN-1-02-14: an incomplete window bounds nothing', () => {
  assert.deepEqual(getWindowBounds('', '2026-11-07'), {});
  assert.deepEqual(getWindowBounds('2026-11-01', ''), {});
  assert.deepEqual(getWindowBounds(null, null), {});
  assert.deepEqual(getWindowBounds(undefined, undefined), {});
});

// ── isDateOutOfWindow (existing; pinned so -02 cannot regress it) ────
// The 17 legacy violations are only visible because of this flag, so the
// badges it drives must keep working (D-2: enforcement is write-time).

test('UT-WIN-1-02-15: the legacy out-of-window flag still flags, and both ends still pass', () => {
  assert.equal(isDateOutOfWindow('2026-10-27', '2026-11-01', '2026-11-07'), true);
  assert.equal(isDateOutOfWindow('2026-11-20', '2026-11-01', '2026-11-07'), true);
  assert.equal(isDateOutOfWindow('2026-11-01', '2026-11-01', '2026-11-07'), false);
  assert.equal(isDateOutOfWindow('2026-11-07', '2026-11-01', '2026-11-07'), false);
});
