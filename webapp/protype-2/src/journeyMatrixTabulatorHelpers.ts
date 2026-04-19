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

export const formatLensCellMarkup = ({
  label,
  actorType,
  lensId,
}: {
  label: string;
  actorType?: string;
  lensId?: string;
}) => {
  const pill = actorType
    ? `<span class="jm-lens-actor-pill">${escapeHtml(actorType.replace('_', ' '))}</span>`
    : '';
  const editBtn = lensId
    ? `<button class="jm-lens-edit-btn" data-edit-lens-id="${escapeHtml(lensId)}" title="Edit actor role" type="button">✎</button>`
    : '';
  return `<div class="jm-lens-cell">${editBtn}<div class="jm-lens-cell-body"><span class="jm-lens-label">${escapeHtml(label)}</span>${pill}</div></div>`;
};

const LINK_TYPE_ICON: Record<string, string> = {
  exception: '⚠',
  anti_journey: '↩',
  sub_journey: '⤵',
};

export interface CellLinkInfo {
  linkType: string;
  targetMapId: number;
}

export const formatMatrixCellMarkup = ({
  content,
  meta,
  selectedCellId,
  linkedCells,
}: {
  content: unknown;
  meta?: MatrixCell;
  selectedCellId: string | null;
  linkedCells?: Map<number, CellLinkInfo>;
}) => {
  const contentText = String(content ?? '');
  const selectedClass = meta?.id === selectedCellId ? 'is-selected' : '';
  const indicatorClass = meta?.status === 'confirmed' ? 'confirmed' : meta?.status === 'draft' ? 'draft' : 'open';
  const indicator = meta?.isLocked
    ? '<span class="jm-status-indicator lock">🔒</span>'
    : `<span class="jm-status-indicator ${indicatorClass}"></span>`;
  const cellIdAttribute = meta?.id ? ` data-cell-id="${escapeHtml(meta.id)}"` : '';

  // Actor field count badge — shown when the cell has structured actor fields.
  let actorBadge = '';
  if (meta?.actorFields && typeof meta.actorFields === 'object') {
    const fields = Object.values(meta.actorFields as Record<string, string | null>);
    const total = fields.length;
    const filled = fields.filter((v) => v !== null && v !== '').length;
    if (total > 0) {
      const badgeClass = filled === total ? 'jm-actor-badge complete' : filled > 0 ? 'jm-actor-badge partial' : 'jm-actor-badge empty';
      actorBadge = `<span class="${badgeClass}">${filled}/${total}</span>`;
    }
  }

  // Primary display: prefer actor badge summary, fall back to content text.
  const hasContent = contentText.length > 0;
  const hasActorFields = actorBadge !== '';
  const displayText = hasContent ? escapeHtml(contentText) : 'No data';
  const isEmpty = !hasContent && !hasActorFields;

  // Breakpoint indicator — shown when this cell is the source of a journey link.
  let linkIndicator = '';
  if (meta?.xanoId && linkedCells?.has(meta.xanoId)) {
    const info = linkedCells.get(meta.xanoId)!;
    const icon = LINK_TYPE_ICON[info.linkType] ?? '→';
    linkIndicator = `<span class="jm-link-indicator" data-link-target="${info.targetMapId}" title="View linked map →" style="position:absolute;bottom:4px;right:20px;font-size:11px;cursor:pointer;opacity:0.7;line-height:1">${icon}</span>`;
  }

  return `
    <div class="jm-grid-cell ${selectedClass}"${cellIdAttribute} style="position:relative">
      <div class="jm-grid-content ${isEmpty ? 'is-empty' : ''}"${hasContent ? ` title="${escapeHtml(contentText)}"` : ''}>${displayText}</div>
      <div class="jm-grid-meta">${actorBadge}${indicator}</div>
      ${linkIndicator}
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