import type {Lens, MatrixCell, Stage} from './types';

export const resolveStageKey = (stage: Pick<Stage, 'id' | 'key'>) => stage.key?.trim() || stage.id;

export const resolveLensKey = (lens: Pick<Lens, 'id' | 'key'>) => lens.key?.trim() || lens.id;

export const buildCellReferenceLabel = (stageLabel?: string | null, lensLabel?: string | null): string | null => {
  if (!stageLabel || !lensLabel) {
    return null;
  }
  return `${stageLabel} × ${lensLabel}`;
};

export const buildCellShorthand = (
  cell: Pick<MatrixCell, 'stageId' | 'lensId'> | null | undefined,
  stages: Stage[],
  lenses: Lens[],
): string | null => {
  if (!cell) {
    return null;
  }
  const stageIndex = stages.findIndex((stage) => stage.id === cell.stageId);
  const lensIndex = lenses.findIndex((lens) => lens.id === cell.lensId);
  if (stageIndex === -1 || lensIndex === -1) {
    return null;
  }
  return `S${stageIndex + 1}-L${lensIndex + 1}`;
};

export interface CellUpdateSummary {
  reference: string;
  status: 'applied' | 'skipped';
  reason?: string | null;
}

const SKIP_REASON_LABELS: Record<string, string> = {
  locked: 'cell is locked',
  stale_target: 'stage or lens was deleted',
};

const formatSkipReason = (reason?: string | null): string | null => {
  if (!reason) return null;
  return SKIP_REASON_LABELS[reason] ?? reason;
};

export const buildCellUpdateSummaries = (
  appliedUpdates: {stageLabel?: string | null; lensLabel?: string | null}[],
  skippedUpdates: {stageLabel?: string | null; lensLabel?: string | null; skipReason?: string | null}[],
): CellUpdateSummary[] => {
  const summaries: CellUpdateSummary[] = [];

  for (const update of appliedUpdates) {
    const reference = buildCellReferenceLabel(update.stageLabel, update.lensLabel);
    summaries.push({reference: reference ?? 'Unknown cell', status: 'applied'});
  }

  for (const update of skippedUpdates) {
    const reference = buildCellReferenceLabel(update.stageLabel, update.lensLabel);
    const reason = formatSkipReason(update.skipReason);
    summaries.push({reference: reference ?? 'Unknown cell', status: 'skipped', reason});
  }

  return summaries;
};

export type CellResolutionResult =
  | {status: 'matched'; cell: MatrixCell}
  | {status: 'ambiguous'; candidates: MatrixCell[]; reason: string}
  | {status: 'not_found'; reason: string};

const SHORTHAND_PATTERN = /^S([0-9]+)-L([0-9]+)$/i;
const REFERENCE_SEPARATOR = /\s*[×x]\s*/i;

export const resolveCellReference = (
  reference: string,
  cells: MatrixCell[],
  stages: Stage[],
  lenses: Lens[],
): CellResolutionResult => {
  const trimmed = reference.trim();
  if (!trimmed) {
    return {status: 'not_found', reason: 'Empty reference.'};
  }

  // 1. Try canonical cell ID (numeric)
  const numericId = Number(trimmed);
  if (Number.isInteger(numericId) && numericId > 0) {
    const byId = cells.filter(
      (c) => c.journeyCellId === numericId || c.xanoId === numericId,
    );
    if (byId.length === 1) {
      return {status: 'matched', cell: byId[0]!};
    }
    if (byId.length > 1) {
      return {status: 'ambiguous', candidates: byId, reason: `Multiple cells match ID ${numericId}.`};
    }
    // Don't return not_found yet — could be a shorthand like "2"
  }

  // 2. Try shorthand (S2-L4)
  const shorthandMatch = trimmed.match(SHORTHAND_PATTERN);
  if (shorthandMatch) {
    const stageIndex = parseInt(shorthandMatch[1]!, 10) - 1;
    const lensIndex = parseInt(shorthandMatch[2]!, 10) - 1;
    const stage = stages[stageIndex];
    const lens = lenses[lensIndex];
    if (stage && lens) {
      const matched = cells.filter((c) => c.stageId === stage.id && c.lensId === lens.id);
      if (matched.length === 1) {
        return {status: 'matched', cell: matched[0]!};
      }
      if (matched.length > 1) {
        return {status: 'ambiguous', candidates: matched, reason: `Multiple cells at ${trimmed}.`};
      }
    }
    return {status: 'not_found', reason: `No cell found at position ${trimmed}.`};
  }

  // 3. Try "Stage × Lens" reference (labels first, then stable keys as fallback)
  const separatorMatch = trimmed.match(REFERENCE_SEPARATOR);
  if (separatorMatch) {
    const parts = trimmed.split(REFERENCE_SEPARATOR);
    if (parts.length === 2) {
      const stageQuery = parts[0]!.trim().toLowerCase();
      const lensQuery = parts[1]!.trim().toLowerCase();

      // Try labels first
      let matchedStages = stages.filter((s) => s.label.toLowerCase() === stageQuery);
      let matchedLenses = lenses.filter((l) => l.label.toLowerCase() === lensQuery);

      // Fall back to stable keys / ids
      if (matchedStages.length === 0) {
        matchedStages = stages.filter(
          (s) => resolveStageKey(s).toLowerCase() === stageQuery || s.id.toLowerCase() === stageQuery,
        );
      }
      if (matchedLenses.length === 0) {
        matchedLenses = lenses.filter(
          (l) => resolveLensKey(l).toLowerCase() === lensQuery || l.id.toLowerCase() === lensQuery,
        );
      }

      if (matchedStages.length === 0) {
        return {status: 'not_found', reason: `Stage "${parts[0]!.trim()}" not found.`};
      }
      if (matchedLenses.length === 0) {
        return {status: 'not_found', reason: `Lens "${parts[1]!.trim()}" not found.`};
      }

      const stageIds = new Set(matchedStages.map((s) => s.id));
      const lensIds = new Set(matchedLenses.map((l) => l.id));
      const matched = cells.filter((c) => stageIds.has(c.stageId) && lensIds.has(c.lensId));

      if (matched.length === 1) {
        return {status: 'matched', cell: matched[0]!};
      }
      if (matched.length > 1) {
        return {status: 'ambiguous', candidates: matched, reason: `Multiple cells match "${trimmed}".`};
      }
      return {status: 'not_found', reason: `No cell found for "${trimmed}".`};
    }
  }

  return {status: 'not_found', reason: `Unable to resolve "${trimmed}" to a cell.`};
};

export interface SelectedCellContext {
  reference: string;
  shorthand: string | null;
  journeyMapId: number | null;
  journeyCellId: number | null;
  stageId: number | null;
  stageKey: string;
  stageLabel: string;
  lensId: number | null;
  lensKey: string;
  lensLabel: string;
}

export const buildSelectedCellContext = ({
  cell,
  stages,
  lenses,
  journeyMapId,
}: {
  cell: MatrixCell | null | undefined;
  stages: Stage[];
  lenses: Lens[];
  journeyMapId?: number | null;
}): SelectedCellContext | null => {
  if (!cell) {
    return null;
  }

  const stage = stages.find((s) => s.id === cell.stageId);
  const lens = lenses.find((l) => l.id === cell.lensId);
  if (!stage || !lens) {
    return null;
  }

  const reference = buildCellReferenceLabel(stage.label, lens.label);
  if (!reference) {
    return null;
  }

  return {
    reference,
    shorthand: buildCellShorthand(cell, stages, lenses),
    journeyMapId: cell.journeyMapId ?? journeyMapId ?? null,
    journeyCellId: cell.journeyCellId ?? cell.xanoId ?? null,
    stageId: cell.stageXanoId ?? stage.xanoId ?? null,
    stageKey: cell.stageKey ?? resolveStageKey(stage),
    stageLabel: stage.label,
    lensId: cell.lensXanoId ?? lens.xanoId ?? null,
    lensKey: cell.lensKey ?? resolveLensKey(lens),
    lensLabel: lens.label,
  };
};