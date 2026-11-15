/** COP-5 story 05 — pure helpers for the copilot's scheduled runs (the run log shown in the panel). */

export interface CopilotRun {
  id: number;
  status: string;
  trigger?: string;
  journey_architecture_id?: number;
  started_at?: number | null;
  finished_at?: number | null;
  work_date?: string;
  open_task_count?: number;
  held_count?: number;
  told_count?: number;
  refused_count?: number;
  report?: string;
  reason?: string;
}

const STATUS_LABELS: Record<string, string> = {
  running: 'Running now',
  finished: 'Finished',
  nothing_to_do: 'Nothing to do',
  skipped: 'Skipped',
  failed: 'Failed',
};

export const runStatusLabel = (status: string): string => STATUS_LABELS[status] ?? status;

export type RunTone = 'ok' | 'quiet' | 'bad';

export const runTone = (status: string): RunTone =>
  status === 'failed' ? 'bad' : status === 'skipped' || status === 'nothing_to_do' ? 'quiet' : 'ok';

/** Counts come from the records (approvals and the tool log), not from the copilot's own words. */
export function runCountsLine(run: CopilotRun): string {
  const parts: string[] = [];
  const held = run.held_count || 0;
  const told = run.told_count || 0;
  const refused = run.refused_count || 0;
  if (held > 0) parts.push(`${held} waiting for you`);
  if (told > 0) parts.push(`${told} done, then told you`);
  if (refused > 0) parts.push(`${refused} refused`);
  return parts.join(' · ');
}

export function runsHeadline(on: boolean, runCount: number): string {
  if (!on) {
    return 'Scheduled work is switched off for this business. An admin can turn it on under Approvals, "How much the copilot may do".';
  }
  if (runCount === 0) return 'Scheduled work is on. No runs yet - the copilot checks its tasks every hour.';
  return 'Runs in the last 14 days, newest first.';
}

export const runWhen = (ts: number | null | undefined): string => {
  if (!ts) return '';
  const d = new Date(ts);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleString();
};
