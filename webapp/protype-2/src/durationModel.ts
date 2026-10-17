// TIME-1 (US-TIME-1-01) — One canonical way to turn a cell's duration
// into minutes, used everywhere "how long" matters (PUB-1's version
// snapshot, JOB-1's hydrated tasks, VAR-1's variance maths).
//
// Never throws, never guesses: anything it can't confidently convert
// returns null, and the caller decides what that means (usually
// "duration not set yet" / "flag as incomplete" — see AUTH-1 readiness
// and US-TIME-1-04's "value without a unit" rule).
export const WORKDAY_MINUTES = 480;

export type DurationUnit = 'minutes' | 'hours' | 'days' | 'weeks';

const MULTIPLIER: Record<DurationUnit, number> = {
  minutes: 1,
  hours: 60,
  days: WORKDAY_MINUTES,
  weeks: 5 * WORKDAY_MINUTES,
};

function isValidUnit(unit: unknown): unit is DurationUnit {
  return typeof unit === 'string' && unit in MULTIPLIER;
}

/**
 * Converts a duration value+unit to whole minutes, rounded half-up.
 * Returns null for anything not confidently convertible: missing,
 * negative, non-numeric, or an unrecognised unit.
 */
export function toMinutes(value: number | string | null | undefined, unit: string | null | undefined): number | null {
  if (value === null || value === undefined || value === '') return null;
  if (!isValidUnit(unit)) return null;

  const numeric = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(numeric)) return null;
  if (numeric < 0) return null;

  const minutes = numeric * MULTIPLIER[unit];
  // Half-up rounding (not banker's rounding): Math.floor(x + 0.5) matches
  // the epic's "1.5 minutes -> 2" expectation for positive values, which
  // is all this domain ever produces (negatives are already rejected).
  return Math.floor(minutes + 0.5);
}
