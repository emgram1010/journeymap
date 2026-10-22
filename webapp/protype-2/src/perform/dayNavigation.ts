// GAP-FIX W4/W5 (2026-10-17) — Which day the performer is looking at,
// and what to say when that day is empty.
//
// PURE, AND TESTED SEPARATELY FROM THE SCREEN, for the same reason
// `performerView.ts` and `sessionModel.ts` are: the interesting part of
// both fixes is a decision ("which day has work next", "why is this
// empty"), and a decision rendered inside a component is a decision
// nobody can test.
//
// TWO GAPS, ONE DATA SOURCE. W4 (the performer can only ever see today)
// and W5 (the empty screen can't say why it's empty) both need the same
// fact — the set of days this person actually has published work on —
// which `perform/today` now returns as `my_dates`.
//
// DATES ARE HANDLED AS STRINGS, NEVER AS `Date` OBJECTS, except in the
// one formatting helper. `new Date("2026-10-19")` parses as UTC
// midnight and then prints in local time, so west of Greenwich it
// renders as the 18th — the exact class of off-by-one-day bug W8 is
// about. ISO dates sort and compare correctly as plain strings, so
// everything but the human label stays textual.

/** ISO dates, de-duplicated and oldest first. The server returns them raw and unsorted on purpose (see its own header). */
export function publishedDays(dates: string[]): string[] {
  return Array.from(new Set(dates.filter(Boolean))).sort();
}

/** The nearest day with work strictly before `date`, or null. */
export function prevDayWithWork(days: string[], date: string): string | null {
  const earlier = days.filter((d) => d < date);
  return earlier.length > 0 ? earlier[earlier.length - 1] : null;
}

/** The nearest day with work strictly after `date`, or null. */
export function nextDayWithWork(days: string[], date: string): string | null {
  return days.find((d) => d > date) ?? null;
}

/** `date` shifted by whole days, still as an ISO string. Used by the plain ‹ › steps. */
export function addDays(date: string, delta: number): string {
  const ms = Date.parse(`${date}T00:00:00Z`);
  if (Number.isNaN(ms)) return date;
  return new Date(ms + delta * 86_400_000).toISOString().slice(0, 10);
}

/** "Sat 19 Oct". Formatted in UTC so the label always matches the ISO string it came from. */
export function formatDayLabel(date: string): string {
  const ms = Date.parse(`${date}T00:00:00Z`);
  if (Number.isNaN(ms)) return date;
  return new Date(ms).toLocaleDateString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    timeZone: 'UTC',
  });
}

export type EmptyDayReason =
  /** This login isn't linked to any agent — nothing can ever reach it. */
  | 'no_agent'
  /** Linked, but nothing has ever been published to them. */
  | 'nothing_published'
  /** Work exists, just not on this day. */
  | 'other_days'
  /** This day genuinely has work published and none of it is showing — the "shouldn't happen" case. */
  | 'empty_day';

export interface EmptyDayDiagnosis {
  reason: EmptyDayReason;
  /** One sentence naming the cause, not the symptom. */
  headline: string;
  /** What to do about it, in the reader's own terms. */
  detail: string;
  /** A day worth jumping to, when there is one. */
  jumpTo: string | null;
}

/**
 * Why is this day empty?
 *
 * The old screen said "Nothing is scheduled for you today." for all
 * four of these. Three of them are not the same problem at all, and
 * the one that looks most like a bug — work published for a different
 * day — is the one that is working exactly as designed.
 */
export function diagnoseEmptyDay(input: {
  date: string;
  today: string;
  agentIds: number[];
  days: string[];
}): EmptyDayDiagnosis {
  const {date, today, agentIds, days} = input;
  const isToday = date === today;

  if (agentIds.length === 0) {
    return {
      reason: 'no_agent',
      headline: "You're not set up as an agent yet.",
      detail:
        'Work is handed out to agents, and no agent on this account is linked to your login — so nothing can reach you here. Ask whoever plans the work to link your login to your agent.',
      jumpTo: null,
    };
  }

  if (days.length === 0) {
    return {
      reason: 'nothing_published',
      headline: 'Nothing has been published to you yet.',
      detail:
        "You're set up as an agent, but no day has been published to you. A planned day only appears here once it's published to live.",
      jumpTo: null,
    };
  }

  if (!days.includes(date)) {
    const next = nextDayWithWork(days, date);
    const prev = prevDayWithWork(days, date);
    const jumpTo = next ?? prev;
    const direction = next ? 'Next' : 'Last';
    return {
      reason: 'other_days',
      headline: isToday ? 'Nothing scheduled for you today.' : `Nothing scheduled for ${formatDayLabel(date)}.`,
      detail: jumpTo
        ? `${direction} work: ${formatDayLabel(jumpTo)}.`
        : 'Your published work is on other days.',
      jumpTo,
    };
  }

  return {
    reason: 'empty_day',
    headline: isToday ? 'Nothing left for today.' : `Nothing left for ${formatDayLabel(date)}.`,
    detail: 'This day was published, but none of its work is showing. If that looks wrong, say so — it should not happen.',
    jumpTo: nextDayWithWork(days, date),
  };
}
