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
import {deriveBlockStatus, type PerformerItem, type SessionInfo, type TaskStatus} from './performerView';

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
 * D-2: a session may be finished only once every item is done or
 * skipped. Mirrors `doneCount === totalCount` so a caller doesn't have
 * to re-derive the same condition two different ways.
 */
export function canFinishSession(session: Session): boolean {
  return session.doneCount === session.totalCount;
}
