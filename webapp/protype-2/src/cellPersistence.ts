import type {MatrixCell} from './types';

export const cloneCellSnapshot = (cell: MatrixCell | null | undefined): MatrixCell | null => (cell ? {...cell} : null);

export const resolveCellPersistenceBaseline = (
  rollbackCell?: MatrixCell | null,
  selectedCellSnapshot?: MatrixCell | null,
) => rollbackCell ?? selectedCellSnapshot ?? null;

export const hasPendingCellChanges = (cell: MatrixCell | null | undefined, snapshot: MatrixCell | null | undefined) => {
  if (!cell || !snapshot) {
    return false;
  }

  return cell.content !== snapshot.content || cell.status !== snapshot.status || Boolean(cell.isLocked) !== Boolean(snapshot.isLocked);
};