// EXC-1 (US-EXC-1-06) — The rules behind the "Send to…" sheet, kept pure
// so they can be tested without a browser. The sheet is the same for the
// performer (on a step) and the planner (on a job).
//
// The server always validates again (endpoint 610); these checks only
// stop an obviously doomed tap and say why, in the same words and codes
// the server would use. The user's typing is never cleared by a refusal.

export const REASON_CODES = ['waiting_on_someone', 'missing_information', 'something_went_wrong', 'other'] as const;
export type ReasonCode = (typeof REASON_CODES)[number];

export const REASON_LABELS: Record<ReasonCode, string> = {
  waiting_on_someone: 'Waiting on someone',
  missing_information: 'Missing information',
  something_went_wrong: 'Something went wrong',
  other: 'Other',
};

export const NOTE_MAX = 500;

/** One row of `exceptions/job_links.send_options`, returned by GET work_item/{id}. */
export interface SendOption {
  work_task_id: number;
  stage_key: string;
  stage_label: string;
  target_map_id: number;
  target_map_title: string;
  published: boolean;
}

/** One of the job's order lines, as the sheet shows it. */
export interface SheetLine {
  item_type_id: number;
  label: string;
  quantity: number;
}

export interface SheetState {
  targetMapId: number | null;
  reasonCode: string;
  note: string;
  /** item_type_id → how many to send (0 = stays). */
  counts: Record<number, number>;
  /** "This step is stuck until it's resolved" — off by default (D-1). */
  blockParent: boolean;
}

export interface SheetProblem {
  code: 'E-EXC-003' | 'E-EXC-006' | 'E-EXC-010' | 'E-EXC-011';
  message: string;
}

/** This step's targets, published ones first (an unpublished one is shown, disabled). */
export function optionsForStep(options: readonly SendOption[], workTaskId: number): SendOption[] {
  return options
    .filter((o) => o.work_task_id === workTaskId)
    .sort((a, b) => Number(b.published) - Number(a.published));
}

export function emptySheet(stepOptions: readonly SendOption[], lines: readonly SheetLine[]): SheetState {
  const published = stepOptions.filter((o) => o.published);
  return {
    targetMapId: published.length === 1 ? published[0].target_map_id : null,
    reasonCode: '',
    note: '',
    counts: Object.fromEntries(lines.map((l) => [l.item_type_id, 0])),
    blockParent: false,
  };
}

/** The stepper's own bound: a whole number from 0 to the line's quantity. */
export function clampCount(value: number, max: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.min(max, Math.max(0, Math.floor(value)));
}

const HTML_TAG = /<[a-zA-Z][^>]*>/;

export function validateSheet(
  state: SheetState,
  lines: readonly SheetLine[],
  stepOptions: readonly SendOption[],
): SheetProblem | null {
  const target = stepOptions.find((o) => o.target_map_id === state.targetMapId);
  if (target && !target.published) {
    return {code: 'E-EXC-003', message: `${target.target_map_title} hasn't been published yet. Publish it, then try again.`};
  }
  if (!(REASON_CODES as readonly string[]).includes(state.reasonCode)) {
    return {code: 'E-EXC-010', message: 'Pick a reason.'};
  }
  if (state.note.trim().length > NOTE_MAX || HTML_TAG.test(state.note)) {
    return {code: 'E-EXC-011', message: 'Keep the note under 500 characters, with no HTML.'};
  }
  for (const line of lines) {
    const n = state.counts[line.item_type_id] ?? 0;
    if (!Number.isInteger(n) || n < 0 || n > line.quantity) {
      return {code: 'E-EXC-006', message: `Enter how many to send, from 1 to ${line.quantity}.`};
    }
  }
  return null;
}

export function buildExceptionRequest(state: SheetState, correlationId: string) {
  const note = state.note.trim();
  return {
    target_map_id: state.targetMapId ?? 0,
    reason_code: state.reasonCode,
    ...(note !== '' ? {note} : {}),
    lines: Object.entries(state.counts)
      .filter(([, n]) => n > 0)
      .map(([id, n]) => ({item_type_id: Number(id), quantity: n})),
    also_block_parent: state.blockParent,
    correlation_id: correlationId,
  };
}

export function sentToast(targetTitle: string, childId: number, moved: readonly {label: string; quantity: number}[]): string {
  if (moved.length === 0) return `Sent to ${targetTitle} (#${childId})`;
  if (moved.length === 1) return `Sent ${moved[0].quantity} ${moved[0].label} to ${targetTitle} (#${childId})`;
  return `Sent ${moved.reduce((n, m) => n + m.quantity, 0)} items to ${targetTitle} (#${childId})`;
}

/** E-EXC-013: this sheet's request was already saved (a retry after a lost response). */
export function isAlreadySent(message: string): boolean {
  return message.includes('(E-EXC-013)');
}
