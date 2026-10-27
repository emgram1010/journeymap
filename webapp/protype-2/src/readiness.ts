import type {ActorType} from './types';
import {toMinutes} from './durationModel';
import {doesPlannedWork} from './stageOwnerModel';

// AUTH-1 (US-AUTH-1-01) — pure readiness rules. No side effects; never
// mutates its inputs. Reason codes are stable identifiers, never prose —
// the UI maps them to copy, so wording can change without re-testing logic.
export type ReadinessReason =
  | 'NO_WORK_TYPE_NAME'
  | 'NO_STAGES'
  | 'NO_STAGE_NAME'
  | 'NO_OWNER'
  | 'OWNER_NOT_WORK_ROLE'
  | 'NO_TASK'
  | 'NO_DURATION'
  | 'PARTIAL_WORK_CELL';

export interface ReadinessLensInput {
  key: string;
  actorType?: ActorType | null;
  /** journey_lens_planned_work override — null/undefined = use the actor_type default. */
  doesPlannedWorkOverride?: boolean | null;
}

export interface ReadinessCellInput {
  lensKey: string;
  /** actor_fields.task_objective (or the template's equivalent task field). */
  task?: string | null;
  durationValue?: number | string | null;
  durationUnit?: string | null;
  /** True if ANY field on this cell (task, duration, notes, content, ...) has been filled in. */
  hasAnyContent: boolean;
}

export interface ReadinessStageInput {
  key: string;
  label?: string | null;
  /** The resolved owner's lens key (STAGE-1's owner_lens_id, read back by key). Null/undefined = no owner. */
  ownerLensKey?: string | null;
}

export interface StageReadinessResult {
  ready: boolean;
  reasons: ReadinessReason[];
}

/** Whether a cell has enough to satisfy the required-field rule (task + a valid duration). */
function cellSatisfiesRequirement(cell: ReadinessCellInput | undefined): boolean {
  if (!cell) return false;
  const hasTask = !!cell.task && cell.task.trim() !== '';
  const hasDuration = toMinutes(cell.durationValue ?? null, cell.durationUnit ?? null) != null;
  return hasTask && hasDuration;
}

// `readonly` on the inputs: these are pure functions that must never
// mutate what they're given (UT-AUTH-1-12 freezes its inputs to prove it),
// and a frozen array is `readonly` to TypeScript.
export function computeStageReadiness(
  stage: ReadinessStageInput,
  lenses: readonly ReadinessLensInput[],
  cells: readonly ReadinessCellInput[],
): StageReadinessResult {
  const reasons: ReadinessReason[] = [];

  if (!stage.label || stage.label.trim() === '') {
    reasons.push('NO_STAGE_NAME');
  }

  const ownerKey = stage.ownerLensKey;
  if (!ownerKey) {
    reasons.push('NO_OWNER');
  } else {
    const ownerLens = lenses.find((l) => l.key === ownerKey);
    const ownerIsWorkRole = !!ownerLens && doesPlannedWork(ownerLens.actorType ?? null, ownerLens.doesPlannedWorkOverride ?? null);

    if (!ownerIsWorkRole) {
      reasons.push('OWNER_NOT_WORK_ROLE');
    } else {
      const ownerCell = cells.find((c) => c.lensKey === ownerKey);
      const hasTask = !!ownerCell?.task && ownerCell.task.trim() !== '';
      const hasDuration = toMinutes(ownerCell?.durationValue ?? null, ownerCell?.durationUnit ?? null) != null;
      if (!hasTask) reasons.push('NO_TASK');
      if (!hasDuration) reasons.push('NO_DURATION');
    }
  }

  // Any OTHER work-doing row's cell for this stage: if it has anything
  // filled in, it must be fully filled (task + duration). Untouched cells
  // are never required — only the owner's cell is strictly required.
  for (const lens of lenses) {
    if (lens.key === ownerKey) continue;
    const isWorkRole = doesPlannedWork(lens.actorType ?? null, lens.doesPlannedWorkOverride ?? null);
    if (!isWorkRole) continue;

    const cell = cells.find((c) => c.lensKey === lens.key);
    if (!cell || !cell.hasAnyContent) continue;

    if (!cellSatisfiesRequirement(cell)) {
      reasons.push('PARTIAL_WORK_CELL');
    }
  }

  return {ready: reasons.length === 0, reasons};
}

export interface MapReadinessInput {
  workTypeName?: string | null;
}

export interface PerStageReadiness extends StageReadinessResult {
  stageKey: string;
}

export interface MapReadinessResult {
  ready: boolean;
  readyCount: number;
  total: number;
  perStage: PerStageReadiness[];
  mapReasons: ReadinessReason[];
}

export function computeMapReadiness(
  map: MapReadinessInput,
  stages: readonly ReadinessStageInput[],
  lenses: readonly ReadinessLensInput[],
  cellsByStage: Record<string, readonly ReadinessCellInput[]>,
): MapReadinessResult {
  const mapReasons: ReadinessReason[] = [];

  if (!map.workTypeName || map.workTypeName.trim() === '') {
    mapReasons.push('NO_WORK_TYPE_NAME');
  }
  if (stages.length === 0) {
    mapReasons.push('NO_STAGES');
  }

  const perStage: PerStageReadiness[] = stages.map((stage) => ({
    stageKey: stage.key,
    ...computeStageReadiness(stage, lenses, cellsByStage[stage.key] ?? []),
  }));

  const readyCount = perStage.filter((s) => s.ready).length;
  const total = perStage.length;
  const ready = mapReasons.length === 0 && total > 0 && readyCount === total;

  return {ready, readyCount, total, perStage, mapReasons};
}

// ── EXC-1 (US-EXC-1-01) — exception links: warn, never block ─────────────
//
// A stage's `exception` link says "work leaves this journey here and
// continues on that map". Readiness warns when that handoff could not
// actually happen yet, so the first real exception is not the moment the
// author finds out. These are WARNINGS: `ready` never changes.
//
// The inputs need database facts (is the target published? does it have an
// Items row? same architecture?), so the caller resolves them first — the
// backend's `exceptions/exception_targets`, mirrored here by whatever builds
// `targets` — and both sides run the same pure rule. Golden cases:
// `src/fixtures/exception-readiness-golden.json` (FT-EXC-1-16 runs the
// backend over the same file). `sub_journey` links are never passed in: a
// method's how-to is not a handoff (D-6).
//
// One warning per (stage, target), however many rows of that stage carry
// the link; checks in a fixed order: unpublished, items, architecture.
export type ExceptionWarningCode =
  | 'exception_map_unpublished'
  | 'exception_map_has_no_items_row'
  | 'exception_map_other_architecture';

export interface ExceptionTargetInput {
  stage_key: string;
  stage_label: string;
  lens_key: string;
  target_map_id: number;
  target_title: string;
  published: boolean;
  has_items_row: boolean;
  same_architecture: boolean;
}

export interface ExceptionWarning {
  code: ExceptionWarningCode;
  stage_key: string;
  lens_key: string;
  target_map_id: number;
  message: string;
}

export function exceptionLinkWarnings(
  sourceHasItemsRow: boolean,
  targets: readonly ExceptionTargetInput[],
): ExceptionWarning[] {
  const out: ExceptionWarning[] = [];
  const seen = new Set<string>();
  for (const t of targets) {
    const key = `${t.stage_key}::${t.target_map_id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const base = {stage_key: t.stage_key, lens_key: t.lens_key, target_map_id: t.target_map_id};
    const stage = t.stage_label;
    const target = t.target_title;
    if (!t.published) {
      out.push({
        ...base,
        code: 'exception_map_unpublished',
        message: `${stage} sends work to ${target}, which has never been published. Performers won't be able to send work there until it is.`,
      });
    }
    if (sourceHasItemsRow && !t.has_items_row) {
      out.push({
        ...base,
        code: 'exception_map_has_no_items_row',
        message: `Items sent from ${stage} to ${target} won't have an estimate there — ${target} has no Items row.`,
      });
    }
    if (!t.same_architecture) {
      out.push({
        ...base,
        code: 'exception_map_other_architecture',
        message: `${stage} links to a map in a different architecture; keep exception maps in the same architecture.`,
      });
    }
  }
  return out;
}
