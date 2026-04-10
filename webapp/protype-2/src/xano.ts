import type {CellStatus, Lens, MatrixCell, Message, Stage} from './types';
import type {SelectedCellContext} from './cellIdentifiers';

export type JourneyMapStatus = 'draft' | 'active' | 'archived';
export type ConversationMode = 'interview' | 'chat';

export interface XanoJourneyMap {
  id: number;
  created_at: number | string;
  updated_at?: string;
  title: string;
  status: JourneyMapStatus;
  owner_user?: number | null;
  account_id?: number | null;
  last_interaction_at?: string | null;
  settings?: Record<string, unknown> | null;
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
  title: string;
  status: JourneyMapStatus;
  settings?: Record<string, unknown>;
  owner_user?: number;
  account_id?: number;
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
};

type RemoveJourneyLensInput = {
  journeyLensId: number;
};

type UpdateJourneyCellInput = {
  journeyCellId: number;
  content?: string;
  status?: CellStatus;
  isLocked?: boolean;
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
  const response = await fetch(`${getXanoBaseUrl()}${path}`, {
    method,
    headers: body ? {'Content-Type': 'application/json', Accept: 'application/json'} : {Accept: 'application/json'},
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

  if (input.selectedCell) {
    body.selected_cell_json = JSON.stringify({
      reference: input.selectedCell.reference,
      shorthand: input.selectedCell.shorthand,
      journey_map_id: input.selectedCell.journeyMapId,
      journey_cell_id: input.selectedCell.journeyCellId,
      stage_id: input.selectedCell.stageId,
      stage_key: input.selectedCell.stageKey,
      stage_label: input.selectedCell.stageLabel,
      lens_id: input.selectedCell.lensId,
      lens_key: input.selectedCell.lensKey,
      lens_label: input.selectedCell.lensLabel,
    });
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
  await xanoRequest<unknown>(buildParameterizedPath(getXanoAddLensPath(), {journeyMapId: input.journeyMapId}), {
    method: 'POST',
    body: input.label ? {label: input.label} : undefined,
  });
}

export async function removeJourneyLens(input: RemoveJourneyLensInput): Promise<void> {
  await xanoRequest<unknown>(buildParameterizedPath(getXanoRemoveLensPath(), {journeyLensId: input.journeyLensId}), {
    method: 'DELETE',
  });
}

export async function updateJourneyCell(input: UpdateJourneyCellInput): Promise<XanoJourneyCell> {
  return xanoRequest<XanoJourneyCell>(buildParameterizedPath(getXanoUpdateCellPath(), {journeyCellId: input.journeyCellId}), {
    method: 'PATCH',
    body: {
      content: input.content,
      status: input.status,
      is_locked: input.isLocked,
    },
  });
}