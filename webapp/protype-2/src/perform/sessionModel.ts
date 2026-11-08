// APP-2 (US-APP-2-03, -04) — Groups the flat, timeline-ordered list
// `toPerformerItems` already produces into SESSIONS: one instance of a
// business flow (one job), worked as a unit.
//
// WHY THIS IS A SEPARATE GROUPING FROM `toPerformerItems`'s OWN. That
// function groups by TIMELINE (a scheduling concept — "whose day, what
// order") because that is what a planned start is derived from. A
// session groups by JOB (`work_item_id`) because that is what a
// performer actually experiences: one customer, one flow, start to
// finish. The two are orthogonal — a session's items can span more
// than one timeline in principle, though at MVP volumes they rarely
// will — and conflating them would make the wrong thing the unit of
// the screen.
//
// NO IMPORTS beyond `performerView`'s own types, same discipline as
// that file: a plain function over plain data, testable with nothing
// but `node --test`.
//
// NEVER DROPS AN ITEM, same rule `toPerformerItems` already states. An
// item whose sub-step has no `session` (should not happen once APP-2's
// backend has shipped everywhere, but a merge must degrade, not
// crash) gets its own one-item session rather than being silently
// merged into some other job's or discarded.
import {
  deriveBlockStatus,
  type PerformerItem,
  type PerformerSubStep,
  type SessionInfo,
  type TaskStatus,
  type TimeWindow,
} from './performerView';

export interface Session {
  workItemId: number;
  title: string;
  flowTitle: string;
  versionNo: number | null;
  planId: number | null;
  planName: string;
  /** Planned order within the session — never the raw merge order. */
  items: PerformerItem[];
  /** Same precedence as a block's own status (`deriveBlockStatus`): blocked wins, then all-done, then any-moving, else not_started. */
  status: TaskStatus;
  plannedStartMinutes: number;
  plannedStartLabel: string;
  totalScheduledMinutes: number;
  /** Done AND skipped both count as "no longer open" — the same rule canFinishSession uses. */
  doneCount: number;
  totalCount: number;
  /** TW-1 — the job's window; every item in a session shares the same job, so the first item's is the session's. */
  timeWindow: TimeWindow | null;
}

const UNTITLED_SESSION: SessionInfo = {
  workItemId: 0,
  title: null,
  flowTitle: null,
  versionNo: null,
  planId: null,
  planName: null,
};

let fallbackSessionCounter = 0;

/**
 * Groups items by `subSteps[0].session.workItemId`. Each item's FIRST
 * sub-step decides which session it belongs to — blocks (several
 * sub-steps per item) are deferred (SCHED-1), so at MVP volumes every
 * item has exactly one sub-step and this is never an approximation in
 * practice.
 *
 * A missing session gets a synthetic, strictly negative id (real
 * work_item ids start at 1) so it can never collide with a real
 * session — and a fresh one per call, so two sessionless items are
 * never merged into the same bucket just because both lack provenance.
 */
export function toSessions(items: PerformerItem[]): Session[] {
  const groups = new Map<number, {info: SessionInfo; items: PerformerItem[]}>();

  for (const item of items) {
    const info = item.subSteps[0]?.session ?? null;
    const key = info ? info.workItemId : --fallbackSessionCounter;
    const existing = groups.get(key);
    if (existing) {
      existing.items.push(item);
    } else {
      groups.set(key, {info: info ?? {...UNTITLED_SESSION, workItemId: key}, items: [item]});
    }
  }

  const sessions: Session[] = [];
  for (const {info, items: groupItems} of groups.values()) {
    const ordered = [...groupItems].sort((a, b) => a.plannedStartMinutes - b.plannedStartMinutes);
    const statuses = ordered.map((i) => i.status);
    const doneCount = ordered.filter((i) => i.status === 'done' || i.status === 'skipped').length;

    sessions.push({
      workItemId: info.workItemId,
      title: info.title ?? 'Untitled session',
      flowTitle: info.flowTitle ?? '',
      versionNo: info.versionNo,
      planId: info.planId,
      planName: info.planName ?? '',
      items: ordered,
      status: deriveBlockStatus(statuses),
      plannedStartMinutes: ordered[0].plannedStartMinutes,
      plannedStartLabel: ordered[0].plannedStartLabel,
      totalScheduledMinutes: ordered.reduce((sum, i) => sum + i.scheduledMinutes, 0),
      doneCount,
      totalCount: ordered.length,
      timeWindow: ordered[0].timeWindow,
    });
  }

  // Ties keep snapshot order — Array.sort is stable (same rule toPerformerItems documents for its own final sort).
  sessions.sort((a, b) => a.plannedStartMinutes - b.plannedStartMinutes);
  return sessions;
}

/**
 * US-APP-2-04/-07 (D-4): order is a SUGGESTION, not a lock — any item
 * stays tappable regardless of status. This is only which one the
 * screen highlights: the first item, in planned order, that is not
 * already done or skipped. Null once every item is.
 */
export function nextItemToWork(session: Session): PerformerItem | null {
  return session.items.find((i) => i.status !== 'done' && i.status !== 'skipped') ?? null;
}

/**
 * BLK-1 (US-BLK-1-04) — the next STEP to work, not the next card.
 *
 * `nextItemToWork` above answers "which card", which was the same
 * question while a card held exactly one step. A card is now a whole
 * order's work for one actor row, so the screen has to highlight the
 * next STAGE inside it — otherwise a half-finished card points at
 * nothing useful.
 *
 * Same rule as its sibling, one level down: planned order, first one
 * that is not already done or skipped, null once every one is. Order
 * is still a suggestion, not a lock (D-4) — this only decides what is
 * highlighted, never what is tappable.
 */
export function nextSubStepToWork(session: Session): PerformerSubStep | null {
  for (const item of session.items) {
    for (const sub of item.subSteps) {
      if (sub.status !== 'done' && sub.status !== 'skipped') return sub;
    }
  }
  return null;
}

/**
 * D-2: a session may be finished only once every item is done or
 * skipped. Mirrors `doneCount === totalCount` so a caller doesn't have
 * to re-derive the same condition two different ways.
 */
export function canFinishSession(session: Session): boolean {
  return session.doneCount === session.totalCount;
}

export interface TodaySummary {
  jobCount: number;
  inProgressCount: number;
}

/**
 * EXEC-1 (US-EXEC-1-02) — the Today header's summary line ("4 jobs today ·
 * 1 in progress"), pulled out as a pure function so it has its own test
 * instead of being buried in JSX. `jobCount` counts every session for the
 * day, same as the existing "N sessions" line did; `inProgressCount` reads
 * `Session.status`, the same derived field the status pill already shows
 * (not a re-derivation from items/sub-steps).
 */
export function todaySummary(sessions: Session[]): TodaySummary {
  return {
    jobCount: sessions.length,
    inProgressCount: sessions.filter((s) => s.status === 'in_progress').length,
  };
}

export interface JobProgress {
  doneCount: number;
  blockedCount: number;
  skippedCount: number;
  totalCount: number;
  /** Rounded 0–100. Done and skipped both count as finished — same rule canFinishSession uses. 0 on a 0-step session, never NaN. */
  percent: number;
}

/**
 * EXEC-1 (US-EXEC-1-04) — the Overview tab's progress ring and counts.
 *
 * Deliberately counts individual STEPS (`PerformerSubStep`, one per
 * `work_task_id`), not `Session.doneCount`/`totalCount` — those two
 * count BLOCKS (`PerformerItem`), the unit `canFinishSession` gates
 * the Finish button on. A block with several steps bundled under one
 * card (SessionScreen's own nested-<ol> case) must not be undercounted
 * as "1 of however-many" here.
 */
export function jobProgress(session: Session): JobProgress {
  const steps = session.items.flatMap((item) => item.subSteps);
  const doneCount = steps.filter((s) => s.status === 'done' || s.status === 'skipped').length;
  const blockedCount = steps.filter((s) => s.status === 'blocked').length;
  const skippedCount = steps.filter((s) => s.status === 'skipped').length;
  const totalCount = steps.length;
  const percent = totalCount === 0 ? 0 : Math.round((doneCount / totalCount) * 100);
  return {doneCount, blockedCount, skippedCount, totalCount, percent};
}

export interface JobNote {
  note: string;
  occurredAt: number;
  author: string | null;
  /** Which step this note was left on — for the "tagged with its step" rule in the design prompt. */
  workTaskId: number;
  stepLabel: string;
}

/**
 * EXEC-1 (US-EXEC-1-05) — every note across every step of a job, merged
 * into one newest-first feed and tagged with its step's label. Notes
 * are stored per step (`PerformerSubStep.notes`, already newest-first
 * off the wire per `hydrate_statuses`'s own ordering) — there is no
 * job-level note today (deferred, see the epic's README). This never
 * drops a note: a step with no `stageLabel` falls back to its
 * `stageKey`, the same fallback the Steps tab rows already use.
 */
export function jobNotes(session: Session): JobNote[] {
  const all: JobNote[] = [];
  for (const item of session.items) {
    for (const sub of item.subSteps) {
      const stepLabel = sub.stageLabel || sub.stageKey;
      for (const n of sub.notes) {
        all.push({note: n.note, occurredAt: n.occurredAt, author: n.author, workTaskId: sub.workTaskId, stepLabel});
      }
    }
  }
  return all.sort((a, b) => b.occurredAt - a.occurredAt);
}
