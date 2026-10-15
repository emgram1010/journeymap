// LOG-1 (US-LOG-1-02, -04) — The status engine.
//
// THE MOST IMPORTANT RULES IN THE PRODUCT live here. A task's status
// is not something anyone sets directly; it is the result of applying
// events to the fixed transition table below. Replaying a task's log
// must always reproduce its stored status — that equality is what
// makes the record trustworthy, and GOV-1's daily audit checks it.
//
// The statuses are fixed (architecture rules): `not_started`,
// `in_progress`, `blocked`, `done`, `skipped`. There is no `paused`
// (D-17) and no `complete/delayed/novel_exception` from the earlier
// initiative (D-39).

export type TaskStatus = 'not_started' | 'in_progress' | 'blocked' | 'done' | 'skipped';

export type EventType =
  | 'started'
  | 'completed'
  | 'blocked'
  | 'unblocked'
  | 'skipped'
  | 'reopened'
  | 'note';

export type ReasonCode =
  | 'waiting_on_someone'
  | 'missing_information'
  | 'something_went_wrong'
  | 'other';

export const REASON_CODES: ReasonCode[] = [
  'waiting_on_someone',
  'missing_information',
  'something_went_wrong',
  'other',
];

/**
 * The whole transition table, exactly as the epic states it.
 *
 * `note` is deliberately absent: it is allowed from ANY status and
 * changes nothing, which is handled in `canTransition` rather than by
 * repeating it on every row.
 *
 * NOTE THE `not_started → completed` ROW. Done is allowed without
 * Start (D-38). People finish things without remembering to press
 * Start, and refusing that would push them to fake a start time,
 * which is worse than an honestly unknown one. VAR-1 reports the
 * actual time as unknown and flags it rather than guessing.
 */
const TRANSITIONS: ReadonlyArray<{from: TaskStatus; event: EventType; to: TaskStatus}> = [
  {from: 'not_started', event: 'started', to: 'in_progress'},
  {from: 'not_started', event: 'blocked', to: 'blocked'},
  {from: 'not_started', event: 'skipped', to: 'skipped'},
  {from: 'not_started', event: 'completed', to: 'done'},
  {from: 'in_progress', event: 'completed', to: 'done'},
  {from: 'in_progress', event: 'blocked', to: 'blocked'},
  {from: 'in_progress', event: 'skipped', to: 'skipped'},
  {from: 'blocked', event: 'unblocked', to: 'in_progress'},
  {from: 'blocked', event: 'skipped', to: 'skipped'},
  {from: 'done', event: 'reopened', to: 'in_progress'},
  {from: 'skipped', event: 'reopened', to: 'in_progress'},
];

export interface TransitionResult {
  allowed: boolean;
  /** The resulting status. For `note`, the status is unchanged. */
  to: TaskStatus | null;
  /** Why it was refused, as a code the catalog explains. */
  code?: 'E-LOG-001' | 'E-LOG-002' | 'E-LOG-005';
}

/**
 * May this event be applied to a task in this status, and what does
 * it become?
 *
 * A `blocked` event REQUIRES a reason. "Blocked" with no explanation
 * is worse than not flagging it at all: the planner sees a problem
 * and has nothing to act on.
 */
export function canTransition(
  from: TaskStatus,
  event: EventType,
  reasonCode?: ReasonCode | string | null,
): TransitionResult {
  if (event === 'note') {
    // A note never changes anything, from any status.
    return {allowed: true, to: from};
  }

  if (event === 'blocked') {
    if (!reasonCode) return {allowed: false, to: null, code: 'E-LOG-002'};
    if (!REASON_CODES.includes(reasonCode as ReasonCode)) {
      return {allowed: false, to: null, code: 'E-LOG-005'};
    }
  }

  const row = TRANSITIONS.find((t) => t.from === from && t.event === event);
  if (!row) return {allowed: false, to: null, code: 'E-LOG-001'};

  return {allowed: true, to: row.to};
}

export interface LoggedEvent {
  event_type: EventType;
  occurred_at: number;
  reason_code?: ReasonCode | null;
}

export interface ReplayResult {
  status: TaskStatus;
  /** First start ever recorded, or null if the task was never started. */
  started_at: number | null;
  /** Completion time, or null when not currently complete. */
  completed_at: number | null;
  /** Events that were not valid from the status at the time. */
  rejected: number[];
}

/**
 * Rebuild a task's state from its log.
 *
 * THIS IS THE DEFINITION OF TRUTH. `work_task.status` is a cache of
 * this result; if the two ever disagree, this one is right and the
 * row has been tampered with or a write went wrong. The daily audit
 * compares them.
 *
 * `started_at` is the FIRST start, kept across reopen/complete cycles
 * (UT-LOG-1-05): a task reopened and finished again was still started
 * when it was first started, and overwriting that would quietly erase
 * how long the work really spanned.
 *
 * Events invalid from the status at the time are skipped and their
 * indexes reported, rather than throwing — a replay must survive bad
 * history in order to be able to report it.
 */
export function replay(events: ReadonlyArray<LoggedEvent>): ReplayResult {
  let status: TaskStatus = 'not_started';
  let startedAt: number | null = null;
  let completedAt: number | null = null;
  const rejected: number[] = [];

  events.forEach((e, index) => {
    const result = canTransition(status, e.event_type, e.reason_code);
    if (!result.allowed) {
      rejected.push(index);
      return;
    }

    switch (e.event_type) {
      case 'started':
        if (startedAt === null) startedAt = e.occurred_at;
        break;
      case 'completed':
      case 'skipped':
        completedAt = e.occurred_at;
        break;
      case 'reopened':
        // Reopening undoes the completion but never the original start.
        completedAt = null;
        break;
      default:
        break;
    }

    status = result.to as TaskStatus;
  });

  return {status, started_at: startedAt, completed_at: completedAt, rejected};
}

export type StageRule = 'all_required_done' | 'any_done' | 'manual';

/**
 * Is a stage finished?
 *
 * The MVP uses `all_required_done` only; the other two arrive with
 * STAGE-1's deferred completion rules and are implemented here so the
 * caller does not change later.
 *
 * `manual` NEVER auto-advances, by definition — a stage someone has
 * to sign off is not finished just because its tasks are.
 * An empty stage is not complete under any rule: there is nothing to
 * have finished, and calling it done would advance a stage that was
 * never worked.
 */
export function stageComplete(
  rule: StageRule,
  tasks: ReadonlyArray<{status: TaskStatus}>,
): boolean {
  if (rule === 'manual') return false;
  if (tasks.length === 0) return false;

  const isFinished = (s: TaskStatus) => s === 'done' || s === 'skipped';

  if (rule === 'any_done') return tasks.some((t) => t.status === 'done');
  return tasks.every((t) => isFinished(t.status));
}

/**
 * The friendly sentence for a refused action.
 *
 * Says what state the step is actually in and what to do instead,
 * because "not allowed" on its own leaves someone stuck holding a
 * phone.
 */
export function transitionMessage(from: TaskStatus, event: EventType): string {
  const plain: Record<TaskStatus, string> = {
    not_started: 'not started yet',
    in_progress: 'already in progress',
    blocked: 'blocked',
    done: 'already done',
    skipped: 'skipped',
  };

  if (from === 'done' || from === 'skipped') {
    return `This step is ${plain[from]}. Reopen it first if you need to change it.`;
  }
  if (from === 'blocked') {
    return 'This step is blocked. Unblock it first.';
  }
  if (from === 'in_progress' && event === 'started') {
    return 'This step is already in progress.';
  }
  return `This step is ${plain[from]}, so that action isn't available.`;
}
