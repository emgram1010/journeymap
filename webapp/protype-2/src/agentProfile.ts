// PLAN-2 (US-PLAN-2-01, US-PLAN-2-02) — The two rules an agent profile
// needs to get right, as pure functions so both sides can agree.
//
// Same reasoning as planTemplate.ts: the backend (apis/planner/573_*,
// 575_*) mirrors these exact rules; the golden cases below are what
// both must satisfy.

const COLOR_PATTERN = /^#[0-9a-fA-F]{6}$/;

/** True only for a full 6-digit "#RRGGBB" hex color. Empty is also valid — color is optional. */
export function isValidColorHex(value: unknown): boolean {
  if (value === '' || value === null || value === undefined) return true;
  return typeof value === 'string' && COLOR_PATTERN.test(value);
}

/** True when the daily capacity is a positive, finite number of hours. Zero and negative are rejected — a profile that can never work shouldn't silently exist as a default. */
export function isValidCapacityHours(value: unknown): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

/** An AI profile (no login) must name itself; a person profile borrows its name from the user at read time and never needs one here. */
export function isValidProfileName(name: unknown, userId: number): boolean {
  if (userId !== 0) return true;
  return typeof name === 'string' && name.trim().length > 0;
}
