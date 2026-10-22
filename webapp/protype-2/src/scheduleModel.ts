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

// ── BLK-1 (US-BLK-1-07) — one slot can cover a whole card ──────────
//
// A SLOT USED TO MEAN A STEP, AND THE FRONTEND WAS WRITTEN THAT WAY.
// `adaptBoard` kept its linked steps in a `Map` keyed by
// `planner_task_id`, so a slot covering two steps kept only whichever
// one the query returned last — the board card showed one arbitrary
// stage as though it were the whole card, and the slot's `workTaskId`
// pointed at it. These two functions are the rule that replaces that
// overwrite, kept here rather than inline in a component so the card
// rule can be asserted without a browser.

export interface SlotStep {
  planner_task_id: number;
  work_task_id: number;
  /**
   * `planner_task_work_task.position`, 1..n. Optional because the
   * board's hydration did not return it before this story; a step
   * without a usable one keeps its arrival order rather than jumping
   * to the front.
   */
  position?: number | null;
}

export interface ScheduledSlot<T extends SlotStep> {
  plannerTaskId: number;
  /** Every step the slot covers, in `position` order. Never empty. */
  steps: T[];
  stepCount: number;
}

/** A position is usable only if it is a whole number from 1 — `0` is what an untouched int column reads as (CLAUDE.md), not a real first place. */
function sortKey(position: number | null | undefined): number {
  return typeof position === 'number' && Number.isInteger(position) && position >= 1
    ? position
    : Number.MAX_SAFE_INTEGER;
}

/**
 * Groups a flat list of scheduled steps into one entry per slot.
 *
 * NEVER DROPS A STEP, the same rule `toPerformerItems` and
 * `toSessions` already state: a step with a duplicate or missing
 * position still appears, in arrival order behind the positioned ones.
 * Dropping one would hide work that is really on somebody's day.
 *
 * Slot order is first-appearance order, so the caller's own ordering
 * (the board's, which is by day and seq) survives the grouping.
 */
export function groupStepsBySlot<T extends SlotStep>(steps: ReadonlyArray<T>): ScheduledSlot<T>[] {
  const order: number[] = [];
  const bySlot = new Map<number, T[]>();

  for (const step of steps) {
    const existing = bySlot.get(step.planner_task_id);
    if (existing) {
      existing.push(step);
    } else {
      bySlot.set(step.planner_task_id, [step]);
      order.push(step.planner_task_id);
    }
  }

  return order.map((plannerTaskId) => {
    const group = bySlot.get(plannerTaskId) as T[];
    const sorted = group
      .map((step, index) => ({step, index}))
      .sort((a, b) => sortKey(a.step.position) - sortKey(b.step.position) || a.index - b.index)
      .map((entry) => entry.step);
    return {plannerTaskId, steps: sorted, stepCount: sorted.length};
  });
}

/**
 * What a linked slot should be called on the board when it stores no
 * title of its own (which it deliberately does not — "reference, do
 * not copy").
 *
 * ONE STEP READS AS THE STEP; SEVERAL READ AS THE CARD. Naming a
 * multi-step card after its first stage would be the old bug with a
 * deterministic order instead of an arbitrary one: the planner would
 * still believe the slot was one stage of the work. The step count is
 * the honest answer, and the stages themselves are one tap away.
 *
 * Returns null when there is nothing to name, so the caller keeps its
 * own fallback chain rather than being handed a made-up string.
 */
export function linkedCardTitle(
  steps: ReadonlyArray<{stage_key: string; step_title?: string | null; job_title?: string | null}>,
): string | null {
  if (steps.length === 0) return null;

  const job = steps[0].job_title;
  if (steps.length === 1) {
    const step = steps[0];
    return step.step_title || `${job ?? 'Job'} — ${step.stage_key}`;
  }

  return `${job ?? 'Job'} · ${steps.length} steps`;
}
