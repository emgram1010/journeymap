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
 * QUE-1 (US-QUE-1-04) — the disclosure rule for a job's steps: flat, or
 * grouped under the role (actor row) that does them.
 *
 * ONE ROLE (the normal case) → `null`. The caller renders the tasks
 * directly; a single-item group would be an extra tier for nothing.
 *
 * MORE THAN ONE ROLE → one group per distinct `lens_key`, first-seen
 * order, each group's tasks kept in the job's own order (the pinned
 * version's stage order — never re-sorted here).
 */
export interface RoleStepGroup<T> {
  lensKey: string;
  lensLabel: string;
  tasks: T[];
}

export function groupTasksByRole<T extends {lens_key: string; owner_lens_label?: string | null}>(
  tasks: readonly T[],
): RoleStepGroup<T>[] | null {
  const distinctLenses = new Set(tasks.map((t) => t.lens_key));
  if (distinctLenses.size <= 1) return null;

  const order: string[] = [];
  const byLens = new Map<string, RoleStepGroup<T>>();
  for (const t of tasks) {
    let group = byLens.get(t.lens_key);
    if (!group) {
      group = {lensKey: t.lens_key, lensLabel: t.owner_lens_label || t.lens_key, tasks: []};
      byLens.set(t.lens_key, group);
      order.push(t.lens_key);
    }
    group.tasks.push(t);
  }
  return order.map((key) => byLens.get(key)!);
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

// ── QTY-1 — how many units, and which ones went down the exception path ──
//
// Every number these produce was already stored (ITEM-1's `work_item_line`)
// and already returned (EXC-1's `moved_lines` on each parent/child link).
// QTY-1 only puts them on screen, so there is nothing to derive here beyond
// summing and phrasing — kept out of the JSX so both can be tested.

export interface UnitLine {
  item_label: string;
  unit: string;
  quantity: number;
}

export interface UnitSummary {
  /** Null, not 0, when the job has no lines at all — D-6: a real zero reads differently. */
  totalQuantity: number | null;
  lines: UnitLine[];
}

/**
 * QTY-1 (US-QTY-1-01). An untouched int column in this stack is `0`, never
 * null (CLAUDE.md, repeatedly), so "nothing recorded" cannot be inferred
 * from the total being falsy — it has to come from there being no lines.
 * That is why `totalQuantity` is nullable and a zero-quantity line still
 * counts as a line.
 */
export function summarizeUnits(
  lines: readonly {item_label?: string | null; item_key?: string | null; unit?: string | null; quantity: number}[],
): UnitSummary {
  if (lines.length === 0) return {totalQuantity: null, lines: []};
  return {
    totalQuantity: lines.reduce((sum, l) => sum + l.quantity, 0),
    lines: lines.map((l) => ({
      // A line with no label still names itself, the same way a job with no
      // title falls back to its number elsewhere in this codebase.
      item_label: l.item_label || l.item_key || 'Unnamed item',
      unit: l.unit || 'units',
      quantity: l.quantity,
    })),
  };
}

export interface MovedUnits {
  workItemId: number;
  /** The other job's own title, so the sentence names it rather than only numbering it. */
  title: string;
  quantity: number;
}

/**
 * QTY-1 (US-QTY-1-02) — what a link moved, per linked job. Used both ways:
 * on a parent it reads "N units moved to <child>", on a child "N units came
 * from <parent>". A link that moved nothing is dropped, so an unsplit job
 * produces an empty list and the UI renders no lineage at all.
 */
export function movedUnits(
  links: readonly {
    work_item_id: number;
    title?: string | null;
    moved_lines?: readonly {quantity: number}[] | null;
  }[],
): MovedUnits[] {
  const out: MovedUnits[] = [];
  for (const link of links) {
    const quantity = (link.moved_lines ?? []).reduce((sum, l) => sum + l.quantity, 0);
    if (quantity <= 0) continue;
    out.push({
      workItemId: link.work_item_id,
      title: link.title || `Job #${link.work_item_id}`,
      quantity,
    });
  }
  return out;
}

/**
 * QTY-1 (US-QTY-1-03) — the Jobs column row's unit line, in the ERP
 * work-order-split phrasing the founder arrived at: `10 ordered · 8 here ·
 * 2 moved out`. "Ordered" is derived from the two parts, so it can never
 * disagree with them.
 *
 * Returns null when there is nothing honest to say — either the endpoint
 * predates the fields (both undefined) or the job genuinely has no units.
 * Note the two are NOT interchangeable with 0: an absent field means
 * "unknown", a 0 means "none", and CLAUDE.md's standing rule is that an
 * untouched numeric column reads as 0, so the distinction has to be made
 * on presence, not on truthiness.
 */
export function unitRowLabel(entry: {unit_total?: number; units_moved_out?: number}): string | null {
  if (entry.unit_total === undefined && entry.units_moved_out === undefined) return null;
  const here = entry.unit_total ?? 0;
  const movedOut = entry.units_moved_out ?? 0;
  if (here === 0 && movedOut === 0) return null;
  if (movedOut === 0) return `${here} ordered`;
  return `${here + movedOut} ordered · ${here} here · ${movedOut} moved out`;
}
