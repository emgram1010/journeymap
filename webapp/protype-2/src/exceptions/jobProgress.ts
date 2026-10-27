// EXC-2 (US-EXC-2-01/02) — One job's progress, computed the same way
// on both sides.
//
// PURE. The backend twin is `functions/exceptions/job_progress.xs`;
// both run over `src/fixtures/job-progress-golden.json` (UT-EXC-2-01..03
// here; the last two golden cases are also verified live against the
// real backend function — see the fixture's `_about`).
//
// finished = done OR skipped (D-4). "Current stage" = the stage of the
// LOWEST-POSITION unfinished step, where position is this job's OWN
// pinned `stageOrder` (a child and its parent can be on different maps
// with different stage orders — never compare positions across jobs).
// A step whose stage key is not in `stageOrder` sorts LAST. All steps
// finished → `current_stage_key` = "".

export type TaskStatus = 'not_started' | 'in_progress' | 'blocked' | 'done' | 'skipped';

export type ProgressTask = {stage_key: string; status: TaskStatus | string};
export type StageOrderEntry = {key: string; label: string};

export type JobProgress = {
  task_count: number;
  finished_count: number;
  has_blocked: boolean;
  current_stage_key: string;
  current_stage_label: string;
};

// Two DISTINCT sentinels, same as the backend twin — collapsing them into
// one (e.g. both Infinity) breaks the "all finished" check: an unfinished
// task whose stage isn't in `stageOrder` would compare equal to "nothing
// unfinished seen yet" and get silently treated as finished.
const UNKNOWN_STAGE_POSITION = 999_999; // a real, sortable "last" position
const NOTHING_UNFINISHED_SEEN = 999_999_999; // strictly bigger — the seed

const isFinished = (status: string) => status === 'done' || status === 'skipped';

/** The US-EXC-2-01 shape, for one job's own tasks and its own pinned stage order. */
export function jobProgress(tasks: ProgressTask[], stageOrder: StageOrderEntry[]): JobProgress {
  const positionByKey = new Map<string, number>();
  const labelByKey = new Map<string, string>();
  stageOrder.forEach((s, i) => {
    positionByKey.set(s.key, i);
    labelByKey.set(s.key, s.label);
  });

  let finishedCount = 0;
  let hasBlocked = false;
  let minPos = NOTHING_UNFINISHED_SEEN;
  let minStageKey = '';

  for (const t of tasks) {
    if (isFinished(t.status)) {
      finishedCount += 1;
      continue;
    }
    if (t.status === 'blocked') hasBlocked = true;
    const pos = positionByKey.get(t.stage_key) ?? UNKNOWN_STAGE_POSITION;
    if (pos < minPos) {
      minPos = pos;
      minStageKey = t.stage_key;
    }
  }

  const allFinished = minPos === NOTHING_UNFINISHED_SEEN;
  const currentStageKey = allFinished ? '' : minStageKey;
  const currentStageLabel = allFinished ? '' : (labelByKey.get(minStageKey) ?? minStageKey);

  return {
    task_count: tasks.length,
    finished_count: finishedCount,
    has_blocked: hasBlocked,
    current_stage_key: currentStageKey,
    current_stage_label: currentStageLabel,
  };
}

/** "2 of 6 done · at Repair", "Done", "2 of 6 done · blocked at Repair", "No steps". */
export function progressLabel(p: JobProgress): string {
  if (p.task_count === 0) return 'No steps';
  if (p.finished_count === p.task_count) return 'Done';
  const base = `${p.finished_count} of ${p.task_count} done`;
  if (p.has_blocked) return `${base} · blocked at ${p.current_stage_label}`;
  return `${base} · at ${p.current_stage_label}`;
}

/** "2 of 6" — the short form used in chips (US-EXC-2-03/04), never built twice. */
export function progressShortLabel(p: JobProgress): string {
  return `${p.finished_count} of ${p.task_count}`;
}
