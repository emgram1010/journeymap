// REPEAT-1 story 06 — the screen's side of "repeat for several periods".
//
// The server (repeat/list_periods) decides every period's dates and name and which ones already
// exist; each period is then made by its own request (POST workspace/{id}/repeat), which is its
// own all-or-nothing write. This file only runs them in order and describes what happened in plain
// words. A failed period never undoes one that was already made, and the periods after it are not
// tried. Pure functions plus one small sequential runner; no network of its own.

export const MAX_PERIODS = 8;

export interface RepeatPeriod {
  n: number;
  start_date: string;
  end_date: string;
  shift_days: number;
  weekdays_align: boolean;
  name: string;
  exists: boolean;
  existing_workspace_id: number;
}

export type PeriodsCheck = {ok: true} | {ok: false; code: 'E-REPEAT-010'; message: string};

/** The same limit the server applies (E-REPEAT-010), so a bad number is caught before a round trip. */
export const validatePeriodCount = (n: number): PeriodsCheck =>
  Number.isInteger(n) && n >= 1 && n <= MAX_PERIODS
    ? {ok: true}
    : {ok: false, code: 'E-REPEAT-010', message: `You can repeat a plan for 1 to ${MAX_PERIODS} periods at a time.`};

export interface CreateAnswer {
  outcome: 'created' | 'exists';
  workspace_id: number;
  existing_workspace_id: number;
}

export type CreateOne = (period: RepeatPeriod) => Promise<CreateAnswer>;

export type PeriodStatus = 'created' | 'skipped' | 'failed' | 'not_attempted';

export interface PeriodOutcome {
  n: number;
  name: string;
  start_date: string;
  status: PeriodStatus;
  /** The plan made (created) or the plan that was already there (skipped). Absent for failed / not attempted. */
  workspace_id?: number;
  message?: string;
}

const failureText = (err: unknown): string => {
  const msg = (err as {message?: unknown} | null)?.message;
  return typeof msg === 'string' && msg.trim() !== '' ? msg : "This period couldn't be made. Nothing was saved for it.";
};

/**
 * Makes each period in order, one request each. A period that already exists is skipped without a
 * request. The first failure stops the run: the periods before it stay, it leaves nothing, and the
 * rest are reported as not tried.
 */
export const runPeriods = async (periods: RepeatPeriod[], createOne: CreateOne): Promise<PeriodOutcome[]> => {
  const out: PeriodOutcome[] = [];
  let stopped = false;
  for (const p of periods) {
    const base = {n: p.n, name: p.name, start_date: p.start_date};
    if (stopped) {
      out.push({...base, status: 'not_attempted'});
      continue;
    }
    if (p.exists) {
      out.push({...base, status: 'skipped', workspace_id: p.existing_workspace_id});
      continue;
    }
    try {
      const a = await createOne(p);
      out.push(
        a.outcome === 'created'
          ? {...base, status: 'created', workspace_id: a.workspace_id}
          : {...base, status: 'skipped', workspace_id: a.existing_workspace_id},
      );
    } catch (err) {
      out.push({...base, status: 'failed', message: failureText(err)});
      stopped = true;
    }
  }
  return out;
};

export const outcomeCounts = (outcomes: PeriodOutcome[]) => ({
  created: outcomes.filter(o => o.status === 'created').length,
  skipped: outcomes.filter(o => o.status === 'skipped').length,
  failed: outcomes.filter(o => o.status === 'failed').length,
  notAttempted: outcomes.filter(o => o.status === 'not_attempted').length,
});

/** One plain line per period. */
export const outcomeLine = (o: PeriodOutcome): string => {
  switch (o.status) {
    case 'created':
      return `${o.name} · made`;
    case 'skipped':
      return `${o.name} · already made earlier, left as it is`;
    case 'failed':
      return `${o.name} · could not be made, nothing was saved for it${o.message ? `: ${o.message}` : ''}`;
    default:
      return `${o.name} · not tried, because an earlier period failed`;
  }
};

export interface RepeatedFrom {
  workspace_id: number;
  name: string;
  exists: boolean;
}

export interface RepeatedTo {
  workspace_id: number;
  name: string;
  start_date: string;
  end_date: string;
  needs_review: number;
}

/** Where a plan came from. Empty when it was not made by a repeat; a deleted source gets its own wording. */
export const repeatedFromText = (from: RepeatedFrom | null): string => {
  if (!from) return '';
  return from.exists ? `Repeated from ${from.name}` : 'Repeated from a plan that no longer exists';
};

/** One line for a plan made from this one, with what still needs a look. */
export const repeatedToLine = (to: RepeatedTo): string =>
  `${to.name} · ${to.start_date} to ${to.end_date}${to.needs_review > 0 ? ` · ${to.needs_review} to review` : ''}`;
