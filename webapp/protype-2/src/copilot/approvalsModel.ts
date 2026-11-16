// COP-2 — pure logic for the Approvals screens. The server is the authority and refuses again;
// this only lets the screen explain things before the round trip.

export type Level = 'own' | 'tell' | 'wait';

export const LEVEL_LABELS: Record<Level, string> = {
  own: 'Runs on its own',
  tell: 'Runs, then tells you',
  wait: 'Waits for you',
};

export const TOUCHES_LABELS: Record<string, string> = {
  internal: 'Stays inside the business',
  customer: 'Reaches a customer',
  booking: 'Changes a booking',
  money: 'Moves money',
};

/**
 * COP-2 story 04 - which done items can really be undone from the Approvals screen. Mirrors
 * POST copilot/action_undo (661): today only a note the copilot saved; a work update lives in the
 * append-only activity log and is changed on the task instead. No false Undo.
 */
export const UNDOABLE_TYPES = new Set(['note_internal']);
export const CHANGE_WHERE_IT_LIVES = "Can't be undone here - change it on the task itself";

export type UndoState =
  | {kind: 'cannot'; label: string}
  | {kind: 'undone'; label: string}
  | {kind: 'undo'; label: string};

export function undoState(t: {reversible: boolean; action_type?: string | null; status?: string | null; reason?: string | null}): UndoState {
  if (!t.reversible) return {kind: 'cannot', label: "Can't be undone"};
  if ((t.reason ?? '').startsWith('Undone')) return {kind: 'undone', label: 'Undone'};
  const done = t.status === 'told' || t.status === 'seen' || t.status === 'executed';
  if (done && UNDOABLE_TYPES.has(t.action_type ?? '')) return {kind: 'undo', label: 'Undo'};
  return {kind: 'cannot', label: CHANGE_WHERE_IT_LIVES};
}

/** Mirror of the server rule in copilot/level_set (E-COP-026). */
export function levelChangeNeedsConfirm(x: {reversible: boolean; touches: string; level: string}): boolean {
  return x.reversible === false && x.touches !== 'internal' && x.level !== 'wait';
}

/**
 * Final review R12: switching scheduled work ON lets the copilot act every hour with nobody at the
 * screen, so the screen asks once. Screen-only: the server needs no extra flag for it.
 */
export function scheduledWorkTurnsOn(key: string, from: string, to: string): boolean {
  return key === 'scheduled_work' && from === 'wait' && to !== 'wait';
}

export function limitProblem(text: string, hasLimit: boolean): string | null {
  if (!hasLimit) return null;
  if (!/^\d+$/.test(text.trim())) return 'Enter a whole number, 0 or more.';
  return null;
}

export function prettyPayload(p: unknown): string {
  if (p == null) return '';
  if (typeof p === 'string') return p;
  try {
    return JSON.stringify(p, null, 2);
  } catch {
    return String(p);
  }
}

export function parseEditedPayload(text: string): {ok: true; value: unknown} | {ok: false; message: string} {
  if (text.trim() === '') return {ok: false, message: 'Add your edited version before sending it.'};
  try {
    return {ok: true, value: JSON.parse(text)};
  } catch {
    return {ok: false, message: "That isn't valid JSON yet. Check the brackets, quotes and commas. Your text is kept."};
  }
}

const STATUS_LABELS: Record<string, string> = {
  told: 'Done, then told you',
  seen: 'Seen',
  approved: 'Approved',
  edited: 'Approved with your edits',
  executed: 'Done',
  rejected: 'Rejected',
  expired: 'Expired',
  failed: 'Failed',
};

export function statusLabel(status: string): string {
  return STATUS_LABELS[status] ?? status;
}

export const isNewlyTold = (status: string) => status === 'told';

/** Plain names for action types, mirroring copilot/action_types (the server's one catalogue). Unknown keys show as-is. */
export const ACTION_TYPE_LABELS: Record<string, string> = {
  map_read: 'Read maps and plans',
  map_draft: 'Edit draft maps',
  map_publish_version: 'Publish a map version',
  plan_draft: 'Draft a plan',
  plan_live_change: 'Change a day that is already live',
  plan_publish_live: 'Publish a plan to live',
  note_internal: 'Write an internal note',
  work_update: 'Update assigned work',
  work_complete: 'Mark its own work done or skipped',
  customer_message: 'Send a message to a customer',
  booking_change: 'Create or change a booking',
  money_payment: 'Charge, pay or refund money',
  scheduled_work: 'Work on its tasks on a schedule, with nobody at the screen',
};

export const actionTypeLabel = (key: string | null | undefined): string =>
  key ? ACTION_TYPE_LABELS[key] ?? key : '';
