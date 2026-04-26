import type {MatrixCell, Stage, MetricsActorFields, CustomerActorFields, InternalActorFields, EngineeringActorFields, AiAgentActorFields, HandoffActorFields, VendorActorFields, FinancialActorFields} from './types';
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

export const escapeHtml = (value: unknown): string =>
  String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

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

// ── Shared color utilities ──────────────────────────────────────────────────

/** Maps emotion text to a sentiment color and truncated display label. */
export const resolveEmotionColor = (emotions: unknown): {color: string; label: string} => {
  const raw = String(emotions ?? '');
  const lower = raw.toLowerCase();
  let color = '#f59e0b'; // yellow neutral default
  if (/frustrated|anxious|confused|overwhelmed|concerned|worried/.test(lower)) color = '#ef4444';
  else if (/confident|happy|satisfied|excited|relieved|positive/.test(lower)) color = '#22c55e';
  const label = raw.length > 18 ? `${raw.slice(0, 18)}\u2026` : raw || 'Neutral';
  return {color, label};
};

/** Maps a priority_score string to a display color. */
export const resolveFinancialPriorityColor = (priorityScore: unknown): string => {
  const lower = String(priorityScore ?? '').toLowerCase();
  if (lower.includes('high')) return '#ef4444';
  if (lower.includes('medium')) return '#f59e0b';
  if (lower.includes('low')) return '#22c55e';
  return '#a1a1aa';
};

// ── Tile formatter mini-helpers (private) ───────────────────────────────────
const ne = (v: unknown): v is string => v != null && String(v).trim() !== '';
const tileShell = (...parts: string[]) =>
  `<div style="display:flex;flex-direction:column;gap:3px">${parts.filter(Boolean).join('')}</div>`;
const tileHeader = (raw: string) => `<div class="jm-tile-header">${escapeHtml(raw)}</div>`;
const tileBody = (raw: string) => `<div class="jm-tile-body">${escapeHtml(raw)}</div>`;
const tileFlow = (html: string) => `<div class="jm-tile-flow">${html}</div>`;
const tileTags = (...tags: string[]) => {
  const filled = tags.filter(Boolean);
  return filled.length ? `<div class="jm-tile-tags">${filled.join('')}</div>` : '';
};
const tileTag = (cls: string, text: string) => `<span class="jm-tile-tag ${cls}">${text}</span>`;
const tileEmpty = (text: string) => `<div class="jm-tile-empty">${text}</div>`;

// ── Per-actor tile renderers ─────────────────────────────────────────────────

/** Customer: emotion badge → entry trigger → Pain Point tag */
export const formatCustomerTileMarkup = (fields: CustomerActorFields): string => {
  if (!ne(fields.emotions) && !ne(fields.entry_trigger) && !ne(fields.friction_points)) {
    return tileEmpty('👤 No data yet');
  }
  const {color, label} = resolveEmotionColor(fields.emotions);
  const badge = `<span class="jm-tile-emotion-badge" style="background:${color}">${escapeHtml(label)}</span>`;
  const action = ne(fields.entry_trigger)
    ? tileBody(fields.entry_trigger)
    : `<div class="jm-tile-body" style="color:#a1a1aa">—</div>`;
  return tileShell(badge, action, tileTags(ne(fields.friction_points) ? tileTag('pain', 'Pain Point') : ''));
};

/** Internal: task header → tools → Pain Point / Handoff tags */
export const formatInternalTileMarkup = (fields: InternalActorFields): string => {
  if (!ne(fields.task_objective) && !ne(fields.tools_systems) && !ne(fields.pain_points) && !ne(fields.handoff_dependencies)) {
    return tileEmpty('🏢 No data yet');
  }
  return tileShell(
    ne(fields.task_objective) ? tileHeader(`Task: ${fields.task_objective}`) : '',
    ne(fields.tools_systems) ? tileBody(`Tools: ${fields.tools_systems}`) : '',
    tileTags(
      ne(fields.pain_points) ? tileTag('pain', 'Pain Point') : '',
      ne(fields.handoff_dependencies) ? tileTag('handoff', 'Handoff \u2192') : '',
    ),
  );
};

/** Engineering: system header → data flow → Error States tag */
export const formatEngineeringTileMarkup = (fields: EngineeringActorFields): string => {
  if (!ne(fields.system_service_owner) && !ne(fields.data_inputs) && !ne(fields.data_outputs) && !ne(fields.error_states_edge_cases)) {
    return tileEmpty('⚙️ No data yet');
  }
  const flowHtml = (ne(fields.data_inputs) || ne(fields.data_outputs))
    ? tileFlow(`In: ${escapeHtml(fields.data_inputs ?? '\u2014')} \u2192 Out: ${escapeHtml(fields.data_outputs ?? '\u2014')}`)
    : '';
  return tileShell(
    ne(fields.system_service_owner) ? tileHeader(`System: ${fields.system_service_owner}`) : '',
    flowHtml,
    tileTags(ne(fields.error_states_edge_cases) ? tileTag('error', '\u26A0 Error States') : ''),
  );
};

/** AI Agent: model badge → decision flow → Confidence / Escalates tag */
export const formatAiAgentTileMarkup = (fields: AiAgentActorFields): string => {
  if (!ne(fields.ai_model_agent) && !ne(fields.input_data) && !ne(fields.decision_output) && !ne(fields.confidence_threshold) && !ne(fields.escalation_logic)) {
    return tileEmpty('🤖 No data yet');
  }
  const flowHtml = (ne(fields.input_data) || ne(fields.decision_output))
    ? tileFlow(`In: ${escapeHtml(fields.input_data ?? '\u2014')} \u2192 ${escapeHtml(fields.decision_output ?? '\u2014')}`)
    : '';
  return tileShell(
    tileHeader(`\uD83E\uDD16 ${fields.ai_model_agent ?? 'AI Agent'}`),
    flowHtml,
    ne(fields.confidence_threshold) ? tileBody(`Confidence: ${fields.confidence_threshold}`) : '',
    tileTags(ne(fields.escalation_logic) ? tileTag('escalation', 'Escalates') : ''),
  );
};

/** Financial: priority badge → cost/risk values → Revenue Leakage tag */
export const formatFinancialTileMarkup = (fields: FinancialActorFields): string => {
  if (!ne(fields.priority_score) && !ne(fields.cost_to_serve) && !ne(fields.revenue_at_risk) && !ne(fields.revenue_leakage)) {
    return tileEmpty('💰 No data yet');
  }
  const priorityColor = resolveFinancialPriorityColor(fields.priority_score);
  const badge = ne(fields.priority_score)
    ? `<span class="jm-tile-emotion-badge" style="background:${priorityColor}">${escapeHtml(`Priority: ${fields.priority_score}`.slice(0, 22))}</span>`
    : '';
  const costPart = ne(fields.cost_to_serve) ? `Cost: ${escapeHtml(fields.cost_to_serve)}` : '';
  const riskPart = ne(fields.revenue_at_risk) ? `Risk: ${escapeHtml(fields.revenue_at_risk)}` : '';
  const valuesHtml = (costPart || riskPart)
    ? `<div class="jm-tile-body">${[costPart, riskPart].filter(Boolean).join(' | ')}</div>`
    : '';
  return tileShell(badge, valuesHtml, tileTags(ne(fields.revenue_leakage) ? tileTag('risk', '\u26A0 Revenue Leakage') : ''));
};

/** Vendor: vendor header → role → SLA/cost → Failure Risk tag */
export const formatVendorTileMarkup = (fields: VendorActorFields): string => {
  if (!ne(fields.vendor_name_type) && !ne(fields.role_at_step) && !ne(fields.sla_performance_metrics) && !ne(fields.cost_impact) && !ne(fields.failure_scenario)) {
    return tileEmpty('🤝 No data yet');
  }
  const slaPart = ne(fields.sla_performance_metrics) ? `SLA: ${escapeHtml(fields.sla_performance_metrics)}` : '';
  const costPart = ne(fields.cost_impact) ? `Cost: ${escapeHtml(fields.cost_impact)}` : '';
  const slaHtml = (slaPart || costPart)
    ? `<div class="jm-tile-body">${[slaPart, costPart].filter(Boolean).join(' | ')}</div>`
    : '';
  return tileShell(
    ne(fields.vendor_name_type) ? tileHeader(`Vendor: ${fields.vendor_name_type}`) : '',
    ne(fields.role_at_step) ? tileBody(`Role: ${fields.role_at_step}`) : '',
    slaHtml,
    tileTags(ne(fields.failure_scenario) ? tileTag('error', '\u26A0 Failure Risk') : ''),
  );
};

/** Handoff: trigger header → upstream→downstream flow → Failure Recovery tag */
export const formatHandoffTileMarkup = (fields: HandoffActorFields): string => {
  if (!ne(fields.trigger_event) && !ne(fields.upstream_actor) && !ne(fields.downstream_actor) && !ne(fields.failure_recovery)) {
    return tileEmpty('\u21C4 No data yet');
  }
  let flowHtml = '';
  if (ne(fields.upstream_actor) || ne(fields.downstream_actor)) {
    const up = ne(fields.upstream_actor) ? escapeHtml(fields.upstream_actor) : '';
    const down = ne(fields.downstream_actor) ? escapeHtml(fields.downstream_actor) : '';
    const text = up && down ? `${up} \u2192 ${down}` : up ? `${up} \u2192` : `\u2192 ${down}`;
    flowHtml = tileFlow(text);
  }
  return tileShell(
    ne(fields.trigger_event) ? tileHeader(`Trigger: ${fields.trigger_event}`) : '',
    flowHtml,
    tileTags(ne(fields.failure_recovery) ? tileTag('error', '\u26A0 Failure Recovery') : ''),
  );
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

  // Tile actor types — render structured field-based tile instead of text + badge.
  const tileActorTypes = new Set(['customer', 'internal', 'engineering', 'ai_agent', 'financial', 'vendor', 'handoff']);
  if (tileActorTypes.has(actorType ?? '') && meta?.actorFields && typeof meta.actorFields === 'object') {
    let tile = '';
    switch (actorType) {
      case 'customer':     tile = formatCustomerTileMarkup(meta.actorFields as CustomerActorFields); break;
      case 'internal':     tile = formatInternalTileMarkup(meta.actorFields as InternalActorFields); break;
      case 'engineering':  tile = formatEngineeringTileMarkup(meta.actorFields as EngineeringActorFields); break;
      case 'ai_agent':     tile = formatAiAgentTileMarkup(meta.actorFields as AiAgentActorFields); break;
      case 'financial':    tile = formatFinancialTileMarkup(meta.actorFields as FinancialActorFields); break;
      case 'vendor':       tile = formatVendorTileMarkup(meta.actorFields as VendorActorFields); break;
      case 'handoff':      tile = formatHandoffTileMarkup(meta.actorFields as HandoffActorFields); break;
    }
    return `
      <div class="jm-grid-cell ${selectedClass}"${cellIdAttribute} style="position:relative">
        <div class="jm-grid-content" style="overflow:visible">${tile}</div>
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