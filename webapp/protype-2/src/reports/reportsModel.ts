// RPT-1 — Reports → Plan vs Action.
//
// The pickers' rule, pulled out of the page so the one decision a
// reader actually notices — WHICH job the report opens on — is tested
// rather than buried in a component.
//
// PURE. No fetching, no React.
import {jobStatusLabel} from '../jobModel';

/** The part of the planner's job-list row this report needs. */
export type ReportJobEntry = {
  work_item: {id: number; title: string; status: string};
  task_count: number;
  finished_count: number;
  /** Set by the list endpoint: Execution has recorded something against this job. */
  has_progress: boolean;
};

export type JobOption = {
  id: number;
  title: string;
  statusLabel: string;
  stepSummary: string;
  /** Something came back from Execution, so there is a comparison to draw. */
  hasRecord: boolean;
};

/**
 * Every job in the plan, in the order a reader wants them: the ones with
 * something recorded first (a report that opens on a job nobody has
 * started shows an empty table and reads as broken), then newest first.
 */
export function reportJobOptions(entries: readonly ReportJobEntry[]): JobOption[] {
  return entries
    .map((e) => ({
      id: e.work_item.id,
      title: e.work_item.title,
      statusLabel: jobStatusLabel(e.work_item.status),
      stepSummary: stepSummary(e.finished_count, e.task_count),
      hasRecord: e.has_progress,
    }))
    // A copy, so the caller's list keeps the order the endpoint gave it.
    .sort((a, b) => Number(b.hasRecord) - Number(a.hasRecord) || b.id - a.id);
}

/** The job the page opens on, or `null` when the plan has no jobs at all. */
export function firstJobToShow(options: readonly JobOption[]): number | null {
  return options[0]?.id ?? null;
}

function stepSummary(finished: number, total: number): string {
  // "0 of 0 done" reads as a job underway that has achieved nothing, which
  // is the opposite of what it means (same call as jobProgress.ts).
  if (total === 0) return 'No steps';
  return `${finished} of ${total} step${total === 1 ? '' : 's'} done`;
}
