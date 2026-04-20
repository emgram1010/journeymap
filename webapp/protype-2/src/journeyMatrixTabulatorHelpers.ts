import type {MatrixCell, Stage, MetricsActorFields} from './types';
import {parseMetricValue, calcStageHealth} from './types';
import {METRICS_THRESHOLDS, getMetricColor} from './constants';

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

const METRIC_DOT_COLOR: Record<string, string> = {green: '#22c55e', yellow: '#f59e0b', red: '#ef4444'};

/** Renders a compact scorecard chip for a metrics actor cell. */
const formatMetricsScorecardMarkup = (fields: MetricsActorFields): string => {
  const f = fields;
  const health = f.stage_health != null ? parseMetricValue(f.stage_health) : calcStageHealth(f);
  const healthColor = METRIC_DOT_COLOR[getMetricColor('stage_health', health)];

  const dot = (key: string, val: number | null) =>
    `<span style="display:inline-block;width:7px;height:7px;border-radius:50%;background:${METRIC_DOT_COLOR[getMetricColor(key, val)]};flex-shrink:0"></span>`;

  const metricPairs: Array<[string, string, number | null, string]> = [
    ['csat_score',          'CSAT',       parseMetricValue(f.csat_score),          '/10'],
    ['completion_rate',     'Done',        parseMetricValue(f.completion_rate),     '%'],
    ['drop_off_rate',       'Drop-off',   parseMetricValue(f.drop_off_rate),       '%'],
    ['error_rate',          'Errors',     parseMetricValue(f.error_rate),          '%'],
    ['sla_compliance_rate', 'SLA',        parseMetricValue(f.sla_compliance_rate), '%'],
  ];

  const pairRows = metricPairs
    .filter(([, , v]) => v != null)
    .map(([key, label, val, unit]) =>
      `<div style="display:flex;align-items:center;gap:3px;min-width:0">
        <span style="font-size:9px;color:#71717a;white-space:nowrap">${label}</span>
        <span style="font-size:10px;font-weight:600;color:#18181b">${val}${unit}</span>
        ${dot(key, val)}
      </div>`,
    )
    .join('');

  const hasAnyField = health != null || pairRows !== '';

  if (!hasAnyField) {
    return `<div style="display:flex;align-items:center;gap:4px;padding:2px 0;color:#a1a1aa;font-size:10px">📊 No metrics yet</div>`;
  }

  const healthDisplay = health != null
    ? `<span style="font-size:13px;font-weight:700;color:#18181b">${health.toFixed(1)}</span>
       <span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${healthColor};margin-left:3px"></span>`
    : `<span style="font-size:11px;color:#a1a1aa">—</span>`;

  return `<div style="display:flex;flex-direction:column;gap:3px;padding:1px 0">
    <div style="display:flex;align-items:center;gap:4px">
      <span style="font-size:9px;color:#71717a;font-weight:500">Health</span>
      ${healthDisplay}
    </div>
    ${pairRows !== '' ? `<div style="display:flex;flex-wrap:wrap;gap:4px 8px">${pairRows}</div>` : ''}
  </div>`;
};

export const formatMatrixCellMarkup = ({
  content,
  meta,
  selectedCellId,
  linkedCells,
  actorType,
}: {
  content: unknown;
  meta?: MatrixCell;
  selectedCellId: string | null;
  linkedCells?: Map<number, CellLinkInfo>;
  actorType?: string;
}) => {
  const contentText = String(content ?? '');
  const selectedClass = meta?.id === selectedCellId ? 'is-selected' : '';
  const indicatorClass = meta?.status === 'confirmed' ? 'confirmed' : meta?.status === 'draft' ? 'draft' : 'open';
  const indicator = meta?.isLocked
    ? '<span class="jm-status-indicator lock">🔒</span>'
    : `<span class="jm-status-indicator ${indicatorClass}"></span>`;
  const cellIdAttribute = meta?.id ? ` data-cell-id="${escapeHtml(meta.id)}"` : '';

  // Breakpoint indicator
  let linkIndicator = '';
  if (meta?.xanoId && linkedCells?.has(meta.xanoId)) {
    const info = linkedCells.get(meta.xanoId)!;
    const icon = LINK_TYPE_ICON[info.linkType] ?? '→';
    linkIndicator = `<span class="jm-link-indicator" data-link-target="${info.targetMapId}" title="View linked map →" style="position:absolute;bottom:4px;right:20px;font-size:11px;cursor:pointer;opacity:0.7;line-height:1">${icon}</span>`;
  }

  // Metrics actor — render compact scorecard instead of text + badge.
  if (actorType === 'metrics' && meta?.actorFields && typeof meta.actorFields === 'object') {
    const scorecard = formatMetricsScorecardMarkup(meta.actorFields as MetricsActorFields);
    return `
      <div class="jm-grid-cell ${selectedClass}"${cellIdAttribute} style="position:relative">
        <div class="jm-grid-content" style="overflow:visible">${scorecard}</div>
        <div class="jm-grid-meta">${indicator}</div>
        ${linkIndicator}
      </div>
    `;
  }

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