// SCHED-1 (US-SCHED-1-03, US-SCHED-1-05) — The rules for putting a
// job's work onto the schedule, and for tweaking how long it is
// allowed to take.
//
// THREE DURATIONS, AND THEY MUST NOT BE CONFUSED:
//   expected  — from the map, through the pinned version. Never
//               written here, and never overwritten by a tweak.
//   scheduled — `planner_task.duration_minutes`. What the planner
//               actually set aside for it, for THIS job only.
//   actual    — from the log (LOG-1). Not touched by this epic.
// A tweak is simply "scheduled ≠ expected", which is what makes
// variance (VAR-1) computable later without storing anything extra.

export const MIN_SCHEDULED_MINUTES = 1;
export const MAX_SCHEDULED_MINUTES = 1440;

/** `other` is always allowed; anything else must be a job attribute key. */
export const OTHER_TWEAK_REASON = 'other';

/**
 * A scheduled duration must be a whole number of minutes from 1 to
 * 1440 (a day).
 *
 * Fractions are rejected rather than rounded: half a minute is not a
 * unit anyone schedules in, and silently rounding would make the
 * planner's number disagree with the stored one.
 */
export function isValidScheduledDuration(value: unknown): boolean {
  return (
    typeof value === 'number' &&
    Number.isInteger(value) &&
    value >= MIN_SCHEDULED_MINUTES &&
    value <= MAX_SCHEDULED_MINUTES
  );
}

export interface BlockDurationResult {
  /** Sum of the durations that were present. */
  minutes: number;
  /** Keys of tasks with no expected duration in the version. */
  missing: string[];
}

/**
 * The default scheduled duration for a block: the sum of its tasks'
 * expected minutes.
 *
 * A TASK WITH NO EXPECTED DURATION IS REPORTED, NOT GUESSED. It
 * contributes nothing to the sum and its key comes back in `missing`,
 * so the planner can be told "two of these steps have no estimate"
 * instead of being handed a total that quietly understates the work.
 *
 * In the MVP a "block" is a single work task (derived blocks are
 * deferred), so this usually sums one number — but it is written for
 * the list so blocks can arrive without changing the callers.
 */
export function defaultBlockDuration(
  tasks: ReadonlyArray<{stage_key: string; lens_key: string; expected_minutes?: number | null}>,
): BlockDurationResult {
  let minutes = 0;
  const missing: string[] = [];

  for (const t of tasks) {
    const m = t.expected_minutes;
    if (typeof m === 'number' && Number.isFinite(m) && m > 0) {
      minutes += m;
    } else {
      missing.push(`${t.stage_key}/${t.lens_key}`);
    }
  }

  return {minutes, missing};
}

/**
 * A tweak reason is optional. When given it must be `other` or a key
 * the job actually has, so a reason cannot point at an attribute that
 * was never set.
 */
export function isValidTweakReason(
  reason: string | null | undefined,
  jobAttributeKeys: ReadonlyArray<string>,
): boolean {
  if (reason === null || reason === undefined || reason === '') return true;
  if (reason === OTHER_TWEAK_REASON) return true;
  return jobAttributeKeys.includes(reason);
}
