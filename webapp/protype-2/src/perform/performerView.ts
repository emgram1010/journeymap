// APP-1 (US-APP-1-03, -04) — Pure view logic for the performer app.
//
// No imports, same discipline as logModel.ts/jobModel.ts: everything
// here is a plain function over plain data, testable without a server,
// a DOM, or a browser. The component that renders the screen is a thin
// wrapper around these.
//
// THE SPLIT THIS FILE DEPENDS ON: `PerformerSnapshot` is WHAT WAS
// PLANNED — the frozen publication, never touched after publish
// (LIVE-1, D-23). `StatusMap` is WHAT'S HAPPENING NOW — live
// `work_task` rows, keyed by id. toPerformerItems merges the two on
// read; neither one is ever written back into the other. An item
// whose planner_task has since been deleted from the live plan is
// still in the snapshot and is still returned (US-APP-1-02's own
// acceptance: "moved/removed tasks still show as published").

export type TaskStatus = 'not_started' | 'in_progress' | 'blocked' | 'done' | 'skipped';

/** TW-1 — same shape as planner/timeWindowModel.ts's TimeWindow, duplicated rather than imported: this file has no imports by design (see header). */
export interface TimeWindow {
  start_date: string;
  start_time: string;
  end_date: string;
  end_time: string;
  note?: string | null;
}

/** The five one-tap actions a performer can take, per the epic's fixed table. */
export type PerformerAction = 'start' | 'done' | 'blocked' | 'skip' | 'unblock' | 'reopen';

/**
 * Which actions are available from a status. Matches
 * `logModel.ts::canTransition`'s allowed set exactly — this is the
 * same rule stated as "what buttons show" rather than "what's
 * allowed", because that's the question a screen actually asks.
 */
export function availableActions(status: TaskStatus): PerformerAction[] {
  switch (status) {
    case 'not_started':
      return ['start', 'done', 'blocked', 'skip'];
    case 'in_progress':
      return ['done', 'blocked', 'skip'];
    case 'blocked':
      return ['unblock', 'skip'];
    case 'done':
    case 'skipped':
      return ['reopen'];
  }
}

/**
 * EXEC-1 (US-EXEC-1-07) — which of `availableActions`' results is the
 * PRIMARY (filled/prominent) button for a status. `availableActions`
 * stays the source of truth for which actions exist at all (shared
 * with the backend's own transition table, pinned by UT-APP-1-01..04);
 * this only decides which one looks like the main action. `null` for
 * done/skipped — neither has a primary action, only Reopen.
 */
export function primaryAction(status: TaskStatus): PerformerAction | null {
  switch (status) {
    case 'not_started':
      return 'start';
    case 'in_progress':
      return 'done';
    case 'blocked':
      return 'unblock';
    case 'done':
    case 'skipped':
      return null;
  }
}

/**
 * EXEC-1 (US-EXEC-1-07) — true once a step has been running longer
 * than its expected minutes, for the Elapsed row's amber warning.
 * `startedAt` of `null` or `0` (never legitimately started) and a
 * missing `expectedMinutes` both read as "not over" — there is
 * nothing to compare against.
 */
export function isOverExpected(startedAt: number | null, now: number, expectedMinutes: number | null): boolean {
  if (!startedAt || expectedMinutes == null) return false;
  const elapsedMinutes = (now - startedAt) / 60000;
  return elapsedMinutes > expectedMinutes;
}

/**
 * EXEC-1 (US-EXEC-1-07/-09) — the "clock" value to measure a step's
 * elapsed time against: `completedAt` once finished, else the live
 * clock. Both `formatElapsed` and `isOverExpected` must be fed the
 * SAME value here, or they silently disagree — caught live (US-09): a
 * step shown as "Elapsed: 11 min" (correctly using `completedAt`) sat
 * next to an amber "over" (wrongly using the live clock), because a
 * long-finished step's real-world age kept growing after it was done.
 * Named and exported so there is exactly one place this decision is
 * made, not two call sites that have to happen to agree.
 */
export function elapsedClock(completedAt: number | null, now: number): number {
  return completedAt ?? now;
}

/** One item exactly as the frozen publication snapshot stored it (LIVE-1's build_publication shape, plus the owning timeline's own start_time — needed because planned start is never stored, only derived). */
export interface SnapshotItem {
  item_ref: string;
  planner_task_id: number;
  timeline_id: number;
  /** The owning timeline's `start_time`, "HH:MM" 24-hour. */
  timeline_start_time: string;
  /** Position within its OWN timeline. Only comparable within the same timeline_id. */
  seq: number;
  scheduled_minutes: number;
  assignee_agent_id: number;
  assignee_name: string;
  title: string;
  /** One task → one id. A "block" (grouped stages) → several. */
  work_task_ids: number[];
  /** TW-1 (US-TW-1-05) — the job's window, frozen at publish time. Null on an item with no window, or one published before TW-1 (v1 snapshot). */
  time_window: TimeWindow | null;
  /** SCHED-2 — the planner's manual start ("HH:MM"), frozen at publish time. "" or absent (pre-v3 snapshot) = none. */
  start_override?: string | null;
}

export interface PerformerSnapshot {
  date: string;
  items: SnapshotItem[];
}

/**
 * APP-2 (US-APP-2-01) — which job, which flow and which plan a step
 * belongs to. Added because the screen had no way to tell two jobs on
 * the same flow apart (review, 2026-10-17) — every field here is
 * sourced from the pinned version/job, same rule as `task`/`done_when`
 * above, never the live map or the live plan.
 */
export interface RawSessionInfo {
  work_item_id: number;
  title: string | null;
  flow_title: string | null;
  version_no: number | null;
  plan_id: number | null;
  plan_name: string | null;
}

/** APP-2 (US-APP-2-02) — one note, server-stamped, newest first as the API already orders them. */
export interface RawNote {
  note: string;
  occurred_at: number;
  author: string | null;
}

/** Live state for one work_task, plus the text hydrated from its pinned version — same hydration endpoint 555 already does for JOB-1. */
export interface WorkTaskStatusEntry {
  work_task_id: number;
  stage_key: string;
  lens_key: string;
  status: TaskStatus;
  started_at: number | null;
  completed_at: number | null;
  stage_label: string | null;
  lens_label: string | null;
  task: string | null;
  done_when: string | null;
  expected_minutes: number | null;
  /** EXEC-1 (US-EXEC-1-03) — the performer's display name, server-resolved from the step's latest completed/skipped event. Always null unless `status` is 'done' or 'skipped' (a reopened-then-not-yet-redone step reports no completer, not a stale name). */
  completed_by: string | null;
  session: RawSessionInfo | null;
  notes: RawNote[];
}

/** Keyed by `work_task_id`. */
export type StatusMap = Record<number, WorkTaskStatusEntry>;

/** camelCase twin of RawSessionInfo — same split as the rest of this file: snake_case off the wire, camelCase once parsed. */
export interface SessionInfo {
  workItemId: number;
  title: string | null;
  flowTitle: string | null;
  versionNo: number | null;
  planId: number | null;
  planName: string | null;
}

export interface PerformerNote {
  note: string;
  occurredAt: number;
  author: string | null;
}

export interface PerformerSubStep {
  workTaskId: number;
  stageKey: string;
  lensKey: string;
  status: TaskStatus;
  startedAt: number | null;
  completedAt: number | null;
  stageLabel: string | null;
  lensLabel: string | null;
  task: string | null;
  doneWhen: string | null;
  expectedMinutes: number | null;
  completedBy: string | null;
  session: SessionInfo | null;
  notes: PerformerNote[];
}

export interface PerformerItem {
  itemRef: string;
  plannerTaskId: number;
  title: string;
  assigneeAgentId: number;
  assigneeName: string;
  scheduledMinutes: number;
  /** Minutes after midnight, derived — never stored anywhere (see planner_task's own header comment). */
  plannedStartMinutes: number;
  /** "HH:MM" for display. */
  plannedStartLabel: string;
  /** One overall status for the block, derived from its sub-steps. */
  status: TaskStatus;
  subSteps: PerformerSubStep[];
  /** TW-1 (US-TW-1-05) — read-only; the performer never edits this (Q-1). */
  timeWindow: TimeWindow | null;
}

/** A status entry used when a work_task_id has no live row in the map yet (should not normally happen — work_task rows are never deleted — but a merge must degrade, not crash, on a sparse or stale join). */
export const FALLBACK_STATUS: Omit<WorkTaskStatusEntry, 'work_task_id'> = {
  stage_key: '',
  lens_key: '',
  status: 'not_started',
  started_at: null,
  completed_at: null,
  stage_label: null,
  lens_label: null,
  task: null,
  done_when: null,
  expected_minutes: null,
  completed_by: null,
  session: null,
  notes: [],
};

function parseHHMM(value: string): number {
  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!match) return 0;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  return hours * 60 + minutes;
}

function formatHHMM(totalMinutes: number): string {
  const clamped = ((totalMinutes % 1440) + 1440) % 1440; // wrap a day that runs past midnight rather than show a negative/garbled time
  const hours = Math.floor(clamped / 60);
  const minutes = clamped % 60;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

/**
 * SCHED-2 — the one start-time rule, "pin + flow". Walk the day in order:
 * a task with an override sets the clock to that time; every task starts
 * at the clock; the clock then advances by the task's minutes. With no
 * overrides this is exactly PLN-7's original rule.
 *
 * Twin of the server's `planner/start_minutes` — same golden cases
 * (UT-SCHED-2-G1..G5). Returns minutes after midnight, unwrapped.
 */
export function plannedStartsInOrder(
  dayStart: string,
  items: ReadonlyArray<{minutes: number; override?: string | null}>,
): number[] {
  let cursor = parseHHMM(dayStart);
  return items.map((item) => {
    if (item.override) cursor = parseHHMM(item.override);
    const start = cursor;
    cursor += item.minutes;
    return start;
  });
}

/**
 * Same precedence as `jobModel.ts::deriveJobStatus`, applied to a
 * block's sub-steps instead of a job's tasks: blocked wins outright,
 * then "every one finished" reads done, then "anything moving" reads
 * in_progress, else not_started. A single-task item is just the
 * degenerate case of a one-element block.
 */
export function deriveBlockStatus(subStatuses: TaskStatus[]): TaskStatus {
  if (subStatuses.length === 0) return 'not_started';
  if (subStatuses.some((s) => s === 'blocked')) return 'blocked';
  if (subStatuses.every((s) => s === 'done' || s === 'skipped')) return 'done';
  if (subStatuses.some((s) => s === 'in_progress' || s === 'done' || s === 'skipped')) return 'in_progress';
  return 'not_started';
}

/**
 * Merges the frozen snapshot with live status, derives each item's
 * planned start (grouped by timeline, walked in seq order from that
 * timeline's own start_time — never a single global clock, because
 * more than one plan can schedule the same performer on the same
 * day), and returns one flat, time-ordered list with each block's
 * sub-steps nested underneath it.
 *
 * Never drops an item. A sparse or stale `statuses` entry degrades to
 * a safe default rather than throwing — see US-APP-1-02's own
 * acceptance that moved/removed tasks still show as published.
 */
export function toPerformerItems(snapshot: PerformerSnapshot, statuses: StatusMap): PerformerItem[] {
  const byTimeline = new Map<number, SnapshotItem[]>();
  for (const item of snapshot.items) {
    const group = byTimeline.get(item.timeline_id);
    if (group) group.push(item);
    else byTimeline.set(item.timeline_id, [item]);
  }

  const withStart: Array<{item: SnapshotItem; plannedStartMinutes: number}> = [];

  for (const group of byTimeline.values()) {
    const ordered = [...group].sort((a, b) => a.seq - b.seq);
    const starts = plannedStartsInOrder(
      ordered.length > 0 ? ordered[0].timeline_start_time : '00:00',
      ordered.map((i) => ({minutes: i.scheduled_minutes, override: i.start_override})),
    );
    ordered.forEach((item, idx) => withStart.push({item, plannedStartMinutes: starts[idx]}));
  }

  const result: PerformerItem[] = withStart.map(({item, plannedStartMinutes}) => {
    const subSteps: PerformerSubStep[] = item.work_task_ids.map((id) => {
      const entry: WorkTaskStatusEntry = statuses[id] ?? {work_task_id: id, ...FALLBACK_STATUS};
      return {
        workTaskId: entry.work_task_id,
        stageKey: entry.stage_key,
        lensKey: entry.lens_key,
        status: entry.status,
        startedAt: entry.started_at,
        completedAt: entry.completed_at,
        stageLabel: entry.stage_label,
        lensLabel: entry.lens_label,
        task: entry.task,
        doneWhen: entry.done_when,
        expectedMinutes: entry.expected_minutes,
        completedBy: entry.completed_by,
        session: entry.session
          ? {
              workItemId: entry.session.work_item_id,
              title: entry.session.title,
              flowTitle: entry.session.flow_title,
              versionNo: entry.session.version_no,
              planId: entry.session.plan_id,
              planName: entry.session.plan_name,
            }
          : null,
        notes: entry.notes.map((n) => ({note: n.note, occurredAt: n.occurred_at, author: n.author})),
      };
    });

    return {
      itemRef: item.item_ref,
      plannerTaskId: item.planner_task_id,
      title: item.title,
      assigneeAgentId: item.assignee_agent_id,
      assigneeName: item.assignee_name,
      scheduledMinutes: item.scheduled_minutes,
      plannedStartMinutes,
      plannedStartLabel: formatHHMM(plannedStartMinutes),
      status: deriveBlockStatus(subSteps.map((s) => s.status)),
      subSteps,
      timeWindow: item.time_window,
    };
  });

  // Ties (same minute, different timelines) keep snapshot order —
  // Array.sort is stable, so this is deterministic without a second key.
  result.sort((a, b) => a.plannedStartMinutes - b.plannedStartMinutes);
  return result;
}

/**
 * One id per tap, so a retry on a bad connection is a duplicate
 * (LOG-1 de-dupes server-side) rather than a second event. Same
 * `crypto.randomUUID` pattern as `ops/correlationId.ts`, duplicated
 * rather than imported — this file stays dependency-free, like
 * logModel.ts and jobModel.ts, so it is testable with nothing but
 * `node --test`.
 */
export function newClientEventId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `evt-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

// ── Optimistic update + rollback (US-APP-1-04) ────────────────────────────

export type OptimisticAction =
  | {type: 'apply'; workTaskId: number; nextStatus: TaskStatus; at: number}
  | {type: 'confirm'; workTaskId: number; entry: WorkTaskStatusEntry}
  | {type: 'revert'; workTaskId: number; previous: WorkTaskStatusEntry};

/**
 * A pure reducer so the optimistic-update rule is one tested function,
 * not scattered through a component. `apply` guesses the new status
 * the instant a tap is sent; `confirm` replaces the guess with
 * whatever the server actually recorded (its own timestamps, not the
 * client's guess); `revert` puts back EXACTLY the entry captured
 * before the tap, so a failed save leaves no trace of the attempt.
 */
export function optimisticReducer(state: StatusMap, action: OptimisticAction): StatusMap {
  switch (action.type) {
    case 'apply': {
      const prior = state[action.workTaskId];
      const next: WorkTaskStatusEntry = {
        ...(prior ?? {work_task_id: action.workTaskId, ...FALLBACK_STATUS}),
        status: action.nextStatus,
        started_at: action.nextStatus === 'in_progress' && !prior?.started_at ? action.at : (prior?.started_at ?? null),
        completed_at: action.nextStatus === 'done' || action.nextStatus === 'skipped' ? action.at : (prior?.completed_at ?? null),
      };
      return {...state, [action.workTaskId]: next};
    }
    case 'confirm':
      return {...state, [action.workTaskId]: action.entry};
    case 'revert':
      return {...state, [action.workTaskId]: action.previous};
  }
}

// ── Offline state (EXEC-1 US-EXEC-1-08) ───────────────────────────────────

export type OfflineEvent = 'went_offline' | 'went_online';

/**
 * EXEC-1 (US-EXEC-1-08) — drives the top banner. A plain pure reducer
 * over `window`'s own `online`/`offline` events (the caller wires
 * those; this file never touches `window`, same discipline as the
 * rest of it). Idempotent: a repeated `went_offline` while already
 * offline is a no-op, same for `went_online`.
 */
export function offlineReducer(state: boolean, event: OfflineEvent): boolean {
  return event === 'went_offline';
}

// ── Friendly error mapping for a failed tap (US-APP-1-04, E-APP codes) ────

export interface AppErrorInfo {
  code: string;
  message: string;
}

const APP_MESSAGES: Record<string, string> = {
  'E-APP-001': 'No connection. Reconnect to continue. Your last tap was not saved.',
  'E-APP-002': "That didn't save. Tap again.",
  'E-APP-003': "You can't change this step.",
  'E-APP-004': 'Please sign in again.',
  'E-APP-005': "Something went wrong. We've recorded it.",
};

const EMBEDDED_CODE = /\(([A-Z]+-[A-Z]+-\d+)\)\s*$/;

/**
 * Turns whatever a failed tap produced into exactly one of the five
 * E-APP codes and a message a performer can read.
 *
 * A 400/422 from the record-event endpoint (LOG-1) is already a
 * friendly, specific sentence — VAL-1 requires it — so it is shown
 * AS IS rather than flattened into a generic "didn't save". Only the
 * shapes LOG-1 cannot explain (no connection, no session, not yours,
 * a dead server, anything unanticipated) get one of this file's own
 * generic sentences.
 */
export function mapActionError(input: {status?: number; serverMessage?: string | null; offline?: boolean}): AppErrorInfo {
  if (input.offline) {
    return {code: 'E-APP-001', message: APP_MESSAGES['E-APP-001']};
  }
  if (input.status === 401) {
    return {code: 'E-APP-004', message: APP_MESSAGES['E-APP-004']};
  }
  if (input.status === 403 || input.status === 404) {
    return {code: 'E-APP-003', message: APP_MESSAGES['E-APP-003']};
  }
  if ((input.status === 400 || input.status === 422) && input.serverMessage) {
    const embedded = EMBEDDED_CODE.exec(input.serverMessage);
    return {code: embedded?.[1] ?? 'E-APP-002', message: input.serverMessage};
  }
  if (input.status !== undefined && input.status >= 500) {
    return {code: 'E-APP-002', message: APP_MESSAGES['E-APP-002']};
  }
  return {code: 'E-APP-005', message: APP_MESSAGES['E-APP-005']};
}
