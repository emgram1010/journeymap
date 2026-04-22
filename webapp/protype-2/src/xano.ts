import type {ActorFields, ActorType, CellStatus, Lens, MatrixCell, Message, Stage, ToolTraceEntry} from './types';
import type {SelectedCellContext} from './cellIdentifiers';

export type JourneyMapStatus = 'draft' | 'active' | 'archived';
export type ConversationMode = 'interview' | 'chat';

export interface JourneySettings {
  primary_actor?: string | null;
  journey_scope?: string | null;
  start_point?: string | null;
  end_point?: string | null;
  duration?: string | null;
  success_metrics?: string | null;
  key_stakeholders?: string | null;
  dependencies?: string | null;
  pain_points_summary?: string | null;
  opportunities?: string | null;
  version?: string | null;
}

export type InterviewDepth = 'strategic' | 'discovery' | 'rapid_capture';
export type InsightStandard = 'surface' | 'discovery' | 'deep_dive';
export type LensPriority = 'balanced' | 'customer' | 'operations' | 'engineering';

export interface SmartAiSettings {
  interview_depth?: InterviewDepth | null;
  insight_standard?: InsightStandard | null;
  lens_priority?: LensPriority | null;
  emotional_mapping?: boolean | null;
  business_impact_framing?: boolean | null;
  auto_confirm_writes?: boolean | null;
  show_reasoning?: boolean | null;
}

export const SMART_AI_DEFAULTS: Required<SmartAiSettings> = {
  interview_depth: 'discovery',
  insight_standard: 'discovery',
  lens_priority: 'balanced',
  emotional_mapping: false,
  business_impact_framing: false,
  auto_confirm_writes: false,
  show_reasoning: true,
};

export interface XanoJourneyMap extends JourneySettings {
  id: number;
  created_at: number | string;
  updated_at?: string;
  title: string;
  status: JourneyMapStatus;
  owner_user?: number | null;
  account_id?: number | null;
  last_interaction_at?: string | null;
  settings?: Record<string, unknown> | null;
  smart_ai_settings?: SmartAiSettings | null;
  // Non-null when this map belongs to a Journey Architecture.
  journey_architecture?: number | null;
  // Non-null when this map was cloned from another map.
  cloned_from_map_id?: number | null;
}

// Lightweight scenario record returned by GET /journey_architecture/{id}/scenarios.
export interface XanoScenario {
  id: number;
  title: string;
  owner_name: string;
  created_at: number | string;
  updated_at: string | null;
  cloned_from_map_id: number | null;
}

export interface XanoJourneyStage {
  id: number;
  journey_map: number;
  key?: string | null;
  label: string;
  display_order?: number | null;
}

export interface XanoJourneyLens {
  id: number;
  journey_map: number;
  key?: string | null;
  label: string;
  display_order?: number | null;
  // Actor identity fields
  actor_type?: string | null;
  template_key?: string | null;
  role_prompt?: string | null;
  persona_description?: string | null;
  primary_goal?: string | null;
  standing_constraints?: string | null;
}

export interface XanoJourneyCell {
  id: number;
  created_at?: number | string | null;
  updated_at?: string | null;
  journey_map: number;
  stage: number;
  lens: number;
  content?: string | null;
  status?: CellStatus | null;
  is_locked?: boolean | null;
  change_source?: string | null;
  last_updated_at?: string | null;
  journey_map_updated_at?: string | null;
  actor_fields?: Record<string, unknown> | null;
}

export interface XanoAgentConversation {
  id: number;
  journey_map?: number | null;
  title?: string | null;
  mode?: ConversationMode | null;
  last_message_at?: string | null;
}

export interface XanoAgentMessage {
  id: number;
  conversation: number;
  role?: 'system' | 'user' | 'assistant' | 'tool' | null;
  mode?: ConversationMode | null;
  content?: unknown;
  created_at?: number | string | null;
}

export interface PersistedJourneyCellUpdate {
  journeyCellId: number;
  journeyMapId?: number | null;
  stageId?: number | null;
  stageKey?: string | null;
  stageLabel?: string | null;
  lensId?: number | null;
  lensKey?: string | null;
  lensLabel?: string | null;
  content: string;
  status: CellStatus;
  changeSource?: string | null;
  isLocked: boolean;
  updatedAt?: string | null;
  lastUpdatedAt?: string | null;
  skipped: boolean;
  skipReason?: string | null;
}

export interface HydratedJourneyMapBundle {
  journeyMap: XanoJourneyMap;
  stages: Stage[];
  lenses: Lens[];
  cells: MatrixCell[];
  conversation: XanoAgentConversation | null;
  messages: Message[];
  source: 'business' | 'crud';
  hasHydratedMatrix: boolean;
}

export interface PersistedConversationThread {
  conversation: XanoAgentConversation | null;
  messages: Message[];
  proposedUpdates: PersistedJourneyCellUpdate[];
  appliedUpdates: PersistedJourneyCellUpdate[];
  skippedUpdates: PersistedJourneyCellUpdate[];
  journeyMapUpdatedAt?: string | null;
}

type CreateDraftJourneyMapInput = {
  title?: string;
  status?: JourneyMapStatus;
  settings?: Record<string, unknown>;
  // owner_user is derived from the auth token on the backend — not sent from the client
  account_id?: number;
  // When provided the map is grouped under this architecture and inherits its ownership
  journey_architecture_id?: number;
};

type SendJourneyMapMessageInput = {
  journeyMapId: number;
  conversationId?: number | null;
  content: string;
  mode: ConversationMode;
  assistantReply?: string;
  selectedCell?: SelectedCellContext | null;
};

type RenameJourneyStageInput = {
  journeyStageId: number;
  label: string;
};

type RenameJourneyLensInput = {
  journeyLensId: number;
  label: string;
};

type AddJourneyStageInput = {
  journeyMapId: number;
  label?: string;
};

type RemoveJourneyStageInput = {
  journeyStageId: number;
};

type AddJourneyLensInput = {
  journeyMapId: number;
  label?: string;
  actorType?: ActorType;
  templateKey?: string;
  rolePrompt?: string;
  personaDescription?: string;
  primaryGoal?: string;
  standingConstraints?: string;
};

type UpdateLensActorFieldsInput = {
  journeyLensId: number;
  label?: string;
  actorType?: ActorType;
  templateKey?: string;
  rolePrompt?: string;
  personaDescription?: string;
  primaryGoal?: string;
  standingConstraints?: string;
};

type RemoveJourneyLensInput = {
  journeyLensId: number;
};

type UpdateJourneyCellInput = {
  journeyCellId: number;
  content?: string;
  status?: CellStatus;
  isLocked?: boolean;
  /** Structured actor-specific fields — only sent when explicitly changed. */
  actorFields?: ActorFields | null;
};

type BusinessBundleResponse = {
  journey_map?: XanoJourneyMap;
  journeyMap?: XanoJourneyMap;
  map?: XanoJourneyMap;
  stages?: XanoJourneyStage[];
  lenses?: XanoJourneyLens[];
  cells?: XanoJourneyCell[];
  conversation?: XanoAgentConversation | null;
  messages?: XanoAgentMessage[];
  conversation_messages?: XanoAgentMessage[];
};

type ConversationThreadResponse = {
  conversation?: XanoAgentConversation | null;
  messages?: XanoAgentMessage[];
  proposed_updates?: unknown[];
  applied_updates?: unknown[];
  skipped_updates?: unknown[];
  journey_map_updated_at?: string | null;
};

export interface AiCellUpdate {
  cell_id: number;
  stage_id: number;
  lens_id: number;
  content?: string | null;
  status?: string | null;
  change_source?: string | null;
  is_locked?: boolean | null;
}

export interface AiToolTraceEntry {
  tool_name: string;
  tool_category: 'read' | 'write' | 'status' | 'structure';
  input_summary: string;
  output_summary: string;
  execution_order: number;
}

export interface AiStructuralChanges {
  stages_changed: boolean;
  lenses_changed: boolean;
  current_stages?: XanoJourneyStage[];
  current_lenses?: XanoJourneyLens[];
}

export interface AiSkippedUpdate {
  tool_name: string;
  target: string;
  skip_reason: string;
}

export interface AiMessageResponse {
  reply: string;
  cell_updates: AiCellUpdate[];
  skipped_updates?: AiSkippedUpdate[];
  suggested_prompts?: string[];
  structural_changes: AiStructuralChanges;
  progress: {
    total_cells: number;
    filled_cells: number;
    percentage: number;
  };
  conversation: XanoAgentConversation | null;
  messages: XanoAgentMessage[];
  tool_trace?: AiToolTraceEntry[];
  thinking?: string | null;
  turn_log?: {
    turn_id?: string | null;
    tool_count?: number | null;
    status?: string | null;
    error_message?: string | null;
  } | null;
}

export interface ToolLogEntry {
  id: number;
  tool_name: string;
  tool_category: 'read' | 'write' | 'status' | 'structure';
  input_summary: string;
  output_summary: string;
  execution_order: number;
  created_at?: string | null;
}

export interface ToolLogsResponse {
  journey_map_id: number;
  turn_id: string;
  count: number;
  tool_calls: ToolLogEntry[];
}

export interface ConversationListItem {
  id: number;
  journey_map: number;
  title: string | null;
  mode: ConversationMode | null;
  last_message_at: string | null;
  created_at: number | string | null;
  message_count: number;
}

export interface ConversationWithMessages {
  conversation: XanoAgentConversation;
  messages: Message[];
}

export interface PersistedAiConversationThread {
  reply: string;
  cellUpdates: AiCellUpdate[];
  skippedUpdates: AiSkippedUpdate[];
  suggestedPrompts: string[];
  structuralChanges: AiStructuralChanges;
  progress: {
    totalCells: number;
    filledCells: number;
    percentage: number;
  };
  conversation: XanoAgentConversation | null;
  messages: Message[];
  toolTrace: ToolTraceEntry[];
  thinking: string | null;
  /** Debug: turn_id for fetching per-tool logs via /tool-logs endpoint */
  turnId: string | null;
  /** Debug: true when tool_count >= 18 (step limit warning) */
  stepLimitWarning: boolean;
}

export type SelectedCellPayload = {
  journey_map_id?: number;
  stage_id?: number;
  stage_key: string;
  stage_label: string;
  lens_id?: number;
  lens_key: string;
  lens_label: string;
  reference: string;
  shorthand?: string;
  journey_cell_id?: number;
};

export const buildSelectedCellPayload = (selectedCell?: SelectedCellContext | null): SelectedCellPayload | null => {
  if (!selectedCell) {
    return null;
  }

  const payload: SelectedCellPayload = {
    stage_key: selectedCell.stageKey,
    stage_label: selectedCell.stageLabel,
    lens_key: selectedCell.lensKey,
    lens_label: selectedCell.lensLabel,
    reference: selectedCell.reference,
  };

  if (typeof selectedCell.journeyMapId === 'number' && Number.isFinite(selectedCell.journeyMapId)) {
    payload.journey_map_id = selectedCell.journeyMapId;
  }

  if (typeof selectedCell.journeyCellId === 'number' && Number.isFinite(selectedCell.journeyCellId)) {
    payload.journey_cell_id = selectedCell.journeyCellId;
  }

  if (typeof selectedCell.stageId === 'number' && Number.isFinite(selectedCell.stageId)) {
    payload.stage_id = selectedCell.stageId;
  }

  if (typeof selectedCell.lensId === 'number' && Number.isFinite(selectedCell.lensId)) {
    payload.lens_id = selectedCell.lensId;
  }

  if (selectedCell.shorthand) {
    payload.shorthand = selectedCell.shorthand;
  }

  return payload;
};

export interface ParentJourneyContext {
  link_type: JourneyLinkType;
  parent_map_id: number;
  parent_map_title: string;
  source_cell_id: number;
  source_stage_label: string;
  source_lens_label: string;
  trigger_content: string | null;
}

type SendAiMessageInput = {
  journeyMapId: number;
  conversationId?: number | null;
  content: string;
  mode: ConversationMode;
  selectedCell?: SelectedCellPayload | null;
  journeySettings?: JourneySettings | null;
  parentContext?: ParentJourneyContext | null;
};

const DEFAULT_XANO_BASE_URL = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ';
const DEFAULT_XANO_CREATE_DRAFT_PATH = '/journey_map/create_draft';
const DEFAULT_XANO_LOAD_MAP_PATH = '/journey_map/load_bundle/:journeyMapId';
const DEFAULT_XANO_MESSAGE_PATH = '/journey_map/:journeyMapId/message';
const DEFAULT_XANO_UPDATE_CELL_PATH = '/journey_cell/update/:journeyCellId';
const DEFAULT_XANO_RENAME_STAGE_PATH = '/journey_stage/rename/:journeyStageId';
const DEFAULT_XANO_RENAME_LENS_PATH = '/journey_lens/rename/:journeyLensId';
const DEFAULT_XANO_ADD_STAGE_PATH = '/journey_stage/add/:journeyMapId';
const DEFAULT_XANO_REMOVE_STAGE_PATH = '/journey_stage/remove/:journeyStageId';
const DEFAULT_XANO_ADD_LENS_PATH = '/journey_lens/add/:journeyMapId';
const DEFAULT_XANO_REMOVE_LENS_PATH = '/journey_lens/remove/:journeyLensId';
const DEFAULT_XANO_AI_MESSAGE_PATH = '/journey_map/:journeyMapId/ai_message';
const DEFAULT_XANO_JOURNEY_SETTINGS_PATH = '/journey_map/settings/:journeyMapId';
const DEFAULT_XANO_SMART_AI_SETTINGS_PATH = '/journey_map/smart_ai_settings/:journeyMapId';
const DEFAULT_XANO_LENS_ACTOR_FIELDS_PATH = '/journey_lens/actor_fields/:journeyLensId';

const trimTrailingSlash = (value: string) => value.replace(/\/+$/, '');

const normalizeOptionalPath = (value?: string | null) => {
  const trimmed = value?.trim();
  if (!trimmed) {
    return null;
  }
  return trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
};

const normalizeCellStatus = (value?: string | null): CellStatus => {
  if (value === 'confirmed' || value === 'draft' || value === 'open') {
    return value;
  }
  return 'open';
};

const normalizeConversationMode = (value?: string | null): ConversationMode => (value === 'chat' ? 'chat' : 'interview');

const toEpoch = (value?: number | string | null) => {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string') {
    const numericValue = Number(value);
    if (Number.isFinite(numericValue) && value.trim() !== '') {
      return numericValue;
    }

    const parsedDate = Date.parse(value);
    if (!Number.isNaN(parsedDate)) {
      return parsedDate;
    }
  }

  return 0;
};

const extractTextFromMessageContent = (value: unknown): string => {
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value)) {
    return value
      .map((entry) => extractTextFromMessageContent(entry))
      .filter((entry) => entry.length > 0)
      .join('\n')
      .trim();
  }

  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    const directText = typeof record.text === 'string' ? record.text : '';
    const nestedText = extractTextFromMessageContent(record.content);
    return [directText, nestedText].filter((entry) => entry.length > 0).join('\n').trim();
  }

  return '';
};

const normalizeMessageRole = (value?: string | null): Message['role'] => (value === 'user' ? 'expert' : 'ai');

const normalizeRecordKey = (value: string | null | undefined, fallbackId: number, prefix: 'stage' | 'lens') => {
  const trimmed = value?.trim();
  return trimmed || `${prefix}-${fallbackId}`;
};

const sortByDisplayOrder = <T extends {display_order?: number | null; id: number}>(records: T[]) =>
  [...records].sort((left, right) => (left.display_order ?? 0) - (right.display_order ?? 0) || left.id - right.id);

export const getXanoBaseUrl = () => {
  const configuredBaseUrl = import.meta.env.VITE_XANO_BASE_URL?.trim();
  return trimTrailingSlash(configuredBaseUrl || DEFAULT_XANO_BASE_URL);
};

export const getXanoCreateDraftPath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_CREATE_DRAFT_PATH) ?? DEFAULT_XANO_CREATE_DRAFT_PATH;

export const getXanoLoadMapPath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_LOAD_MAP_PATH) ?? DEFAULT_XANO_LOAD_MAP_PATH;

export const getXanoMessagePath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_MESSAGE_PATH) ?? DEFAULT_XANO_MESSAGE_PATH;

export const getXanoUpdateCellPath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_UPDATE_CELL_PATH) ?? DEFAULT_XANO_UPDATE_CELL_PATH;

export const getXanoRenameStagePath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_RENAME_STAGE_PATH) ?? DEFAULT_XANO_RENAME_STAGE_PATH;

export const getXanoRenameLensPath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_RENAME_LENS_PATH) ?? DEFAULT_XANO_RENAME_LENS_PATH;

export const getXanoAddStagePath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_ADD_STAGE_PATH) ?? DEFAULT_XANO_ADD_STAGE_PATH;

export const getXanoRemoveStagePath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_REMOVE_STAGE_PATH) ?? DEFAULT_XANO_REMOVE_STAGE_PATH;

export const getXanoAddLensPath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_ADD_LENS_PATH) ?? DEFAULT_XANO_ADD_LENS_PATH;

export const getXanoRemoveLensPath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_REMOVE_LENS_PATH) ?? DEFAULT_XANO_REMOVE_LENS_PATH;

export const getXanoAiMessagePath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_AI_MESSAGE_PATH) ?? DEFAULT_XANO_AI_MESSAGE_PATH;

export const getXanoJourneySettingsPath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_JOURNEY_SETTINGS_PATH) ?? DEFAULT_XANO_JOURNEY_SETTINGS_PATH;

export const getXanoSmartAiSettingsPath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_SMART_AI_SETTINGS_PATH) ?? DEFAULT_XANO_SMART_AI_SETTINGS_PATH;

export const getXanoLensActorFieldsPath = () => normalizeOptionalPath(import.meta.env.VITE_XANO_LENS_ACTOR_FIELDS_PATH) ?? DEFAULT_XANO_LENS_ACTOR_FIELDS_PATH;

// ── Auth API group ──────────────────────────────────────────────────────────
const DEFAULT_XANO_AUTH_BASE_URL = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:RPonubWS';
export const getXanoAuthBaseUrl = () => trimTrailingSlash(import.meta.env.VITE_XANO_AUTH_BASE_URL?.trim() || DEFAULT_XANO_AUTH_BASE_URL);
export const getAuthToken = () => (typeof localStorage !== 'undefined' ? localStorage.getItem('authToken') : null);

type RequestOptions = {
  method?: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
  body?: Record<string, unknown>;
};

class XanoHttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = 'XanoHttpError';
  }
}

async function xanoRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const {method = 'GET', body} = options;
  const token = getAuthToken();
  const headers: Record<string, string> = {Accept: 'application/json'};
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (body) headers['Content-Type'] = 'application/json';
  const response = await fetch(`${getXanoBaseUrl()}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  const responseText = await response.text();

  if (!response.ok) {
    throw new XanoHttpError(
      response.status,
      `Xano ${method} ${path} failed (${response.status}): ${responseText || response.statusText}`,
    );
  }

  return responseText ? (JSON.parse(responseText) as T) : (undefined as T);
}

async function authXanoRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const {method = 'GET', body} = options;
  const token = getAuthToken();
  const headers: Record<string, string> = {Accept: 'application/json'};
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (body) headers['Content-Type'] = 'application/json';
  const response = await fetch(`${getXanoAuthBaseUrl()}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  const responseText = await response.text();

  if (!response.ok) {
    throw new XanoHttpError(
      response.status,
      `Auth ${method} ${path} failed (${response.status}): ${responseText || response.statusText}`,
    );
  }

  return responseText ? (JSON.parse(responseText) as T) : (undefined as T);
}

const listJourneyStages = () => xanoRequest<XanoJourneyStage[]>('/journey_stage');

const listJourneyLenses = () => xanoRequest<XanoJourneyLens[]>('/journey_lens');

const listJourneyCells = () => xanoRequest<XanoJourneyCell[]>('/journey_cell');

const createJourneyMap = (input: CreateDraftJourneyMapInput) =>
  xanoRequest<XanoJourneyMap>('/journey_map', {method: 'POST', body: input});

const buildHydratedConversationMessages = (messageRecords: XanoAgentMessage[]): Message[] =>
  [...messageRecords]
    .sort((left, right) => toEpoch(left.created_at) - toEpoch(right.created_at) || left.id - right.id)
    .map((message) => ({
      id: String(message.id),
      role: normalizeMessageRole(message.role),
      content: extractTextFromMessageContent(message.content),
      timestamp: new Date(toEpoch(message.created_at) || Date.now()),
    }));

const buildHydratedJourneyMapBundle = (
  journeyMap: XanoJourneyMap,
  stageRecords: XanoJourneyStage[],
  lensRecords: XanoJourneyLens[],
  cellRecords: XanoJourneyCell[],
  source: 'business' | 'crud',
  conversation: XanoAgentConversation | null = null,
  messageRecords: XanoAgentMessage[] = [],
): HydratedJourneyMapBundle => {
  const sortedStages = sortByDisplayOrder(stageRecords);
  const sortedLenses = sortByDisplayOrder(lensRecords);

  const stageKeyById = new Map(sortedStages.map((stage) => [stage.id, normalizeRecordKey(stage.key, stage.id, 'stage')]));
  const lensKeyById = new Map(sortedLenses.map((lens) => [lens.id, normalizeRecordKey(lens.key, lens.id, 'lens')]));

  return {
    journeyMap,
    conversation,
    messages: buildHydratedConversationMessages(messageRecords),
    source,
    hasHydratedMatrix: sortedStages.length > 0 && sortedLenses.length > 0,
    stages: sortedStages.map((stage) => ({
      id: stageKeyById.get(stage.id)!,
      key: stageKeyById.get(stage.id)!,
      xanoId: stage.id,
      displayOrder: stage.display_order ?? undefined,
      label: stage.label,
    })),
    lenses: sortedLenses.map((lens) => ({
      id: lensKeyById.get(lens.id)!,
      key: lensKeyById.get(lens.id)!,
      xanoId: lens.id,
      displayOrder: lens.display_order ?? undefined,
      label: lens.label,
      actorType: (lens.actor_type ?? undefined) as ActorType | undefined,
      templateKey: lens.template_key ?? undefined,
      rolePrompt: lens.role_prompt ?? undefined,
      personaDescription: lens.persona_description ?? undefined,
      primaryGoal: lens.primary_goal ?? undefined,
      standingConstraints: lens.standing_constraints ?? undefined,
    })),
    cells: cellRecords
      .filter((cell) => stageKeyById.has(cell.stage) && lensKeyById.has(cell.lens))
      .map((cell) => ({
        id: String(cell.id),
        xanoId: cell.id,
        journeyCellId: cell.id,
        journeyMapId: cell.journey_map,
        stageId: stageKeyById.get(cell.stage)!,
        stageKey: stageKeyById.get(cell.stage)!,
        stageXanoId: cell.stage,
        lensId: lensKeyById.get(cell.lens)!,
        lensKey: lensKeyById.get(cell.lens)!,
        lensXanoId: cell.lens,
        content: cell.content ?? '',
        status: normalizeCellStatus(cell.status),
        isLocked: Boolean(cell.is_locked),
        lastUpdated: cell.last_updated_at ? new Date(cell.last_updated_at) : undefined,
        actorFields: (cell.actor_fields ?? null) as ActorFields | null,
      })),
  };
};

const buildParameterizedPath = (templatePath: string, replacements: Record<string, number>) => {
  let resolvedPath = templatePath;
  let hasReplacement = false;

  Object.entries(replacements).forEach(([key, value]) => {
    const colonToken = `:${key}`;
    const braceToken = `{${key}}`;

    if (resolvedPath.includes(colonToken)) {
      resolvedPath = resolvedPath.replace(colonToken, String(value));
      hasReplacement = true;
    }

    if (resolvedPath.includes(braceToken)) {
      resolvedPath = resolvedPath.replace(braceToken, String(value));
      hasReplacement = true;
    }
  });

  if (hasReplacement) {
    return resolvedPath;
  }

  const fallbackValue = Object.values(replacements)[0];
  return `${templatePath}/${fallbackValue}`;
};

const buildJourneyMapPath = (templatePath: string, journeyMapId: number) => buildParameterizedPath(templatePath, {journeyMapId});

const coerceJourneyMap = (value: unknown): XanoJourneyMap | null => {
  if (!value || typeof value !== 'object') {
    return null;
  }

  const candidate = value as Partial<XanoJourneyMap>;
  if (typeof candidate.id !== 'number' || typeof candidate.title !== 'string') {
    return null;
  }

  return candidate as XanoJourneyMap;
};

const coerceConversation = (value: unknown): XanoAgentConversation | null => {
  if (!value || typeof value !== 'object') {
    return null;
  }

  const candidate = value as Partial<XanoAgentConversation>;
  if (typeof candidate.id !== 'number') {
    return null;
  }

  return {
    ...candidate,
    mode: normalizeConversationMode(candidate.mode),
  } as XanoAgentConversation;
};

const coercePersistedJourneyCellUpdate = (value: unknown): PersistedJourneyCellUpdate | null => {
  if (!value || typeof value !== 'object') {
    return null;
  }

  const candidate = value as Record<string, unknown>;
  const journeyCellId =
    typeof candidate.journey_cell_id === 'number'
      ? candidate.journey_cell_id
      : typeof candidate.id === 'number'
        ? candidate.id
        : null;

  if (journeyCellId === null) {
    return null;
  }

  return {
    journeyCellId,
    journeyMapId: typeof candidate.journey_map_id === 'number' ? candidate.journey_map_id : null,
    stageId: typeof candidate.stage_id === 'number' ? candidate.stage_id : null,
    stageKey: typeof candidate.stage_key === 'string' ? candidate.stage_key : null,
    stageLabel: typeof candidate.stage_label === 'string' ? candidate.stage_label : null,
    lensId: typeof candidate.lens_id === 'number' ? candidate.lens_id : null,
    lensKey: typeof candidate.lens_key === 'string' ? candidate.lens_key : null,
    lensLabel: typeof candidate.lens_label === 'string' ? candidate.lens_label : null,
    content: typeof candidate.content === 'string' ? candidate.content : '',
    status: normalizeCellStatus(typeof candidate.status === 'string' ? candidate.status : null),
    changeSource: typeof candidate.change_source === 'string' ? candidate.change_source : null,
    isLocked: Boolean(candidate.is_locked),
    updatedAt: typeof candidate.updated_at === 'string' ? candidate.updated_at : null,
    lastUpdatedAt: typeof candidate.last_updated_at === 'string' ? candidate.last_updated_at : null,
    skipped: Boolean(candidate.skipped),
    skipReason: typeof candidate.skip_reason === 'string' ? candidate.skip_reason : null,
  };
};

const buildPersistedJourneyCellUpdates = (value: unknown): PersistedJourneyCellUpdate[] =>
  Array.isArray(value)
    ? value
        .map((entry) => coercePersistedJourneyCellUpdate(entry))
        .filter((entry): entry is PersistedJourneyCellUpdate => entry !== null)
    : [];

const coerceBusinessBundle = (response: BusinessBundleResponse): HydratedJourneyMapBundle | null => {
  const journeyMap = coerceJourneyMap(response.journey_map ?? response.journeyMap ?? response.map ?? response);
  if (!journeyMap) {
    return null;
  }

  return buildHydratedJourneyMapBundle(
    journeyMap,
    Array.isArray(response.stages) ? response.stages : [],
    Array.isArray(response.lenses) ? response.lenses : [],
    Array.isArray(response.cells) ? response.cells : [],
    'business',
    coerceConversation(response.conversation),
    Array.isArray(response.messages)
      ? response.messages
      : Array.isArray(response.conversation_messages)
        ? response.conversation_messages
        : [],
  );
};

const buildPersistedConversationThread = (response: ConversationThreadResponse): PersistedConversationThread => ({
  conversation: coerceConversation(response.conversation),
  messages: buildHydratedConversationMessages(Array.isArray(response.messages) ? response.messages : []),
  proposedUpdates: buildPersistedJourneyCellUpdates(response.proposed_updates),
  appliedUpdates: buildPersistedJourneyCellUpdates(response.applied_updates),
  skippedUpdates: buildPersistedJourneyCellUpdates(response.skipped_updates),
  journeyMapUpdatedAt: response.journey_map_updated_at ?? null,
});

export const listJourneyMaps = () => xanoRequest<XanoJourneyMap[]>('/journey_map');

export async function createDraftJourneyMap(input: CreateDraftJourneyMapInput): Promise<HydratedJourneyMapBundle> {
  const createDraftPath = getXanoCreateDraftPath();

  if (createDraftPath) {
    try {
      const businessResponse = await xanoRequest<BusinessBundleResponse>(createDraftPath, {method: 'POST', body: input});
      const businessBundle = coerceBusinessBundle(businessResponse);
      if (businessBundle) {
        return businessBundle;
      }
    } catch {
      // Fall back to raw CRUD when the business endpoint is not configured or not ready yet.
    }
  }

  const journeyMap = await createJourneyMap(input);
  return buildHydratedJourneyMapBundle(journeyMap, [], [], [], 'crud');
}

export async function loadJourneyMapBundle(
  journeyMapId: number,
  existingJourneyMap?: XanoJourneyMap,
): Promise<HydratedJourneyMapBundle> {
  const loadMapPath = getXanoLoadMapPath();

  try {
    const businessResponse = await xanoRequest<BusinessBundleResponse>(buildJourneyMapPath(loadMapPath, journeyMapId));
    const businessBundle = coerceBusinessBundle(businessResponse);
    if (businessBundle) {
      return businessBundle;
    }
  } catch {
    // Fall back to raw CRUD when the business endpoint is not configured or not ready yet.
  }

  const journeyMap = existingJourneyMap ?? (await xanoRequest<XanoJourneyMap>(`/journey_map/${journeyMapId}`));
  const [stageRecords, lensRecords, cellRecords] = await Promise.all([
    listJourneyStages(),
    listJourneyLenses(),
    listJourneyCells(),
  ]);

  return buildHydratedJourneyMapBundle(
    journeyMap,
    stageRecords.filter((stage) => stage.journey_map === journeyMapId),
    lensRecords.filter((lens) => lens.journey_map === journeyMapId),
    cellRecords.filter((cell) => cell.journey_map === journeyMapId),
    'crud',
  );
}

export async function sendJourneyMapMessage(input: SendJourneyMapMessageInput): Promise<PersistedConversationThread> {
  const body: Record<string, unknown> = {
    content: input.content,
    assistant_reply: input.assistantReply,
    mode: input.mode,
  };

  if (typeof input.conversationId === 'number') {
    body.conversation_id = input.conversationId;
  }

  const selectedCellPayload = buildSelectedCellPayload(input.selectedCell);

  if (selectedCellPayload) {
    body.selected_cell_json = JSON.stringify(selectedCellPayload);
  }

  const response = await xanoRequest<ConversationThreadResponse>(buildJourneyMapPath(getXanoMessagePath(), input.journeyMapId), {
    method: 'POST',
    body,
  });

  return buildPersistedConversationThread(response);
}

export async function renameJourneyStage(input: RenameJourneyStageInput): Promise<void> {
  await xanoRequest<unknown>(buildParameterizedPath(getXanoRenameStagePath(), {journeyStageId: input.journeyStageId}), {
    method: 'PATCH',
    body: {label: input.label},
  });
}

export async function renameJourneyLens(input: RenameJourneyLensInput): Promise<void> {
  await xanoRequest<unknown>(buildParameterizedPath(getXanoRenameLensPath(), {journeyLensId: input.journeyLensId}), {
    method: 'PATCH',
    body: {label: input.label},
  });
}

export async function addJourneyStage(input: AddJourneyStageInput): Promise<void> {
  await xanoRequest<unknown>(buildParameterizedPath(getXanoAddStagePath(), {journeyMapId: input.journeyMapId}), {
    method: 'POST',
    body: input.label ? {label: input.label} : undefined,
  });
}

export async function removeJourneyStage(input: RemoveJourneyStageInput): Promise<void> {
  await xanoRequest<unknown>(buildParameterizedPath(getXanoRemoveStagePath(), {journeyStageId: input.journeyStageId}), {
    method: 'DELETE',
  });
}

export async function addJourneyLens(input: AddJourneyLensInput): Promise<void> {
  const body: Record<string, unknown> = {};
  if (input.label) body.label = input.label;
  if (input.actorType) body.actor_type = input.actorType;
  if (input.templateKey) body.template_key = input.templateKey;
  if (input.rolePrompt) body.role_prompt = input.rolePrompt;
  if (input.personaDescription) body.persona_description = input.personaDescription;
  if (input.primaryGoal) body.primary_goal = input.primaryGoal;
  if (input.standingConstraints) body.standing_constraints = input.standingConstraints;
  await xanoRequest<unknown>(buildParameterizedPath(getXanoAddLensPath(), {journeyMapId: input.journeyMapId}), {
    method: 'POST',
    body: Object.keys(body).length > 0 ? body : undefined,
  });
}

export async function updateLensActorFields(input: UpdateLensActorFieldsInput): Promise<XanoJourneyLens> {
  const body: Record<string, unknown> = {};
  if (input.label !== undefined) body.label = input.label;
  if (input.actorType !== undefined) body.actor_type = input.actorType;
  if (input.templateKey !== undefined) body.template_key = input.templateKey;
  if (input.rolePrompt !== undefined) body.role_prompt = input.rolePrompt;
  if (input.personaDescription !== undefined) body.persona_description = input.personaDescription;
  if (input.primaryGoal !== undefined) body.primary_goal = input.primaryGoal;
  if (input.standingConstraints !== undefined) body.standing_constraints = input.standingConstraints;
  return xanoRequest<XanoJourneyLens>(
    buildParameterizedPath(getXanoLensActorFieldsPath(), {journeyLensId: input.journeyLensId}),
    {method: 'PATCH', body},
  );
}

export async function removeJourneyLens(input: RemoveJourneyLensInput): Promise<void> {
  await xanoRequest<unknown>(buildParameterizedPath(getXanoRemoveLensPath(), {journeyLensId: input.journeyLensId}), {
    method: 'DELETE',
  });
}

export async function updateJourneyCell(input: UpdateJourneyCellInput): Promise<XanoJourneyCell> {
  const body: Record<string, unknown> = {
    content: input.content,
    status: input.status,
    is_locked: input.isLocked,
  };
  // Only include actor_fields when explicitly provided — avoids null-write on unrelated saves.
  if (input.actorFields !== undefined) {
    body.actor_fields = input.actorFields;
  }
  return xanoRequest<XanoJourneyCell>(buildParameterizedPath(getXanoUpdateCellPath(), {journeyCellId: input.journeyCellId}), {
    method: 'PATCH',
    body,
  });
}

export async function saveJourneySettings(journeyMapId: number, settings: JourneySettings): Promise<XanoJourneyMap> {
  return xanoRequest<XanoJourneyMap>(
    buildParameterizedPath(getXanoJourneySettingsPath(), {journeyMapId}),
    {method: 'PATCH', body: settings as Record<string, unknown>},
  );
}

export async function saveSmartAiSettings(journeyMapId: number, settings: Partial<SmartAiSettings>): Promise<XanoJourneyMap> {
  return xanoRequest<XanoJourneyMap>(
    buildParameterizedPath(getXanoSmartAiSettingsPath(), {journeyMapId}),
    {method: 'PATCH', body: settings as Record<string, unknown>},
  );
}

export async function sendAiMessage(input: SendAiMessageInput): Promise<PersistedAiConversationThread> {
  const body: Record<string, unknown> = {
    journey_map_id: input.journeyMapId,
    content: input.content,
    mode: input.mode,
  };

  if (typeof input.conversationId === 'number') {
    body.conversation_id = input.conversationId;
  }

  if (input.selectedCell) {
    body.selected_cell = input.selectedCell;
  }

  if (input.journeySettings) {
    // Only include non-null settings fields to keep the payload lean
    const settingsPayload: Record<string, string> = {};
    for (const [key, value] of Object.entries(input.journeySettings)) {
      if (typeof value === 'string' && value.trim().length > 0) {
        settingsPayload[key] = value;
      }
    }
    if (Object.keys(settingsPayload).length > 0) {
      body.journey_settings = settingsPayload;
    }
  }

  if (input.parentContext) {
    body.parent_context = input.parentContext;
  }

  const response = await xanoRequest<AiMessageResponse>(
    buildJourneyMapPath(getXanoAiMessagePath(), input.journeyMapId),
    {method: 'POST', body},
  );

  const rawTrace = Array.isArray(response.tool_trace) ? response.tool_trace : [];

  return {
    reply: response.reply ?? '',
    cellUpdates: Array.isArray(response.cell_updates) ? response.cell_updates : [],
    skippedUpdates: Array.isArray(response.skipped_updates) ? response.skipped_updates : [],
    suggestedPrompts: Array.isArray(response.suggested_prompts) ? response.suggested_prompts : [],
    structuralChanges: response.structural_changes ?? {stages_changed: false, lenses_changed: false},
    progress: {
      totalCells: response.progress?.total_cells ?? 0,
      filledCells: response.progress?.filled_cells ?? 0,
      percentage: response.progress?.percentage ?? 0,
    },
    conversation: coerceConversation(response.conversation),
    messages: buildHydratedConversationMessages(Array.isArray(response.messages) ? response.messages : []),
    toolTrace: rawTrace.map((entry, idx) => ({
      toolName: entry.tool_name ?? '',
      toolCategory: entry.tool_category ?? 'read',
      inputSummary: entry.input_summary ?? '',
      outputSummary: entry.output_summary ?? '',
      executionOrder: entry.execution_order ?? idx + 1,
    })),
    thinking: typeof response.thinking === 'string' && response.thinking.trim().length > 0
      ? response.thinking
      : null,
    turnId: response.turn_log?.turn_id ?? null,
    stepLimitWarning: (response.turn_log?.tool_count ?? 0) >= 18,
  };
}

export async function fetchToolLogs(journeyMapId: number, turnId: string): Promise<ToolLogsResponse> {
  const path = `/journey_map/${journeyMapId}/tool-logs?turn_id=${encodeURIComponent(turnId)}`;
  return xanoRequest<ToolLogsResponse>(path);
}

// ── Conversation CRUD ──

export async function listConversations(journeyMapId: number): Promise<ConversationListItem[]> {
  const items = await xanoRequest<ConversationListItem[]>(`/journey_map/${journeyMapId}/conversations`);
  return Array.isArray(items) ? items : [];
}

export async function getConversation(journeyMapId: number, conversationId: number): Promise<ConversationWithMessages> {
  type RawResponse = {conversation: XanoAgentConversation; messages: XanoAgentMessage[]};
  const response = await xanoRequest<RawResponse>(`/journey_map/${journeyMapId}/conversation/${conversationId}`);
  return {
    conversation: coerceConversation(response.conversation) ?? response.conversation,
    messages: buildHydratedConversationMessages(Array.isArray(response.messages) ? response.messages : []),
  };
}

type CreateConversationInput = {
  journeyMapId: number;
  title?: string;
  mode: ConversationMode;
};

export async function createConversation(input: CreateConversationInput): Promise<XanoAgentConversation> {
  const body: Record<string, unknown> = {mode: input.mode};
  if (input.title) {
    body.title = input.title;
  }
  const response = await xanoRequest<XanoAgentConversation>(`/journey_map/${input.journeyMapId}/conversation`, {
    method: 'POST',
    body,
  });
  return coerceConversation(response) ?? response;
}

type UpdateConversationInput = {
  journeyMapId: number;
  conversationId: number;
  title?: string;
  mode?: ConversationMode;
};

export async function updateConversation(input: UpdateConversationInput): Promise<XanoAgentConversation> {
  const body: Record<string, unknown> = {};
  if (input.title !== undefined) {
    body.title = input.title;
  }
  if (input.mode !== undefined) {
    body.mode = input.mode;
  }
  const response = await xanoRequest<XanoAgentConversation>(
    `/journey_map/${input.journeyMapId}/conversation/${input.conversationId}`,
    {method: 'PATCH', body},
  );
  return coerceConversation(response) ?? response;
}

export async function deleteConversation(journeyMapId: number, conversationId: number): Promise<void> {
  await xanoRequest<unknown>(`/journey_map/${journeyMapId}/conversation/${conversationId}`, {method: 'DELETE'});
}

export async function deleteMessage(journeyMapId: number, conversationId: number, messageId: number): Promise<void> {
  await xanoRequest<unknown>(
    `/journey_map/${journeyMapId}/conversation/${conversationId}/message/${messageId}`,
    {method: 'DELETE'},
  );
}

// ── Auth types ───────────────────────────────────────────────────────────────

export interface XanoUser {
  id: number;
  created_at?: number | string | null;
  name: string;
  email: string;
  account_id?: number | null;
  role?: string | null;
}

interface AuthApiResponse {
  authToken: string;
  user_id: number;
}

// ── Auth API functions ───────────────────────────────────────────────────────

export async function loginUser(email: string, password: string): Promise<{authToken: string; userId: number}> {
  const res = await authXanoRequest<AuthApiResponse>('/auth/login', {method: 'POST', body: {email, password}});
  return {authToken: res.authToken, userId: res.user_id};
}

export async function signupUser(name: string, email: string, password: string): Promise<{authToken: string; userId: number}> {
  const res = await authXanoRequest<AuthApiResponse>('/auth/signup', {method: 'POST', body: {name, email, password}});
  return {authToken: res.authToken, userId: res.user_id};
}

export async function getAuthMe(): Promise<XanoUser> {
  return authXanoRequest<XanoUser>('/auth/me');
}

// ── Dashboard journey map management ────────────────────────────────────────

export async function deleteJourneyMap(journeyMapId: number): Promise<void> {
  await xanoRequest<unknown>(`/journey_map/${journeyMapId}`, {method: 'DELETE'});
}

export async function updateJourneyMapMeta(
  journeyMapId: number,
  data: {title?: string; status?: JourneyMapStatus},
): Promise<XanoJourneyMap> {
  return xanoRequest<XanoJourneyMap>(`/journey_map/${journeyMapId}`, {method: 'PATCH', body: data});
}

// ── Journey Architecture ─────────────────────────────────────────────────────

export type JourneyArchitectureStatus = 'draft' | 'active' | 'archived';

export interface XanoJourneyArchitecture {
  id: number;
  created_at: number | string | null;
  updated_at: string | null;
  title: string | null;
  description: string | null;
  status: JourneyArchitectureStatus;
  owner_user: number | null;
  account_id: number | null;
}

// ── Journey Link ─────────────────────────────────────────────────────────────

export type JourneyLinkType = 'exception' | 'anti_journey' | 'sub_journey';

export interface XanoJourneyLink {
  id: number;
  created_at: number | string | null;
  updated_at: string | null;
  journey_architecture: number;
  source_map: number;
  source_cell: number;
  target_map: number;
  link_type: JourneyLinkType;
  label: string | null;
  owner_user: number | null;
}

export interface JourneyArchitectureBundle {
  journey_architecture: XanoJourneyArchitecture;
  journey_maps: XanoJourneyMap[];
  journey_links: XanoJourneyLink[];
}

export const listJourneyArchitectures = (): Promise<XanoJourneyArchitecture[]> =>
  xanoRequest<XanoJourneyArchitecture[]>('/journey_architecture');

export const createJourneyArchitecture = (data?: {
  title?: string;
  description?: string;
  status?: JourneyArchitectureStatus;
}): Promise<XanoJourneyArchitecture> =>
  xanoRequest<XanoJourneyArchitecture>('/journey_architecture', {method: 'POST', body: data ?? {}});

export const updateJourneyArchitecture = (
  id: number,
  data: {title?: string; description?: string; status?: JourneyArchitectureStatus},
): Promise<XanoJourneyArchitecture> =>
  xanoRequest<XanoJourneyArchitecture>(`/journey_architecture/${id}`, {method: 'PATCH', body: data});

export const deleteJourneyArchitecture = (id: number): Promise<void> =>
  xanoRequest<void>(`/journey_architecture/${id}`, {method: 'DELETE'});

export const loadJourneyArchitectureBundle = (id: number): Promise<JourneyArchitectureBundle> =>
  xanoRequest<JourneyArchitectureBundle>(`/journey_architecture/bundle/${id}`);

export const listScenarios = (archId: number): Promise<XanoScenario[]> =>
  xanoRequest<XanoScenario[]>(`/journey_architecture/${archId}/scenarios`);

export const cloneScenario = (
  archId: number,
  sourceMapId: number,
  title?: string,
): Promise<XanoScenario> =>
  xanoRequest<XanoScenario>(`/journey_architecture/${archId}/scenarios/clone`, {
    method: 'POST',
    body: {source_map_id: sourceMapId, ...(title ? {title} : {})},
  });

export const createJourneyLink = (
  architectureId: number,
  data: {
    source_map_id: number;
    source_cell_id: number;
    target_map_id: number;
    link_type: JourneyLinkType;
    label?: string;
  },
): Promise<XanoJourneyLink> =>
  xanoRequest<XanoJourneyLink>(`/journey_architecture/${architectureId}/link`, {method: 'POST', body: data});

export const updateJourneyLink = (
  id: number,
  data: {link_type?: JourneyLinkType; label?: string},
): Promise<XanoJourneyLink> =>
  xanoRequest<XanoJourneyLink>(`/journey_link/${id}`, {method: 'PATCH', body: data});

export const deleteJourneyLink = (id: number): Promise<{deleted: boolean; id: number}> =>
  xanoRequest<{deleted: boolean; id: number}>(`/journey_link/${id}`, {method: 'DELETE'});

export const listJourneyLinksForMap = (mapId: number): Promise<XanoJourneyLink[]> =>
  xanoRequest<XanoJourneyLink[]>(`/journey_link?source_map=${mapId}`);

export const listJourneyStagesForMap = async (mapId: number): Promise<XanoJourneyStage[]> => {
  const all = await xanoRequest<XanoJourneyStage[]>('/journey_stage');
  return all.filter((s) => s.journey_map === mapId).sort((a, b) => (a.display_order ?? 0) - (b.display_order ?? 0));
};

export const listJourneyCellsForMap = async (mapId: number): Promise<XanoJourneyCell[]> => {
  const all = await xanoRequest<XanoJourneyCell[]>('/journey_cell');
  return all.filter((c) => c.journey_map === mapId);
};

export const getJourneyCell = (journeyCellId: number): Promise<XanoJourneyCell> =>
  xanoRequest<XanoJourneyCell>(`/journey_cell/${journeyCellId}`);

export const listInboundLinksForMap = (targetMapId: number): Promise<XanoJourneyLink[]> =>
  xanoRequest<XanoJourneyLink[]>(`/journey_link?target_map=${targetMapId}`);

// ── Scorecard ────────────────────────────────────────────────────────────────

export type HealthLabel = 'healthy' | 'at_risk' | 'critical';

export interface ScorecardStage {
  stage_id: number;
  stage_key: string;
  stage_label: string;
  health: number | null;
  health_label: HealthLabel | null;
  cell_populated: boolean;
}

export interface ScorecardResult {
  metrics_rollup: {
    map_health: number | null;
    map_hl: HealthLabel | null;
    stages: ScorecardStage[];
    populated_count: number;
    total_count: number;
  };
  financial_rollup: {
    total_cost_to_serve: number;
    total_revenue_at_risk: number;
    total_automation_savings: number;
    total_upsell_opportunity: number;
  };
}

export const fetchScorecard = (journeyMapId: number): Promise<ScorecardResult> =>
  xanoRequest<ScorecardResult>(`/journey_map/${journeyMapId}/scorecard`);

// ── Compare ───────────────────────────────────────────────────────────────────

export interface CompareMapMeta {
  id: number;
  title: string;
  updated_at: string | null;
}

export interface CompareMetaResult {
  map_a: CompareMapMeta;
  map_b: CompareMapMeta;
}

export const fetchCompareMeta = (
  archId: number,
  mapA: number,
  mapB: number,
): Promise<CompareMetaResult> =>
  xanoRequest<CompareMetaResult>(
    `/journey_architecture/${archId}/compare?map_a=${mapA}&map_b=${mapB}`,
  );