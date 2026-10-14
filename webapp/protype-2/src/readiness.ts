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
