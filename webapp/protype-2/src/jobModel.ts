// JOB-1 (US-JOB-1-02, US-JOB-1-05) — The two rules that decide what a
// job contains and what state it is in.
//
// Both are pure functions over a PINNED version snapshot, never over
// the live map. That is the whole point of JOB-1: a job's content is
// read through the version it was pinned to, so editing or
// re-publishing the map afterwards cannot change work already in
// flight.

/** A task's status. Fixed list — see the architecture rules. */
export type TaskStatus = 'not_started' | 'in_progress' | 'blocked' | 'done' | 'skipped';

/** A job's status. `cancelled` is set explicitly; the rest are derived. */
export type JobStatus = 'open' | 'in_progress' | 'blocked' | 'completed' | 'cancelled';

const JOB_STATUS_LABELS: Record<string, string> = {
  open: 'Not started',
  in_progress: 'In progress',
  blocked: 'Blocked',
  completed: 'Done',
  cancelled: 'Cancelled',
};

/**
 * The words a planner reads for a job's status.
 *
 * ONE PLACE (CLAUDE.md: a shared rule lives in its own function, not a
 * copy in each reader). The jobs list and the Plan vs Action report
 * both name the same job, and two copies of this map would eventually
 * call the same status different things. A status this doesn't know is
 * shown exactly as it arrived rather than blanked — a new status added
 * server-side should look unfamiliar, not invisible.
 */
export function jobStatusLabel(status: string): string {
  return JOB_STATUS_LABELS[status] ?? status;
}

export interface VersionLens {
  key: string;
  label?: string;
  actor_type?: string;
  does_planned_work?: boolean;
}

export interface VersionStage {
  key: string;
  label?: string;
  owner_lens_key?: string | null;
}

export interface VersionCell {
  stage_key: string;
  lens_key: string;
  task?: string | null;
  done_when?: string | null;
  duration_minutes?: number | null;
}

export interface VersionSnapshot {
  stages: VersionStage[];
  lenses: VersionLens[];
  cells: VersionCell[];
}

export interface GeneratedTask {
  stage_key: string;
  lens_key: string;
  /** True when this is the stage's owning row, rather than an extra work cell. */
  is_owner: boolean;
}

export interface SkippedStage {
  stage_key: string;
  reason: 'no_owner' | 'owner_does_no_planned_work' | 'owner_lens_missing';
}

export interface TasksFromVersionResult {
  tasks: GeneratedTask[];
  skipped: SkippedStage[];
}

/**
 * Which tasks a job gets, from its pinned version.
 *
 * One task for each stage's OWNING row, plus any other row in that
 * stage that both does planned work and has a task written in it.
 *
 * A stage whose owner does no planned work produces no task and is
 * REPORTED rather than silently dropped (US-JOB-1-09). Silently
 * skipping it would give a job fewer tasks than the map implies, and
 * nobody would know which stage went missing.
 *
 * Order is the version's stage order, and within a stage the owner
 * comes first. A job's task list should read like the map.
 */
export function tasksFromVersion(version: VersionSnapshot): TasksFromVersionResult {
  const tasks: GeneratedTask[] = [];
  const skipped: SkippedStage[] = [];

  const lensByKey = new Map<string, VersionLens>();
  for (const lens of version.lenses ?? []) lensByKey.set(lens.key, lens);

  const cellsByStage = new Map<string, VersionCell[]>();
  for (const cell of version.cells ?? []) {
    const list = cellsByStage.get(cell.stage_key);
    if (list) list.push(cell);
    else cellsByStage.set(cell.stage_key, [cell]);
  }

  for (const stage of version.stages ?? []) {
    const ownerKey = stage.owner_lens_key;
    const stageCells = cellsByStage.get(stage.key) ?? [];

    if (!ownerKey) {
      skipped.push({stage_key: stage.key, reason: 'no_owner'});
    } else {
      const ownerLens = lensByKey.get(ownerKey);
      if (!ownerLens) {
        skipped.push({stage_key: stage.key, reason: 'owner_lens_missing'});
      } else if (!ownerLens.does_planned_work) {
        skipped.push({stage_key: stage.key, reason: 'owner_does_no_planned_work'});
      } else {
        tasks.push({stage_key: stage.key, lens_key: ownerKey, is_owner: true});
      }
    }

    // Any other work-doing row in this stage that actually has a task.
    for (const cell of stageCells) {
      if (cell.lens_key === ownerKey) continue;
      const lens = lensByKey.get(cell.lens_key);
      if (!lens?.does_planned_work) continue;
      if (!hasText(cell.task)) continue;
      tasks.push({stage_key: stage.key, lens_key: cell.lens_key, is_owner: false});
    }
  }

  return {tasks, skipped};
}

function hasText(value: string | null | undefined): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

/**
 * A job's status, derived from its tasks.
 *
 * NEVER STORED AS THE SOURCE OF TRUTH. `work_item.status` is a cached
 * copy written only by LOG-1's engine, and GOV-1's daily audit
 * compares it against this function (review finding F12). If the two
 * ever disagree, this one is right.
 *
 * Precedence, highest first:
 *   cancelled  — set explicitly, and it wins over everything
 *   blocked    — one blocked task holds up the job, however much else is done
 *   completed  — every task finished one way or the other
 *   in_progress— something has started, or some work is done
 *   open       — nothing has happened yet
 *
 * A job with no tasks is `open`: nothing has happened, which is
 * truthful, and it avoids calling an empty job "completed".
 */
export function deriveJobStatus(
  tasks: ReadonlyArray<{status: TaskStatus}>,
  isCancelled = false,
): JobStatus {
  if (isCancelled) return 'cancelled';
  if (tasks.length === 0) return 'open';

  if (tasks.some((t) => t.status === 'blocked')) return 'blocked';

  if (tasks.every((t) => t.status === 'done' || t.status === 'skipped')) return 'completed';

  if (tasks.some((t) => t.status === 'in_progress' || t.status === 'done' || t.status === 'skipped')) {
    return 'in_progress';
  }

  return 'open';
}
