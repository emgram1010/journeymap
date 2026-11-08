// BOARD-1 — The planner board's own rules, pulled out of the components
// so the decisions a reader actually notices — how the Jobs column
// groups, what the count means, when a drop is refused, what a job slot
// says about itself — are tested rather than buried in JSX.
//
// PURE. No fetching, no React, no DOM.

/** The part of a backlog card (559) the grouping needs. */
export type GroupableCard = {
  card_key: string;
  work_item_id: number;
  job_title: string | null;
};

export type JobGroup<T extends GroupableCard> = {
  workItemId: number;
  jobTitle: string;
  cards: T[];
};

/**
 * One group per job, newest job first (a job just created is the one
 * being worked with), cards within a job in the order the server gave
 * them — 559 already returns them in the pinned version's stage order.
 * Q-1 (founder, 2026-10-28): grouped under job titles, not a flat list.
 */
export function groupCardsByJob<T extends GroupableCard>(cards: readonly T[]): JobGroup<T>[] {
  const byJob = new Map<number, JobGroup<T>>();
  for (const c of cards) {
    const group = byJob.get(c.work_item_id);
    if (group) group.cards.push(c);
    else {
      byJob.set(c.work_item_id, {
        workItemId: c.work_item_id,
        // A job with no title still gets a name a human can say out loud.
        jobTitle: c.job_title || `Job #${c.work_item_id}`,
        cards: [c],
      });
    }
  }
  return [...byJob.values()].sort((a, b) => b.workItemId - a.workItemId);
}

/** "Jobs (N)" counts JOBS with waiting work, not cards — a job with three roles is one job. */
export function waitingJobsCount(cards: readonly GroupableCard[]): number {
  return new Set(cards.map((c) => c.work_item_id)).size;
}

/**
 * The drop-intent rule (D-3): may a job card land on this day?
 * `undefined` timeline status means the (agent, day) has no day yet —
 * that is allowed, the day is created idempotently on drop. Only a
 * published day refuses, with the sentence the toast shows. The server
 * enforces the same rule again either way (E-SCHED-008).
 */
export function jobCardDropRefusal(timelineStatus: string | undefined | null): string | null {
  if (timelineStatus === 'published') {
    return 'That day is published and frozen — reopen it before adding work.';
  }
  return null;
}

/**
 * The amber provenance line on a scheduled slot: which job it belongs
 * to and, when the slot is a CARD covering several steps (BLK-1), how
 * many. A plain task has none, and returns null rather than ''.
 */
export function jobSlotProvenance(task: {jobTitle?: string; jobStepCount?: number}): string | null {
  if (!task.jobTitle) return null;
  const steps = task.jobStepCount ?? 1;
  return steps > 1 ? `${task.jobTitle} · ${steps} steps` : task.jobTitle;
}

/** PUX-3-04 — the job line under a card's title, or null when it would only repeat the title. */
export function cardSubtitle(task: {title: string; jobTitle?: string; jobStepCount?: number}): string | null {
  const line = jobSlotProvenance(task);
  if (!line) return null;
  return line.trim() === task.title.trim() ? null : line;
}

/**
 * REPUB-1 — may this timeline be republished right now? Mirrors
 * endpoint 562's own seal rule exactly: nothing to republish before
 * the first publish, and a published day seals itself the moment ANY
 * activity is recorded against it (the server decides `isSealed`,
 * never this function — it only reads the answer).
 */
export function canRepublish(timeline: {status: string; isSealed?: boolean}): boolean {
  return timeline.status === 'published' && timeline.isSealed !== true;
}

/**
 * REPUB-1 — the small "v2" badge next to a Published label. Quiet
 * until it matters: version 1 (the ordinary, never-republished case)
 * and an unset/zero version both render as no badge at all.
 */
export function versionBadge(currentVersion: number | undefined | null): string | null {
  return currentVersion && currentVersion > 1 ? `v${currentVersion}` : null;
}

/**
 * QUE-1 (US-QUE-1-05/06) — what happens when a scheduled task is pulled
 * off its day, apart from the DOM.
 *
 * A JOB slot (it has `workItemId`) always needs the confirmation —
 * taking it off a day is a real decision, not a tidy-up, and it is
 * linked work (BLK-1: the slot covers several steps as one unit). A
 * PLAIN task keeps its existing, already-visible behaviour — it was
 * never silent about what it does, and the confirmation this epic adds
 * is scoped to the thing that is new: a job's role line (Q-4).
 *
 * A job slot with no `workTaskId` is a defensive `invalid` — there is
 * nothing to call `unscheduleWorkTask` with, so the caller must not
 * even open the confirmation (it would have nothing to confirm into).
 */
export type UnscheduleIntent = 'confirm-job-slot' | 'plain-task' | 'invalid';

export function classifyUnscheduleTarget(task: {workItemId?: number; workTaskId?: number}): UnscheduleIntent {
  if ((task.workItemId ?? 0) > 0) {
    return (task.workTaskId ?? 0) > 0 ? 'confirm-job-slot' : 'invalid';
  }
  return 'plain-task';
}

/**
 * PUX-3-01 — the planner's own calendar date, "YYYY-MM-DD". NOT
 * `toISOString()`: that is UTC, so in the evening anywhere west of UTC it
 * already says tomorrow (Opus review, 2026-11-07).
 */
export function localToday(now: Date = new Date()): string {
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  return `${now.getFullYear()}-${m}-${d}`;
}

/**
 * PUX-3-01 — which day the board opens on. Today when it is inside the plan,
 * else the plan's first day. Only a plan with no dates falls back to its first
 * timeline (the old rule, which opened a Nov 1–7 plan on Oct 27).
 */
export function initialBoardDay(today: string, planStart: string, planEnd: string, firstTimelineDate: string | null): string {
  if (planStart && planEnd) return today >= planStart && today <= planEnd ? today : planStart;
  return firstTimelineDate || today;
}

/** PUX-3-02 — days that hold work but sit outside the plan's dates (so the week view hides them). */
export function workOutsidePlan(
  timelines: ReadonlyArray<{id: string; plannedDate: string}>,
  tasks: ReadonlyArray<{timelineId: string | null}>,
  planStart: string,
  planEnd: string,
): Array<{timelineId: string; date: string; slots: number}> {
  if (!planStart || !planEnd) return [];
  const out: Array<{timelineId: string; date: string; slots: number}> = [];
  for (const tl of timelines) {
    if (tl.plannedDate >= planStart && tl.plannedDate <= planEnd) continue;
    const slots = tasks.filter((t) => t.timelineId === tl.id).length;
    if (slots > 0) out.push({timelineId: tl.id, date: tl.plannedDate, slots});
  }
  return out.sort((a, b) => a.date.localeCompare(b.date));
}

/** PUX-3-03 — what a week-view cell lists: the first `max` items in day order, and how many more. */
export function cellPreview<T extends {seq: number}>(tasks: ReadonlyArray<T>, max: number): {shown: T[]; more: number} {
  const ordered = [...tasks].sort((a, b) => a.seq - b.seq);
  return {shown: ordered.slice(0, max), more: Math.max(0, ordered.length - max)};
}

export interface CapacityFit {
  /** Minutes still free before adding anything (never negative). */
  freeMinutes: number;
  /** Planned minutes if the work is added. */
  afterMinutes: number;
  /** fits: room for it · over: has room but this tips it over · full: already at/over capacity. */
  state: 'fits' | 'over' | 'full';
}

/** PUX-4-01 — would `addMinutes` fit on a day already holding `loadMinutes`? Advisory only. */
export function capacityFit(loadMinutes: number, capacityHours: number, addMinutes: number): CapacityFit {
  const cap = capacityHours * 60;
  const freeMinutes = Math.max(0, cap - loadMinutes);
  const afterMinutes = loadMinutes + addMinutes;
  const state = freeMinutes === 0 ? 'full' : afterMinutes > cap ? 'over' : 'fits';
  return {freeMinutes, afterMinutes, state};
}

function hm(totalMin: number): string {
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  if (h === 0) return `${m}m`;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

/** PUX-4-01 — "8h free", "1h 30m free", "no time free". */
export function formatFree(freeMinutes: number): string {
  return freeMinutes <= 0 ? 'no time free' : `${hm(freeMinutes)} free`;
}

/** PUX-4-02 — the one question asked before overloading someone. */
export function overloadMessage(agentName: string, fit: CapacityFit, capacityHours: number): string {
  return `This puts ${agentName} at ${hm(fit.afterMinutes)} of ${capacityHours}h. Place anyway?`;
}
