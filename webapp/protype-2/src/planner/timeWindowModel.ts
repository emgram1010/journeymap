// TW-1 — A job's time window: when this piece of work is allowed to happen.
// Plan-local date + HH:MM, no timezone (D-4); may cross midnight. V1 warns,
// never blocks (D-2). The server re-checks every rule (D-6) with the same
// codes, in apis/planner/*_work-item_work_item_id_time-window_PUT.xs.

export interface TimeWindow {
  start_date: string;
  start_time: string;
  end_date: string;
  end_time: string;
  note?: string | null;
}

export type WindowField = 'start_date' | 'start_time' | 'end_date' | 'end_time' | 'note';

export type WindowCheck =
  | {ok: true}
  | {ok: false; code: 'E-TW-001' | 'E-TW-002' | 'E-TW-003' | 'E-TW-006'; field: WindowField; message: string};

export const NOTE_MAX = 200;

const TIME_RE = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
const DATE_RE = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export function validateWindow(
  w: TimeWindow,
  plan?: {start: string | null; end: string | null},
): WindowCheck {
  for (const f of ['start_date', 'end_date'] as const) {
    if (!DATE_RE.test(w[f] ?? '')) {
      return {ok: false, code: 'E-TW-001', field: f, message: 'Enter a start and end date, and times as two digits each, like 09:00.'};
    }
  }
  for (const f of ['start_time', 'end_time'] as const) {
    if (!TIME_RE.test(w[f] ?? '')) {
      return {ok: false, code: 'E-TW-001', field: f, message: 'Enter a start and end date, and times as two digits each, like 09:00.'};
    }
  }
  // Fixed-width strings, so text order is time order — same as the server.
  if (`${w.end_date} ${w.end_time}` <= `${w.start_date} ${w.start_time}`) {
    return {ok: false, code: 'E-TW-002', field: 'end_time', message: 'The window has to end after it starts.'};
  }
  if (plan?.start && plan?.end && (w.end_date < plan.start || w.start_date > plan.end)) {
    return {
      ok: false,
      code: 'E-TW-003',
      field: 'start_date',
      message: `This time window falls completely outside the plan (${plan.start} to ${plan.end}). Move it so at least part of it is inside.`,
    };
  }
  if ((w.note ?? '').trim().length > NOTE_MAX) {
    return {ok: false, code: 'E-TW-006', field: 'note', message: `Keep the time window's note to ${NOTE_MAX} characters or fewer.`};
  }
  return {ok: true};
}

/** Date-only on purpose: the derived slot start moves on every reorder and would make the warning flicker. */
export function isPlacementOutsideWindow(w: TimeWindow | null | undefined, plannedDate: string | null | undefined): boolean {
  if (!w || !plannedDate) return false;
  return plannedDate < w.start_date || plannedDate > w.end_date;
}

function shortDate(iso: string): string {
  const [, m, d] = iso.split('-');
  return `${Number(d)} ${MONTHS[Number(m) - 1] ?? ''}`;
}

export function formatWindow(w: TimeWindow | null | undefined): string {
  if (!w) return '';
  if (w.start_date === w.end_date) return `${w.start_time}–${w.end_time}, ${shortDate(w.start_date)}`;
  return `${shortDate(w.start_date)} ${w.start_time} – ${shortDate(w.end_date)} ${w.end_time}`;
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** PUX-1 — "Wed 4 Nov". Plan-local date, so read as UTC to avoid a timezone shift. */
export function formatDayShort(iso: string): string {
  if (!DATE_RE.test(iso)) return iso;
  const d = new Date(`${iso}T00:00:00Z`);
  return `${WEEKDAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

function addDays(iso: string, n: number): string {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** PUX-2 — every calendar day the window touches, clipped to the plan when it has dates. */
export function daysInsideWindow(w: TimeWindow | null | undefined, planStart: string | null, planEnd: string | null): string[] {
  if (!w || !DATE_RE.test(w.start_date) || !DATE_RE.test(w.end_date)) return [];
  const from = planStart && planStart > w.start_date ? planStart : w.start_date;
  const to = planEnd && planEnd < w.end_date ? planEnd : w.end_date;
  const days: string[] = [];
  for (let day = from; day <= to && days.length < 366; day = addDays(day, 1)) days.push(day);
  return days;
}

/** PUX-2 — sort by soonest window end; jobs with no window go last. */
export function compareByWindow(a: TimeWindow | null | undefined, b: TimeWindow | null | undefined): number {
  if (!a && !b) return 0;
  if (!a) return 1;
  if (!b) return -1;
  return `${a.end_date} ${a.end_time}`.localeCompare(`${b.end_date} ${b.end_time}`);
}

/** PUX-2 — what a window chip looks like, given the days the job's slots sit on. */
export function windowChipState(w: TimeWindow | null | undefined, placedDays: ReadonlyArray<string>): 'none' | 'fine' | 'outside' {
  if (!w) return 'none';
  return placedDays.some((d) => isPlacementOutsideWindow(w, d)) ? 'outside' : 'fine';
}

/** US-TW-1-03 — the plan's windows, read once (`GET workspace/{id}/time-windows`) and looked up by job. */
export function indexWindowsByJob<T extends TimeWindow & {work_item_id: number}>(windows: ReadonlyArray<T>): Map<number, T> {
  const map = new Map<number, T>();
  for (const w of windows) map.set(w.work_item_id, w);
  return map;
}
