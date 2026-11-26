// REPEAT-1 story 05 — the screen's side of "needs review".
//
// The server (planner_task_review, returned as the board's `reviews[]`) decides which slots need
// a second look and why. Nothing here decides that. This file only turns the server's list into
// what the screen shows: a sign and a reason on each slot, a count on each day, a total for the
// plan, and one plain sentence at Publish to live. Pure functions, no network.

export interface RawReview {
  planner_task_id: number;
  reason_code: string;
  reason_text: string;
}

export interface ReviewMark {
  code: string;
  text: string;
}

/** The minimal slot shape this model needs (the board's Task has more): a slot carries its mark once adapted. */
export interface ReviewableTask {
  timelineId: string | null;
  review?: ReviewMark;
}

/** Slot id (as the board spells it, a string) → its mark. */
export const reviewByTask = (reviews: RawReview[]): Map<string, ReviewMark> => {
  const out = new Map<string, ReviewMark>();
  for (const r of reviews) {
    out.set(String(r.planner_task_id), {code: r.reason_code, text: reviewReasonText(r.reason_code, r.reason_text)});
  }
  return out;
};

/** How many marked slots sit on one day. */
export const markedOnDay = (tasks: ReviewableTask[], timelineId: string): number =>
  tasks.reduce((n, t) => n + (t.review && t.timelineId === timelineId ? 1 : 0), 0);

/** Every marked slot of the plan, on a day or in the backlog. */
export const totalMarked = (tasks: ReviewableTask[]): number =>
  tasks.reduce((n, t) => n + (t.review ? 1 : 0), 0);

/** The sentence at Publish to live. Empty when there is nothing to say. Publishing is never blocked by it. */
export const publishReviewNotice = (count: number): string => {
  if (!(count > 0)) return '';
  return count === 1
    ? '1 item was copied and not yet reviewed. Publish anyway?'
    : `${count} items were copied and not yet reviewed. Publish anyway?`;
};

const REASONS: Record<string, string> = {
  copied: 'Copied from the last plan. Check it still fits.',
  person_left_off: 'Its person is no longer on the plan. Pick who does it.',
  new_step: 'A new step in the map. Decide where it goes.',
};

/** Plain wording. The server's own sentence wins when it has one (it names the plan or the person). */
export const reviewReasonText = (code: string, serverText: string): string => {
  const own = (serverText ?? '').trim();
  if (own !== '') return own;
  return REASONS[code] ?? 'Look at this before publishing.';
};
