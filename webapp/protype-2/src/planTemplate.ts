// PLAN-1 (US-PLAN-1-01, US-PLAN-1-04) — The two rules a plan template
// needs to get right, as pure functions so both sides can agree.
//
// These live here rather than in the planner app because that is where
// the repo's unit tests run (see the test conventions in
// product/stories/phase-4/README.md). The backend mirrors the same
// rules; the golden cases below are what both must satisfy.

/** A plan window is INCLUSIVE of both ends. */
export const MIN_WINDOW_DAYS = 1;
export const MAX_WINDOW_DAYS = 366;

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;

/**
 * The last day of a window that starts on `start` and runs for
 * `windowDays` days.
 *
 * INCLUSIVE, so a 14-day window ending 13 days after it starts — not
 * 14. Off-by-one here would silently give every plan an extra day,
 * and the window is what decides whether work shows as out-of-range.
 *
 * All arithmetic is in UTC. Using local time would make the result
 * depend on the server's timezone and shift a window by a day for
 * anyone the wrong side of midnight.
 */
export function windowEnd(start: string, windowDays: number): string {
  if (!DATE_PATTERN.test(start)) {
    throw new Error(`windowEnd: start must be YYYY-MM-DD, got "${start}"`);
  }
  if (!Number.isInteger(windowDays) || windowDays < MIN_WINDOW_DAYS) {
    throw new Error(`windowEnd: windowDays must be a whole number >= 1, got ${windowDays}`);
  }

  const [y, m, d] = start.split('-').map(Number);
  // Date.UTC normalises overflow for us, which is what makes month,
  // year and leap-day boundaries fall out correctly rather than
  // needing to be special-cased.
  const ms = Date.UTC(y, m - 1, d + (windowDays - 1));
  const end = new Date(ms);

  const yy = end.getUTCFullYear().toString().padStart(4, '0');
  const mm = (end.getUTCMonth() + 1).toString().padStart(2, '0');
  const dd = end.getUTCDate().toString().padStart(2, '0');
  return `${yy}-${mm}-${dd}`;
}

/**
 * True only for a 24-hour `HH:MM` with both parts two digits.
 *
 * "8:00" is rejected on purpose. It is unambiguous to a human but not
 * to the string comparison the backend uses to sort and compare start
 * times, and accepting both spellings means the same time of day has
 * two representations in the database.
 */
export function isValidStartTime(value: unknown): boolean {
  return typeof value === 'string' && TIME_PATTERN.test(value);
}

/** True when `windowDays` is a whole number inside the allowed range. */
export function isValidWindowDays(value: unknown): boolean {
  return (
    typeof value === 'number' &&
    Number.isInteger(value) &&
    value >= MIN_WINDOW_DAYS &&
    value <= MAX_WINDOW_DAYS
  );
}
