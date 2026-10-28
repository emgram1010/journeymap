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
