// LOAD-1 (US-LOAD-1-03) — one Unscheduled card's steps, from the job it belongs to.
//
// The Unscheduled list arrives as summary rows (no step text). When a card is
// selected the drawer reads the job (`GET work_item/{id}`, 555 — already
// tenancy-checked, already hydrated from the job's PINNED version) and this
// picks out that card's steps.
//
// `work_task_ids` IS THE CONTRACT. The backlog builds it from exactly the
// card's unscheduled steps, walking the pinned version's stages in order — so
// it decides both WHICH tasks belong to the card and in WHAT ORDER they show.
// The job's own task list is by id and includes scheduled steps and other
// actor rows, so it must never decide either.
//
// An id the job no longer returns is REPORTED in `missing`, not silently
// dropped: a card showing fewer steps than it claims must be visible.
import type {BacklogCard, BacklogCardStep, WorkItemTask} from './plannerApi';

export interface CardStepsResult {
  steps: BacklogCardStep[];
  /** Ids the card lists that the job no longer has. Empty in the normal case. */
  missing: number[];
}

export function cardStepsFromJobTasks(
  card: Pick<BacklogCard, 'work_task_ids'>,
  jobTasks: readonly WorkItemTask[],
): CardStepsResult {
  const byId = new Map<number, WorkItemTask>();
  for (const t of jobTasks) byId.set(t.id, t);

  const steps: BacklogCardStep[] = [];
  const missing: number[] = [];
  for (const id of card.work_task_ids) {
    const t = byId.get(id);
    if (!t) {
      missing.push(id);
      continue;
    }
    steps.push({
      work_task_id: t.id,
      stage_key: t.stage_key,
      // The backlog sent '' for a stage with no label; 555 sends null. Keep the old shape.
      stage_label: t.stage_label ?? '',
      status: t.status,
      task: t.task,
      done_when: t.done_when,
      expected_minutes: t.expected_minutes,
      estimate_status: t.estimate_status,
      estimate_source: t.estimate_source as BacklogCardStep['estimate_source'],
    });
  }
  return {steps, missing};
}
