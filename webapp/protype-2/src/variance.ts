// VAR-1 (US-VAR-1-01, -02) — Per-task variance, derived, never stored.
//
// No imports, same discipline as logModel.ts/jobModel.ts: a plain
// function over plain data, testable without a server. The backend
// twin is `functions/variance/compute_task_variance.xs`; a golden
// fixture pins both sides to the same numbers (CLAUDE.md's rule for
// any value computed on both ends).
//
// NOTHING HERE IS A GUESS. Every field is null when its inputs are
// missing, never a fallback value — a null variance is honest; a
// variance computed from a guessed duration is not.

export type VarianceEventType = 'started' | 'completed' | 'blocked' | 'unblocked' | 'skipped' | 'reopened' | 'note';

export interface VarianceEvent {
  event_type: VarianceEventType;
  occurred_at: number;
}

export interface TaskVarianceInput {
  /** This task's own activity log, in any order — sorted internally by `occurred_at`. */
  events: ReadonlyArray<VarianceEvent>;
  /** Minutes from the pinned map version (TIME-1). Null when the map never had a duration for this cell (W-VAR-004). */
  expectedMinutes: number | null;
  /** Minutes from the published snapshot — the planner's tweak included, if any. */
  scheduledMinutes: number | null;
  /** The planned start as an absolute instant (same clock as `occurred_at`), for lateness. Null when there is nothing to compare against (e.g. an unscheduled task). */
  plannedStartAt: number | null;
}

export interface TaskVarianceResult {
  /** The span of the attempt that produced the CURRENT completion — start to done/skipped, wall-clock, blocked time included. Null when never completed, or completed without ever starting (D-38). */
  actualMinutes: number | null;
  /** Sum of every blocked→unblocked interval. Reported separately; never subtracted from `actualMinutes`. */
  blockedMinutes: number;
  expectedGapMinutes: number | null;
  expectedGapPct: number | null;
  scheduledGapMinutes: number | null;
  scheduledGapPct: number | null;
  /** How late the FIRST start was against `plannedStartAt`. Negative means early. Survives any later reopen — this is about when work actually began, once. */
  startLatenessMinutes: number | null;
  isOutlier: boolean;
  /** Data-quality codes from the Governance table (W-VAR-001..004). Empty when clean. */
  warnings: string[];
}

/** Reference the outlier rule compares against: scheduled if present, else expected. */
export const OUTLIER_FACTOR = 2.0;
export const OUTLIER_FLOOR_MINUTES = 10;

/**
 * A task is an outlier when its actual time exceeds BOTH a relative
 * threshold (factor × reference) and an absolute floor (reference +
 * floor minutes) — the floor exists so a 3-minute task that took 12
 * minutes isn't flagged over a difference nobody would notice.
 *
 * Never flags without a reference or without a completed actual —
 * US-VAR-1-02's own acceptance.
 */
export function isOutlier(actualMinutes: number | null, reference: number | null): boolean {
  if (actualMinutes == null || reference == null) return false;
  return actualMinutes > Math.max(OUTLIER_FACTOR * reference, reference + OUTLIER_FLOOR_MINUTES);
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

function gap(actual: number | null, reference: number | null): {minutes: number | null; pct: number | null} {
  if (actual == null || reference == null) return {minutes: null, pct: null};
  const minutes = actual - reference;
  const pct = reference === 0 ? null : round1((minutes / reference) * 100);
  return {minutes, pct};
}

export function computeTaskVariance(input: TaskVarianceInput): TaskVarianceResult {
  // Processed in the order given, never re-sorted — same convention as
  // logModel.ts::replay and replay_task.xs, both of which trust the
  // caller to have ordered by `occurred_at` (the backend does this at
  // the query level). Re-sorting here would make W-VAR-002 (end
  // earlier than start) impossible to detect: sorting ascending by
  // time guarantees a later-processed event never has an earlier
  // timestamp than an earlier-processed one, which would hide exactly
  // the clock/data anomaly this check exists to catch.
  const events = input.events;

  let firstStartAt: number | null = null; // survives reopen — when work truly first began
  let currentAttemptStart: number | null = null; // reset on reopen — the attempt behind the current/last completion
  let lastSpanStart: number | null = null; // currentAttemptStart AS OF the most recent completion
  let lastCompletionAt: number | null = null;
  let blockedStart: number | null = null;
  let blockedMinutes = 0;

  for (const e of events) {
    switch (e.event_type) {
      case 'started':
        if (firstStartAt === null) firstStartAt = e.occurred_at;
        if (currentAttemptStart === null) currentAttemptStart = e.occurred_at;
        break;
      case 'blocked':
        blockedStart = e.occurred_at;
        break;
      case 'unblocked':
        if (blockedStart !== null) {
          blockedMinutes += (e.occurred_at - blockedStart) / 60_000;
          blockedStart = null;
        }
        break;
      case 'completed':
      case 'skipped':
        lastCompletionAt = e.occurred_at;
        lastSpanStart = currentAttemptStart; // may be null — "done without start" (D-38)
        break;
      case 'reopened':
        // The resumed attempt begins AT the reopen itself — not null.
        // `logModel.ts::canTransition` has no `in_progress`+`started`
        // row, so a real event log can never contain an explicit
        // `started` after a `reopened`; the reopen is the only signal
        // that work resumed. Found live (VAR-1 smoke test): a task
        // reopened then completed directly (no re-start, which the UI
        // doesn't even offer from `in_progress`) came back with
        // `actual_minutes: null` and a spurious W-VAR-001 — the first
        // version of this function wrongly treated every reopen as
        // "unknown start" rather than "resumed now".
        currentAttemptStart = e.occurred_at;
        lastSpanStart = null;
        lastCompletionAt = null;
        blockedStart = null; // defensive — a valid history cannot reopen mid-block
        break;
      case 'note':
        break;
    }
  }

  const actualMinutes =
    lastCompletionAt !== null && lastSpanStart !== null ? (lastCompletionAt - lastSpanStart) / 60_000 : null;

  const startLatenessMinutes =
    firstStartAt !== null && input.plannedStartAt !== null ? (firstStartAt - input.plannedStartAt) / 60_000 : null;

  const expectedGap = gap(actualMinutes, input.expectedMinutes);
  const scheduledGap = gap(actualMinutes, input.scheduledMinutes);
  const reference = input.scheduledMinutes ?? input.expectedMinutes;

  const warnings: string[] = [];
  if (lastCompletionAt !== null && lastSpanStart === null) warnings.push('W-VAR-001');
  if (lastCompletionAt !== null && lastSpanStart !== null && lastCompletionAt < lastSpanStart) warnings.push('W-VAR-002');
  if (actualMinutes !== null && actualMinutes > 1440) warnings.push('W-VAR-003');
  if (lastCompletionAt !== null && input.expectedMinutes == null) warnings.push('W-VAR-004');

  return {
    actualMinutes,
    blockedMinutes,
    expectedGapMinutes: expectedGap.minutes,
    expectedGapPct: expectedGap.pct,
    scheduledGapMinutes: scheduledGap.minutes,
    scheduledGapPct: scheduledGap.pct,
    startLatenessMinutes,
    isOutlier: isOutlier(actualMinutes, reference),
    warnings,
  };
}
