import type {PersistedJourneyCellUpdate} from './xano';
import type {CellStatus, Lens, MatrixCell, Stage} from './types';
import {resolveLensKey, resolveStageKey} from './cellIdentifiers';

const buildCellLookupKey = (stageId: string, lensId: string) => `${stageId}::${lensId}`;

export const normalizePersistedCellStatus = (value: CellStatus | null | undefined, fallback: CellStatus): CellStatus => {
  if (value === 'confirmed' || value === 'draft' || value === 'open') {
    return value;
  }
  return fallback;
};

export const mergePersistedCellUpdates = (
  currentCells: MatrixCell[],
  updates: PersistedJourneyCellUpdate[],
  stages: Stage[],
  lenses: Lens[],
) => {
  const activeUpdates = updates.filter((u) => !u.skipped);

  if (activeUpdates.length === 0 || currentCells.length === 0) {
    return currentCells;
  }

  const updatesByXanoId = new Map<number, PersistedJourneyCellUpdate>();
  const updatesByCompositeKey = new Map<string, PersistedJourneyCellUpdate>();
  const stageIdByXanoId = new Map<number, string>();
  const lensIdByXanoId = new Map<number, string>();
  const stageIdByKey = new Map<string, string>();
  const lensIdByKey = new Map<string, string>();

  stages.forEach((stage) => {
    stageIdByKey.set(stage.id, stage.id);
    stageIdByKey.set(resolveStageKey(stage), stage.id);
    if (typeof stage.xanoId === 'number') {
      stageIdByXanoId.set(stage.xanoId, stage.id);
    }
  });

  lenses.forEach((lens) => {
    lensIdByKey.set(lens.id, lens.id);
    lensIdByKey.set(resolveLensKey(lens), lens.id);
    if (typeof lens.xanoId === 'number') {
      lensIdByXanoId.set(lens.xanoId, lens.id);
    }
  });

  activeUpdates.forEach((update) => {
    updatesByXanoId.set(update.journeyCellId, update);

    const localStageId =
      (typeof update.stageId === 'number' ? stageIdByXanoId.get(update.stageId) : undefined) ??
      (update.stageKey ? stageIdByKey.get(update.stageKey) : undefined);
    const localLensId =
      (typeof update.lensId === 'number' ? lensIdByXanoId.get(update.lensId) : undefined) ??
      (update.lensKey ? lensIdByKey.get(update.lensKey) : undefined);

    if (localStageId && localLensId) {
      updatesByCompositeKey.set(buildCellLookupKey(localStageId, localLensId), update);
    }
  });

  return currentCells.map((cell) => {
    const directUpdate =
      (typeof cell.journeyCellId === 'number' ? updatesByXanoId.get(cell.journeyCellId) : undefined) ??
      (typeof cell.xanoId === 'number' ? updatesByXanoId.get(cell.xanoId) : undefined) ??
      (Number.isInteger(Number(cell.id)) ? updatesByXanoId.get(Number(cell.id)) : undefined) ??
      updatesByCompositeKey.get(buildCellLookupKey(cell.stageId, cell.lensId));

    if (!directUpdate) {
      return cell;
    }

    const nextLastUpdated = directUpdate.lastUpdatedAt ?? directUpdate.updatedAt;

    return {
      ...cell,
      journeyCellId: directUpdate.journeyCellId,
      journeyMapId: directUpdate.journeyMapId ?? cell.journeyMapId,
      xanoId: directUpdate.journeyCellId,
      stageXanoId: directUpdate.stageId ?? cell.stageXanoId,
      stageKey: directUpdate.stageKey ?? cell.stageKey ?? cell.stageId,
      content: directUpdate.content,
      lensXanoId: directUpdate.lensId ?? cell.lensXanoId,
      lensKey: directUpdate.lensKey ?? cell.lensKey ?? cell.lensId,
      status: normalizePersistedCellStatus(directUpdate.status, cell.status),
      isLocked: directUpdate.isLocked,
      lastUpdated: nextLastUpdated ? new Date(nextLastUpdated) : new Date(),
    };
  });
};