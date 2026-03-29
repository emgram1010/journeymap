import type {MatrixCell, Stage} from './types';

type ToggleableClassList = {
  toggle(className: string, force?: boolean): void;
};

type GridCellElementLike = {
  classList?: ToggleableClassList;
  dataset?: {cellId?: string};
};

type QueryableElementLike = {
  querySelector?(selector: string): unknown;
};

type CellLike = {
  getField?(): unknown;
  getElement?(): QueryableElementLike | null;
};

type RowLike = {
  getData(): {id?: string};
  getCells(): CellLike[];
};

type TableLike = {
  getRows(): RowLike[];
};

type FilterableTableLike = {
  clearFilter(): void;
  setFilter(predicate: (rowData: Record<string, string>) => boolean): void;
};

type ContainerLike = {
  contains(node: unknown): boolean;
};

export const escapeHtml = (value: string) =>
  value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

export const formatLensCellMarkup = (value: unknown) =>
  `<div class="jm-lens-cell">${escapeHtml(String(value ?? ''))}</div>`;

export const formatMatrixCellMarkup = ({
  content,
  meta,
  selectedCellId,
}: {
  content: unknown;
  meta?: MatrixCell;
  selectedCellId: string | null;
}) => {
  const contentText = String(content ?? '');
  const selectedClass = meta?.id === selectedCellId ? 'is-selected' : '';
  const indicatorClass = meta?.status === 'confirmed' ? 'confirmed' : meta?.status === 'draft' ? 'draft' : 'open';
  const indicator = meta?.isLocked
    ? '<span class="jm-status-indicator lock">🔒</span>'
    : `<span class="jm-status-indicator ${indicatorClass}"></span>`;
  const cellIdAttribute = meta?.id ? ` data-cell-id="${escapeHtml(meta.id)}"` : '';

  return `
    <div class="jm-grid-cell ${selectedClass}"${cellIdAttribute}>
      <div class="jm-grid-content ${contentText ? '' : 'is-empty'}">${contentText ? escapeHtml(contentText) : 'No data'}</div>
      <div class="jm-grid-meta">${indicator}</div>
    </div>
  `;
};

export const syncSelectedMatrixCellClasses = (
  table: TableLike,
  cellMap: Map<string, MatrixCell>,
  selectedCellId: string | null,
) => {
  table.getRows().forEach((row) => {
    const lensId = String(row.getData().id);

    row.getCells().forEach((cell) => {
      const field = String(cell.getField?.() ?? '');
      if (!field || field === 'lensLabel') {
        return;
      }

      const gridCell = cell.getElement?.()?.querySelector?.('.jm-grid-cell') as GridCellElementLike | null | undefined;
      if (!gridCell?.classList?.toggle) {
        return;
      }

      const meta = cellMap.get(`${field}:${lensId}`);
      gridCell.classList.toggle('is-selected', Boolean(meta?.id && meta.id === selectedCellId));
    });
  });
};

const rowMatchesMatrixSearchQuery = (rowData: Record<string, string>, query: string, stages: Stage[]) => {
  if (String(rowData.lensLabel ?? '').toLowerCase().includes(query)) {
    return true;
  }

  return stages.some((stage) => String(rowData[stage.id] ?? '').toLowerCase().includes(query));
};

export const applyMatrixSearchFilter = (table: FilterableTableLike, searchTerm: string, stages: Stage[]) => {
  const query = searchTerm.trim().toLowerCase();
  if (!query) {
    table.clearFilter();
    return;
  }

  table.setFilter((rowData) => rowMatchesMatrixSearchQuery(rowData, query, stages));
};

export const findMatrixCellIdFromClickTarget = (
  target: EventTarget | null,
  container: ContainerLike | null,
) => {
  const closestTarget = target as (EventTarget & {closest?(selector: string): unknown}) | null;
  const gridCell = closestTarget?.closest?.('.jm-grid-cell[data-cell-id]') as GridCellElementLike | null | undefined;

  if (!gridCell) {
    return null;
  }

  if (container && !container.contains(gridCell)) {
    return null;
  }

  return gridCell.dataset?.cellId ?? null;
};