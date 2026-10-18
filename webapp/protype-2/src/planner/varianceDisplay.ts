// W3 (2026-10-17) — Turning variance numbers into something a person
// can read at a glance.
//
// PURE AND TESTED SEPARATELY, like `dayNavigation.ts` and
// `performerView.ts`. The judgements here are small but they are
// judgements — what counts as "on time", how much precision to show,
// what to say when there is nothing to compare — and a judgement
// rendered inside a component is one nobody can test.
//
// THE NUMBERS ARRIVE RAW. The server computes in exact minutes, so a
// step can come back as 0.06225 minutes (a performer tapping start and
// done in the same breath) or 154.26895. Rounding is a display concern
// and belongs here, not in the endpoint — the stored figure stays
// exact so the maths never compounds a rounding error.
//
// NULL IS NOT ZERO. A step nobody started has `actual_minutes: null`,
// which means "we don't know", not "it took no time". Everything below
// keeps those two apart, because showing "0 min, 100% under" for work
// that never happened is the kind of confidently wrong number that
// makes a whole report untrustworthy.

/** Whole minutes for display, or null when there is nothing to show. */
export function roundMinutes(value: number | null | undefined): number | null {
  if (value === null || value === undefined || Number.isNaN(value)) return null;
  return Math.round(value);
}

/** "25 min", "1 hr 10 min", "—". */
export function formatMinutes(value: number | null | undefined): string {
  const total = roundMinutes(value);
  if (total === null) return '—';
  if (total < 60) return `${total} min`;
  const hours = Math.floor(total / 60);
  const minutes = total % 60;
  return minutes === 0 ? `${hours} hr` : `${hours} hr ${minutes} min`;
}

export type GapTone = 'over' | 'under' | 'on_track' | 'unknown';

/**
 * How a step's actual time compares with what was expected.
 *
 * `on_track` is deliberately a BAND, not an exact match: nobody
 * finishes a 25-minute step in exactly 25 minutes, and a report that
 * flags every job as off-plan tells you nothing. Anything within 10%
 * (or under 2 minutes either way, which keeps very short steps from
 * being judged by percentages) reads as on track.
 */
export function gapTone(gapMinutes: number | null | undefined, gapPct: number | null | undefined): GapTone {
  if (gapMinutes === null || gapMinutes === undefined || Number.isNaN(gapMinutes)) return 'unknown';
  const absMinutes = Math.abs(gapMinutes);
  const absPct = gapPct === null || gapPct === undefined ? 0 : Math.abs(gapPct);
  if (absMinutes < 2 || absPct <= 10) return 'on_track';
  return gapMinutes > 0 ? 'over' : 'under';
}

/** "12 min over", "5 min under", "On track", "Not recorded". */
export function formatGap(gapMinutes: number | null | undefined, gapPct: number | null | undefined): string {
  const tone = gapTone(gapMinutes, gapPct);
  if (tone === 'unknown') return 'Not recorded';
  if (tone === 'on_track') return 'On track';
  const amount = formatMinutes(Math.abs(gapMinutes as number));
  return `${amount} ${tone}`;
}

/**
 * One line summarising a whole job, for the collapsed row.
 *
 * Says the most useful true thing available, in this order: nothing
 * recorded at all → say so plainly; otherwise the total against the
 * plan, and the number of steps that ran long enough to be outliers.
 */
export function summariseJob(rows: Array<{
  expected_minutes: number | null;
  actual_minutes: number | null;
  is_outlier: boolean;
}>): string {
  const recorded = rows.filter((r) => r.actual_minutes !== null && r.actual_minutes !== undefined);
  if (recorded.length === 0) return 'Nothing recorded yet';

  const actual = recorded.reduce((sum, r) => sum + (r.actual_minutes ?? 0), 0);
  // Only count the plan for steps that actually have a recorded time,
  // so a half-finished job isn't reported as massively under plan.
  const expected = recorded.reduce((sum, r) => sum + (r.expected_minutes ?? 0), 0);
  const outliers = rows.filter((r) => r.is_outlier).length;

  const head = `${formatMinutes(actual)} actual vs ${formatMinutes(expected)} planned`;
  const gap = formatGap(actual - expected, expected > 0 ? ((actual - expected) / expected) * 100 : null);
  const tail = outliers > 0 ? ` · ${outliers} step${outliers === 1 ? '' : 's'} well over` : '';
  return `${head} · ${gap}${tail}`;
}

const REASON_LABELS: Record<string, string> = {
  waiting_on_someone: 'Waiting on someone',
  missing_information: 'Missing information',
  something_went_wrong: 'Something went wrong',
  other: 'Other',
};

/** The reason a step was blocked, in the words the performer picked. */
export function reasonLabel(code: string | null | undefined): string | null {
  if (!code) return null;
  return REASON_LABELS[code] ?? code;
}

const EVENT_LABELS: Record<string, string> = {
  started: 'Started',
  completed: 'Finished',
  blocked: 'Blocked',
  unblocked: 'Unblocked',
  skipped: 'Skipped',
  reopened: 'Reopened',
  note: 'Note',
};

export function eventLabel(eventType: string): string {
  return EVENT_LABELS[eventType] ?? eventType;
}
