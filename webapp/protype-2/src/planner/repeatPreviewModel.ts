// REPEAT-1 story 01 — the screen's side of "preview a repeat".
//
// The server decides what a repeat copies (functions/repeat/build_plan.xs); nothing here
// re-decides it. This file holds only what the screen needs: the same date rules, so a bad date
// is caught before a round trip (the server checks again), and plain wording for each verdict.
// Pure functions, no network.

export type RepeatVerdict = 'repeat' | 'left_out' | 'will_not_repeat' | 'cannot_repeat';

export interface RepeatJob {
  id: number;
  title: string;
  status: string;
  verdict: RepeatVerdict;
  reason: string;
  uses_newer_version: boolean;
  map_id: number;
  map_title: string;
  from_version_id: number;
  to_version_id: number;
  to_version_no: number;
  steps: number;
}

export interface RepeatPerson {
  agent_id: number;
  name: string;
  kind: string;
  left_off: boolean;
  slots_to_backlog: number;
}

export interface RepeatCounts {
  people: number;
  people_left_off: number;
  days: number;
  jobs: number;
  jobs_left_out: number;
  jobs_will_not: number;
  jobs_cannot: number;
  jobs_newer: number;
  steps: number;
  slots: number;
  slots_to_backlog: number;
  backlog: number;
  slots_dropped: number;
  row_estimate: number;
}

export interface RepeatPreview {
  source: {id: number; name: string; start_date: string; end_date: string; length_days: number; is_archived: boolean};
  offer: {start_date: string; end_date: string; shift_days: number; weekdays_align: boolean; name: string; name_is_free: boolean};
  counts: RepeatCounts;
  people: RepeatPerson[];
  jobs: RepeatJob[];
}

const DAY_MS = 86_400_000;
const ISO_DATE = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

/** A YYYY-MM-DD string as UTC milliseconds, or null when it is not a real day. */
const toMs = (iso: string): number | null => {
  if (!ISO_DATE.test(iso)) return null;
  const ms = Date.parse(`${iso}T00:00:00Z`);
  if (Number.isNaN(ms)) return null;
  // 2027-02-31 parses in some engines by rolling over; the round trip refuses it.
  return new Date(ms).toISOString().slice(0, 10) === iso ? ms : null;
};

const toIso = (ms: number): string => new Date(ms).toISOString().slice(0, 10);

/** The day after the source plan ends. */
export const defaultRepeatStart = (sourceEnd: string): string => {
  const ms = toMs(sourceEnd);
  return ms === null ? '' : toIso(ms + DAY_MS);
};

/** Whole days from the source start to the new start. */
export const shiftDays = (sourceStart: string, newStart: string): number => {
  const a = toMs(sourceStart);
  const b = toMs(newStart);
  return a === null || b === null ? 0 : Math.round((b - a) / DAY_MS);
};

/** True when Monday's work stays on a Monday. */
export const weekdaysAlign = (sourceStart: string, newStart: string): boolean =>
  shiftDays(sourceStart, newStart) % 7 === 0;

/** True when the new window (same length as the source) would share a day with the source. */
export const windowOverlaps = (sourceStart: string, sourceEnd: string, newStart: string): boolean => {
  const s = toMs(sourceStart);
  const e = toMs(sourceEnd);
  const n = toMs(newStart);
  if (s === null || e === null || n === null) return false;
  const newEnd = n + (e - s);
  return n <= e && newEnd >= s;
};

export type StartDateCheck = {ok: true} | {ok: false; code: 'E-REPEAT-002' | 'E-REPEAT-003'; message: string};

/** The same two refusals the server makes, with the same codes. */
export const validateStartDate = (newStart: string, sourceStart: string, sourceEnd: string): StartDateCheck => {
  if (toMs(newStart) === null) {
    return {ok: false, code: 'E-REPEAT-002', message: 'Pick a start date for the new plan.'};
  }
  if (windowOverlaps(sourceStart, sourceEnd, newStart)) {
    return {ok: false, code: 'E-REPEAT-003', message: 'The new plan would overlap this one. Pick a start date after this plan ends.'};
  }
  return {ok: true};
};

/** Only a job that would repeat, or one the planner unticked, has a working tick box. */
export const canTick = (job: RepeatJob): boolean => job.verdict === 'repeat' || job.verdict === 'left_out';

export const toggleSkip = (skipIds: number[], jobId: number): number[] =>
  skipIds.includes(jobId) ? skipIds.filter(id => id !== jobId) : [...skipIds, jobId];

const REASONS: Record<string, string> = {
  outside_order: 'It came from a customer order, so it is a one-off.',
  exception_child: 'It was created by an exception on another job.',
  cancelled: 'It was cancelled.',
  map_unavailable: 'Its map was archived or deleted.',
  no_published_version: 'Its map has no published version.',
  left_out: 'You chose to leave it out.',
};

/** Plain wording for a reason. An unknown reason never shows its raw code. */
export const reasonText = (reason: string): string => {
  if (reason === '') return '';
  return REASONS[reason] ?? 'It cannot be repeated.';
};

export const groupJobs = (jobs: RepeatJob[]) => ({
  repeat: jobs.filter(j => j.verdict === 'repeat'),
  newer: jobs.filter(j => j.verdict === 'repeat' && j.uses_newer_version),
  leftOut: jobs.filter(j => j.verdict === 'left_out'),
  willNot: jobs.filter(j => j.verdict === 'will_not_repeat'),
  cannot: jobs.filter(j => j.verdict === 'cannot_repeat'),
});

export const peopleLeftOff = (people: RepeatPerson[]) =>
  people
    .filter(p => p.left_off)
    .map(p => ({agent_id: p.agent_id, name: p.name.trim() === '' ? 'Unnamed person' : p.name, slots_to_backlog: p.slots_to_backlog}));

const plural = (n: number, one: string, many: string): string => `${n} ${n === 1 ? one : many}`;

/** What will be in the new plan, as short lines. Slots moved off a left-off person count as backlog. */
export const summaryLines = (c: RepeatCounts): string[] => [
  plural(c.people, 'person', 'people'),
  plural(c.days, 'day', 'days'),
  plural(c.jobs, 'job', 'jobs'),
  plural(c.slots, 'scheduled slot', 'scheduled slots'),
  plural(c.backlog + c.slots_to_backlog, 'backlog item', 'backlog items'),
];

export const capList = <T>(items: T[], cap: number): {shown: T[]; more: number} => ({
  shown: items.slice(0, cap),
  more: Math.max(0, items.length - cap),
});

/**
 * The "Repeat this plan" action stays hidden until the copy itself is built (stories 02-04), so
 * nobody presses a button that does nothing. Set VITE_REPEAT_PLAN_UI=1 to see the preview.
 */
export const isRepeatPlanUiEnabled = (): boolean => {
  try {
    return import.meta.env?.VITE_REPEAT_PLAN_UI === '1';
  } catch {
    return false;
  }
};
