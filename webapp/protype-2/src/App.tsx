import React, { useState, useRef, useEffect, useCallback, useMemo } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  Send,
  Play,
  RotateCcw,
  CheckCircle2,
  CircleDashed,
  HelpCircle,
  Info,
  ChevronDown,
  ChevronRight,
  Check,
  MessageSquare,
  LayoutGrid,
  Search,
  Plus,
  X,
  GripHorizontal,
  Edit2,
  Trash2,
  Lock,
  Unlock,
  Bot,
  MessageCircle,
  Share2,
  Paperclip,
  Sparkles,
  AtSign,
  Box,
  Bookmark,
  MousePointer2,
  Folder,
  Settings,
  ArrowLeft,
  LogOut,
  BarChart2,
} from 'lucide-react';
import { useAuth } from './AuthContext';
import { motion, AnimatePresence } from 'motion/react';
import { Message, MessageActivity, MatrixCell, CellStatus, Stage, Lens, ToolTraceEntry, isMetricsActorFields, parseMetricValue, calcStageHealth } from './types';
import type {MetricsActorFields} from './types';
import {cloneCellSnapshot, hasPendingCellChanges, resolveCellPersistenceBaseline} from './cellPersistence';
import { STAGES as INITIAL_STAGES, LENSES as INITIAL_LENSES, ACTOR_TEMPLATES, METRICS_THRESHOLDS, getMetricColor, METRICS_ACTOR_ENABLED } from './constants';
import JourneyMatrixTabulator from './JourneyMatrixTabulator';
import { JourneyHealthWidget } from './JourneyHealthWidget';
import {ActorSetupWizard} from './ActorSetupWizard';
import type {ActorWizardInput} from './ActorSetupWizard';
import {buildCellReferenceLabel, buildCellShorthand, buildSelectedCellContext} from './cellIdentifiers';
import type {CellUpdateSummary} from './cellIdentifiers';
import {
  addJourneyLens,
  updateLensActorFields,
  addJourneyStage,
  buildSelectedCellPayload,
  createConversation,
  createDraftJourneyMap,
  deleteConversation,
  deleteMessage,
  getConversation,
  listConversations,
  listJourneyMaps,
  createJourneyLink,
  loadJourneyArchitectureBundle,
  listJourneyLinksForMap,
  listInboundLinksForMap,
  getJourneyCell,
  loadJourneyMapBundle,
  removeJourneyLens,
  removeJourneyStage,
  renameJourneyLens,
  renameJourneyStage,
  sendAiMessage,
  fetchToolLogs,
  updateConversation,
  updateJourneyCell,
  saveJourneySettings,
  saveSmartAiSettings,
  type ConversationListItem,
  type XanoAgentConversation,
  type XanoJourneyMap,
  type HydratedJourneyMapBundle,
  type JourneySettings,
  type SmartAiSettings,
  type InterviewDepth,
  type InsightStandard,
  type LensPriority,
  SMART_AI_DEFAULTS,
  type JourneyLinkType,
  type ParentJourneyContext,
  fetchScorecard,
  type ScorecardResult,
} from './xano';
import type {CellLinkInfo} from './journeyMatrixTabulatorHelpers';

type InitialLoadState = 'loading' | 'ready' | 'empty' | 'error';

const buildScaffoldCells = (stages: Stage[], lenses: Lens[]): MatrixCell[] =>
  stages.flatMap((stage) =>
    lenses.map((lens) => ({
      id: `${stage.id}-${lens.id}`,
      stageId: stage.id,
      stageKey: stage.key ?? stage.id,
      lensId: lens.id,
      lensKey: lens.key ?? lens.id,
      content: '',
      status: 'open' as CellStatus,
      isLocked: false,
    })),
  );

const SCAFFOLD_CELLS = buildScaffoldCells(INITIAL_STAGES, INITIAL_LENSES);

const DEFAULT_MATRIX_EDIT_ERROR = 'Create or load a persisted journey map before editing the matrix.';

const normalizePersistedCellStatus = (value: CellStatus | null | undefined, fallback: CellStatus): CellStatus => {
  if (value === 'confirmed' || value === 'draft' || value === 'open') {
    return value;
  }
  return fallback;
};

const resolveXanoId = (entity: {id: string; xanoId?: number}, entityName: string) => {
  if (typeof entity.xanoId === 'number' && Number.isFinite(entity.xanoId)) {
    return entity.xanoId;
  }

  const parsedId = Number(entity.id);
  if (Number.isInteger(parsedId) && parsedId > 0) {
    return parsedId;
  }

  throw new Error(`Cannot persist ${entityName} edits because this record is not backed by a saved Xano row yet.`);
};

const getErrorMessage = (error: unknown, fallback: string) => (error instanceof Error ? error.message : fallback);

// ── Transparency Layer helpers ──────────────────────────────────────────────

const TOOL_CATEGORY_ICON: Record<string, string> = {
  read: '🔍',
  write: '✏️',
  status: '🔒',
  structure: '🏗️',
};

interface ActivityPanelProps {
  msgId: string;
  activity: MessageActivity;
  isTraceExpanded: boolean;
  isReasoningExpanded: boolean;
  onToggleTrace: () => void;
  onToggleReasoning: () => void;
  showReasoning?: boolean;
}

function ActivityPanel({
  activity,
  isTraceExpanded,
  isReasoningExpanded,
  onToggleTrace,
  onToggleReasoning,
  showReasoning = true,
}: ActivityPanelProps) {
  const toolTrace: ToolTraceEntry[] = activity.toolTrace ?? [];
  const hasTrace = toolTrace.length > 0;
  const hasThinking = Boolean(activity.thinking);
  const readCount = toolTrace.filter((t) => t.toolCategory === 'read').length;

  const showChip =
    activity.cellsUpdated > 0 ||
    activity.structureChanged ||
    hasTrace;

  if (!showChip) return null;

  return (
    <div className="ml-8 mt-0.5 space-y-1.5">
      {/* Layer 1: compact activity chip */}
      <button
        type="button"
        onClick={hasTrace ? onToggleTrace : undefined}
        className={`flex items-center gap-1.5 text-[10px] text-zinc-400 font-medium transition-colors ${
          hasTrace ? 'cursor-pointer hover:text-zinc-600' : 'cursor-default'
        }`}
      >
        {readCount > 0 && <span>📖 {readCount} read</span>}
        {readCount > 0 && activity.cellsUpdated > 0 && <span className="text-zinc-300">·</span>}
        {activity.cellsUpdated > 0 && (
          <span>✏️ {activity.cellsUpdated} updated</span>
        )}
        {activity.structureChanged && (
          <>
            {(readCount > 0 || activity.cellsUpdated > 0) && <span className="text-zinc-300">·</span>}
            <span>🏗️ Structure changed</span>
          </>
        )}
        {(activity.cellsUpdated > 0 || activity.structureChanged || readCount > 0) && (
          <>
            <span className="text-zinc-300">·</span>
            <span>{activity.progress.percentage}% complete</span>
          </>
        )}
        {hasTrace && (
          <span className="text-zinc-300 ml-0.5">
            {isTraceExpanded
              ? <ChevronDown className="w-2.5 h-2.5 inline" />
              : <ChevronRight className="w-2.5 h-2.5 inline" />}
          </span>
        )}
      </button>

      {/* Layer 2: tool trace panel */}
      {isTraceExpanded && hasTrace && (
        <div className="border border-zinc-100 rounded-lg bg-zinc-50/70 overflow-hidden divide-y divide-zinc-100">
          {toolTrace.map((entry, idx) => (
            <div key={idx} className="flex items-start gap-2 px-2.5 py-1.5 text-[10px]">
              <span className="shrink-0 mt-px">
                {TOOL_CATEGORY_ICON[entry.toolCategory] ?? '🔧'}
              </span>
              <div className="min-w-0 flex-1">
                <span className="font-medium text-zinc-700">{entry.toolName}</span>
                {entry.inputSummary && (
                  <>
                    <span className="text-zinc-300 mx-1">·</span>
                    <span className="text-zinc-500">{entry.inputSummary}</span>
                  </>
                )}
                {entry.outputSummary && entry.outputSummary !== entry.inputSummary && (
                  <>
                    <span className="text-zinc-300 mx-1">→</span>
                    <span className="text-zinc-400">{entry.outputSummary}</span>
                  </>
                )}
              </div>
            </div>
          ))}

          {/* Layer 3 toggle — only when thinking is present */}
          {hasThinking && (
            <button
              type="button"
              onClick={onToggleReasoning}
              className="w-full flex items-center gap-1.5 px-2.5 py-1.5 text-[10px] text-zinc-400 hover:text-zinc-600 hover:bg-zinc-100 transition-colors"
            >
              <span>💭</span>
              <span>{isReasoningExpanded ? 'Hide AI reasoning' : 'Show AI reasoning'}</span>
              {isReasoningExpanded
                ? <ChevronDown className="w-2.5 h-2.5 ml-auto" />
                : <ChevronRight className="w-2.5 h-2.5 ml-auto" />}
            </button>
          )}
        </div>
      )}

      {/* Layer 3: reasoning panel — hidden when show_reasoning is off */}
      {showReasoning && isReasoningExpanded && hasThinking && (
        <div className="p-2.5 rounded-lg bg-zinc-50 border border-zinc-100 text-[10px] text-zinc-400 italic leading-relaxed">
          {activity.thinking}
        </div>
      )}
    </div>
  );
}

// ── Debug Panel (Layer 4) — only rendered when ?debug=1 in URL ──────────────

const TOOL_CATEGORY_COLOR: Record<string, string> = {
  read    : 'text-blue-500',
  write   : 'text-emerald-600',
  status  : 'text-violet-500',
  structure: 'text-amber-500',
};

interface DebugPanelProps {
  journeyMapId: number;
  turnId: string;
  stepLimitWarning: boolean;
}

function DebugPanel({ journeyMapId, turnId, stepLimitWarning }: DebugPanelProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [toolCalls, setToolCalls] = useState<import('./xano').ToolLogEntry[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleExpand = useCallback(async () => {
    const next = !isExpanded;
    setIsExpanded(next);
    if (next && toolCalls === null && !loading) {
      setLoading(true);
      setError(null);
      try {
        const result = await fetchToolLogs(journeyMapId, turnId);
        setToolCalls(result.tool_calls ?? []);
      } catch {
        setError('Failed to load tool logs');
      } finally {
        setLoading(false);
      }
    }
  }, [isExpanded, toolCalls, loading, journeyMapId, turnId]);

  return (
    <div className="ml-8 mt-0.5">
      <button
        type="button"
        onClick={handleExpand}
        className="flex items-center gap-1.5 text-[10px] text-amber-500 font-medium hover:text-amber-700 transition-colors"
      >
        <span>🔧 Debug</span>
        {toolCalls !== null && <span className="text-zinc-400">— {toolCalls.length} tool calls</span>}
        {isExpanded
          ? <ChevronDown className="w-2.5 h-2.5" />
          : <ChevronRight className="w-2.5 h-2.5" />}
      </button>

      {isExpanded && (
        <div className="mt-1 border border-amber-100 rounded-lg bg-amber-50/50 overflow-hidden">
          {stepLimitWarning && (
            <div className="px-2.5 py-1.5 bg-amber-100 text-[10px] text-amber-700 font-medium">
              ⚠ Step limit warning — agent may have been cut off before completing all operations
            </div>
          )}
          {loading && (
            <div className="px-2.5 py-2 text-[10px] text-zinc-400">Loading tool logs…</div>
          )}
          {error && (
            <div className="px-2.5 py-2 text-[10px] text-red-500">{error}</div>
          )}
          {!loading && !error && toolCalls !== null && toolCalls.length === 0 && (
            <div className="px-2.5 py-2 text-[10px] text-zinc-400">No tool log records found for this turn.</div>
          )}
          {!loading && toolCalls !== null && toolCalls.length > 0 && (
            <div className="divide-y divide-amber-100">
              {toolCalls.map((call, idx) => {
                const isSkipped = call.output_summary?.toLowerCase().includes('skipped') || call.output_summary?.toLowerCase().includes('not_found');
                return (
                  <div
                    key={call.id ?? idx}
                    className={`flex items-start gap-2 px-2.5 py-1.5 text-[10px] ${isSkipped ? 'bg-amber-100/60' : ''}`}
                  >
                    <span className="text-zinc-400 shrink-0 w-4 text-right">{call.execution_order}</span>
                    <span className={`shrink-0 font-medium ${TOOL_CATEGORY_COLOR[call.tool_category] ?? 'text-zinc-500'}`}>
                      {call.tool_name}
                    </span>
                    {call.input_summary && (
                      <span className="text-zinc-500 truncate">{call.input_summary}</span>
                    )}
                    {call.output_summary && (
                      <>
                        <span className="text-zinc-300 shrink-0">→</span>
                        <span className={`truncate ${isSkipped ? 'text-amber-600 font-medium' : 'text-zinc-400'}`}>
                          {call.output_summary}
                        </span>
                      </>
                    )}
                  </div>
                );
              })}
            </div>
          )}
          <div className="px-2.5 py-1 border-t border-amber-100 text-[9px] text-zinc-400 font-mono">
            turn_id: {turnId}
          </div>
        </div>
      )}
    </div>
  );
}

// ───────────────────────────────────────────────────────────────────────────

export default function App({ journeyMapId }: { journeyMapId?: number }) {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const architectureId = searchParams.get('arch') ? Number(searchParams.get('arch')) : null;
  const fromScenarios = searchParams.get('tab') === 'scenarios';
  const isDebugMode = searchParams.get('debug') === '1';
  const { user, logout } = useAuth();
  const [messages, setMessages] = useState<Message[]>([]);
  const [inputText, setInputText] = useState('');
  const [cells, setCells] = useState<MatrixCell[]>([]);
  const [stages, setStages] = useState<Stage[]>([]);
  const [lenses, setLenses] = useState<Lens[]>([]);
  const [journeyMapRecord, setJourneyMapRecord] = useState<XanoJourneyMap | null>(null);
  const [cellLinkMap, setCellLinkMap] = useState<Map<number, CellLinkInfo>>(new Map());
  // Cell-level link creation state
  const [siblingMaps, setSiblingMaps] = useState<XanoJourneyMap[]>([]);
  const [siblingMapsLoaded, setSiblingMapsLoaded] = useState(false);
  const [cellLinkType, setCellLinkType] = useState<JourneyLinkType>('exception');
  const [cellLinkTargetId, setCellLinkTargetId] = useState<number | 'new' | ''>('');
  const [cellLinkNewTitle, setCellLinkNewTitle] = useState('');
  const [cellLinkCreating, setCellLinkCreating] = useState(false);
  const [cellLinkError, setCellLinkError] = useState<string | null>(null);
  const [cellLinkSuccess, setCellLinkSuccess] = useState(false);
  const [conversationRecord, setConversationRecord] = useState<XanoAgentConversation | null>(null);
  const [initialLoadState, setInitialLoadState] = useState<InitialLoadState>('loading');
  const [isXanoSyncing, setIsXanoSyncing] = useState(true);
  const [isSendingMessage, setIsSendingMessage] = useState(false);
  const [lastUpdateSummaries, setLastUpdateSummaries] = useState<CellUpdateSummary[]>([]);
  const [xanoError, setXanoError] = useState<string | null>(null);
  const [matrixSyncSource, setMatrixSyncSource] = useState<'local' | 'map-only' | 'crud' | 'business'>('local');
  const [selectedCellId, setSelectedCellId] = useState<string | null>(null);
  const [selectedCellSnapshot, setSelectedCellSnapshot] = useState<MatrixCell | null>(null);
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [isChatMode, setIsChatMode] = useState(false); // false = Interview Mode, true = Chat Mode
  const [isSmartAiSettingsOpen, setIsSmartAiSettingsOpen] = useState(false);
  const [smartAiSettings, setSmartAiSettings] = useState<SmartAiSettings>({...SMART_AI_DEFAULTS});
  const [isSmartAiSettingsSaving, setIsSmartAiSettingsSaving] = useState(false);
  const [smartAiSettingsError, setSmartAiSettingsError] = useState<string | null>(null);
  const [suggestedPrompts, setSuggestedPrompts] = useState<string[]>([]);
  const [isQuestionMode, setIsQuestionMode] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [conversationList, setConversationList] = useState<ConversationListItem[]>([]);
  const [isSessionPickerOpen, setIsSessionPickerOpen] = useState(false);
  const [isLoadingSessions, setIsLoadingSessions] = useState(false);
  const [isRenamingSession, setIsRenamingSession] = useState<number | null>(null);
  const [renameText, setRenameText] = useState('');
  const [confirmDeleteId, setConfirmDeleteId] = useState<number | null>(null);
  // transparency layer: tracks which panel (trace | reasoning | null) is open per message id
  const [expandedPanels, setExpandedPanels] = useState<Record<string, 'trace' | 'reasoning' | null>>({});
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [journeySettings, setJourneySettings] = useState<JourneySettings>({});
  const [settingsDraft, setSettingsDraft] = useState<JourneySettings>({});
  const [isSavingSettings, setIsSavingSettings] = useState(false);
  const [settingsSaved, setSettingsSaved] = useState(false);
  const [showActorWizard, setShowActorWizard] = useState(false);
  const [actorWizardEditTarget, setActorWizardEditTarget] = useState<Lens | null>(null);
  const [inboundContext, setInboundContext] = useState<ParentJourneyContext | null>(null);
  // ── Scorecard / Health Widget (US-MET-12/14) ──
  const [scorecard, setScorecard] = useState<ScorecardResult | null>(null);
  const [scorecardBaseline, setScorecardBaseline] = useState<ScorecardResult | null>(null);
  const [widgetVisible, setWidgetVisible] = useState(true);
  const scorecardDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const chatEndRef = useRef<HTMLDivElement>(null);
  const mainRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    if (isChatOpen) {
      scrollToBottom();
    }
  }, [messages, isChatOpen]);

  const applyJourneyMapBundle = useCallback((bundle: HydratedJourneyMapBundle | null) => {
    setSelectedCellId(null);
    setSelectedCellSnapshot(null);

    if (!bundle) {
      setJourneyMapRecord(null);
      setConversationRecord(null);
      setMessages([]);
      setIsChatMode(false);
      setStages([]);
      setLenses([]);
      setCells([]);
      setMatrixSyncSource('local');
      setJourneySettings({});
      setSettingsDraft({});
      setSmartAiSettings({...SMART_AI_DEFAULTS});
      return;
    }

    setJourneyMapRecord(bundle.journeyMap);
    setConversationRecord(bundle.conversation);
    setMessages(bundle.messages);
    setIsChatMode(bundle.conversation?.mode === 'chat');

    // Populate journey settings from the loaded map record
    const loadedSettings: JourneySettings = {
      primary_actor:       bundle.journeyMap.primary_actor ?? null,
      journey_scope:       bundle.journeyMap.journey_scope ?? null,
      start_point:         bundle.journeyMap.start_point ?? null,
      end_point:           bundle.journeyMap.end_point ?? null,
      duration:            bundle.journeyMap.duration ?? null,
      success_metrics:     bundle.journeyMap.success_metrics ?? null,
      key_stakeholders:    bundle.journeyMap.key_stakeholders ?? null,
      dependencies:        bundle.journeyMap.dependencies ?? null,
      pain_points_summary: bundle.journeyMap.pain_points_summary ?? null,
      opportunities:       bundle.journeyMap.opportunities ?? null,
      version:             bundle.journeyMap.version ?? null,
    };
    setJourneySettings(loadedSettings);
    setSettingsDraft(loadedSettings);

    // Load smart AI settings — merge persisted values over defaults so null fields fall back cleanly
    setSmartAiSettings({...SMART_AI_DEFAULTS, ...(bundle.journeyMap.smart_ai_settings ?? {})});

    if (bundle.hasHydratedMatrix) {
      setStages(bundle.stages);
      setLenses(bundle.lenses);
      setCells(bundle.cells);
      setMatrixSyncSource(bundle.source);
      return;
    }

    setStages(INITIAL_STAGES);
    setLenses(INITIAL_LENSES);
    setCells(SCAFFOLD_CELLS);
    setMatrixSyncSource('map-only');
  }, []);

  const refreshCurrentJourneyMap = useCallback(
    async (currentJourneyMap?: XanoJourneyMap | null) => {
      const nextJourneyMap = currentJourneyMap ?? journeyMapRecord;
      if (!nextJourneyMap) {
        throw new Error(DEFAULT_MATRIX_EDIT_ERROR);
      }

      const hydratedBundle = await loadJourneyMapBundle(nextJourneyMap.id, nextJourneyMap);
      applyJourneyMapBundle(hydratedBundle);
      setInitialLoadState('ready');
    },
    [applyJourneyMapBundle, journeyMapRecord],
  );

  // ── Scorecard refresh (US-MET-14) ──────────────────────────────────────────
  const refreshScorecard = useCallback(async (mapId: number, isInitial = false) => {
    if (!METRICS_ACTOR_ENABLED) return;
    try {
      const result = await fetchScorecard(mapId);
      setScorecard(result);
      if (isInitial) setScorecardBaseline(result);
    } catch { /* scorecard is non-critical — swallow errors */ }
  }, []);

  const debouncedRefreshScorecard = useCallback((mapId: number) => {
    if (scorecardDebounceRef.current) clearTimeout(scorecardDebounceRef.current);
    scorecardDebounceRef.current = setTimeout(() => { void refreshScorecard(mapId); }, 2000);
  }, [refreshScorecard]);

  const syncLatestJourneyMap = useCallback(async () => {
    setIsXanoSyncing(true);
    setXanoError(null);

    try {
      const maps = await listJourneyMaps();
      const latestMap = [...maps].sort((left, right) => {
        const leftCreatedAt = Number(left.created_at ?? 0);
        const rightCreatedAt = Number(right.created_at ?? 0);
        if (rightCreatedAt !== leftCreatedAt) {
          return rightCreatedAt - leftCreatedAt;
        }
        return right.id - left.id;
      })[0] ?? null;

      if (!latestMap) {
        applyJourneyMapBundle(null);
        setInitialLoadState('empty');
        return;
      }

      const hydratedBundle = await loadJourneyMapBundle(latestMap.id, latestMap);
      applyJourneyMapBundle(hydratedBundle);
      setInitialLoadState('ready');
    } catch (error) {
      applyJourneyMapBundle(null);
      setXanoError(error instanceof Error ? error.message : 'Unable to reach Xano.');
      setInitialLoadState((currentState) => (currentState === 'ready' ? 'ready' : 'error'));
    } finally {
      setIsXanoSyncing(false);
    }
  }, [applyJourneyMapBundle]);

  // When a specific journeyMapId is provided (from URL), load that map directly.
  // Otherwise fall back to loading the most recently updated map.
  useEffect(() => {
    if (typeof journeyMapId === 'number') {
      setIsXanoSyncing(true);
      setXanoError(null);
      loadJourneyMapBundle(journeyMapId)
        .then((bundle) => {
          applyJourneyMapBundle(bundle);
          setInitialLoadState('ready');
          void refreshScorecard(journeyMapId, true);
        })
        .catch((err) => {
          applyJourneyMapBundle(null);
          setXanoError(err instanceof Error ? err.message : 'Unable to load journey map.');
          setInitialLoadState('error');
        })
        .finally(() => setIsXanoSyncing(false));
    } else {
      void syncLatestJourneyMap();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [journeyMapId]);

  // Load sibling maps from the architecture bundle (lazy — only when architectureId is set).
  useEffect(() => {
    if (!architectureId || siblingMapsLoaded) return;
    loadJourneyArchitectureBundle(architectureId)
      .then((bundle) => {
        setSiblingMaps(bundle.journey_maps.filter((m) => m.id !== journeyMapRecord?.id));
        setSiblingMapsLoaded(true);
      })
      .catch(() => setSiblingMapsLoaded(true));
  }, [architectureId, siblingMapsLoaded, journeyMapRecord?.id]);

  // Load inbound parent context — runs once when the map and architecture are both known.
  useEffect(() => {
    if (!architectureId || !journeyMapRecord) { setInboundContext(null); return; }
    const mapId = journeyMapRecord.id;
    listInboundLinksForMap(mapId)
      .then(async (links) => {
        if (links.length === 0) { setInboundContext(null); return; }
        // Take most-recently-created inbound link.
        const link = [...links].sort((a, b) => Number(b.created_at ?? 0) - Number(a.created_at ?? 0))[0]!;
        // Fetch source cell and parent map bundle (gives title + stages + lenses) in parallel.
        const [sourceCell, parentMapBundle] = await Promise.all([
          getJourneyCell(link.source_cell),
          loadJourneyMapBundle(link.source_map),
        ]);
        const stageLabel = parentMapBundle.stages.find((s) => s.xanoId === sourceCell.stage)?.label ?? `Stage ${sourceCell.stage}`;
        const lensLabel = parentMapBundle.lenses.find((l) => l.xanoId === sourceCell.lens)?.label ?? `Lens ${sourceCell.lens}`;
        setInboundContext({
          link_type: link.link_type,
          parent_map_id: link.source_map,
          parent_map_title: parentMapBundle.journeyMap.title ?? `Map ${link.source_map}`,
          source_cell_id: link.source_cell,
          source_stage_label: stageLabel,
          source_lens_label: lensLabel,
          trigger_content: sourceCell.content ?? null,
        });
      })
      .catch(() => setInboundContext(null));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [architectureId, journeyMapRecord?.id]);

  // Reset link form when the user selects a different cell.
  useEffect(() => {
    setCellLinkType('exception');
    setCellLinkTargetId('');
    setCellLinkNewTitle('');
    setCellLinkError(null);
    setCellLinkSuccess(false);
  }, [selectedCellId]);

  // Load journey links for the current map to power breakpoint indicators in the matrix.
  useEffect(() => {
    if (!journeyMapRecord) { setCellLinkMap(new Map()); return; }
    listJourneyLinksForMap(journeyMapRecord.id)
      .then((links) => {
        setCellLinkMap(
          new Map(links.map((l) => [l.source_cell, {linkType: l.link_type as JourneyLinkType, targetMapId: l.target_map}])),
        );
      })
      .catch(() => setCellLinkMap(new Map()));
  }, [journeyMapRecord?.id]);

  const handleCreateCellLink = async () => {
    if (!selectedCell?.xanoId || !journeyMapRecord || !architectureId || !cellLinkTargetId) return;
    setCellLinkCreating(true);
    setCellLinkError(null);
    try {
      let targetMapId: number;
      if (cellLinkTargetId === 'new') {
        const bundle = await createDraftJourneyMap({
          title: cellLinkNewTitle.trim() || 'Untitled Journey Map',
          status: 'draft',
          journey_architecture_id: architectureId,
        });
        targetMapId = bundle.journeyMap.id;
        setSiblingMaps((prev) => [...prev, bundle.journeyMap]);
      } else {
        targetMapId = cellLinkTargetId;
      }
      const link = await createJourneyLink(architectureId, {
        source_map_id: journeyMapRecord.id,
        source_cell_id: selectedCell.xanoId,
        target_map_id: targetMapId,
        link_type: cellLinkType,
      });
      // Show breakpoint indicator immediately on the cell
      setCellLinkMap((prev) => {
        const next = new Map(prev);
        next.set(selectedCell.xanoId!, { linkType: link.link_type, targetMapId: link.target_map });
        return next;
      });
      setCellLinkSuccess(true);
      if (cellLinkTargetId === 'new') {
        navigate(`/maps/${targetMapId}?arch=${architectureId}`);
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      setCellLinkError(
        msg.includes('already exists')
          ? 'This cell already links to that map.'
          : 'Failed to create link. Please try again.',
      );
    } finally {
      setCellLinkCreating(false);
    }
  };

  const handleCreateXanoDraft = useCallback(async () => {
    setIsXanoSyncing(true);
    setXanoError(null);

    try {
      const createdBundle = await createDraftJourneyMap({
        title: `Prototype 2 Smoke Test ${new Date().toLocaleString()}`,
        status: 'draft',
        settings: {source: 'webapp/protype-2 frontend integration'},
      });

      applyJourneyMapBundle(createdBundle);
      setInitialLoadState('ready');
    } catch (error) {
      setXanoError(error instanceof Error ? error.message : 'Unable to create journey map.');
      setInitialLoadState((currentState) => (currentState === 'ready' ? 'ready' : 'error'));
    } finally {
      setIsXanoSyncing(false);
    }
  }, [applyJourneyMapBundle]);

  const refreshConversationList = useCallback(async () => {
    if (!journeyMapRecord) return;
    setIsLoadingSessions(true);
    try {
      const items = await listConversations(journeyMapRecord.id);
      setConversationList(items);
    } catch {
      // Silently fail — list is non-critical
    } finally {
      setIsLoadingSessions(false);
    }
  }, [journeyMapRecord]);

  const handleToggleSessionPicker = useCallback(() => {
    setIsSessionPickerOpen((open) => {
      if (!open) {
        void refreshConversationList();
      }
      return !open;
    });
    setIsRenamingSession(null);
    setConfirmDeleteId(null);
  }, [refreshConversationList]);

  const handleSwitchSession = useCallback(async (conversationId: number) => {
    if (!journeyMapRecord) return;
    setIsLoadingSessions(true);
    setXanoError(null);
    try {
      const result = await getConversation(journeyMapRecord.id, conversationId);
      setConversationRecord(result.conversation);
      setMessages(result.messages);
      setIsChatMode(result.conversation.mode === 'chat');
      setIsSessionPickerOpen(false);
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to load conversation.'));
    } finally {
      setIsLoadingSessions(false);
    }
  }, [journeyMapRecord]);

  const handleCreateSession = useCallback(async () => {
    if (!journeyMapRecord) return;
    setIsLoadingSessions(true);
    setXanoError(null);
    try {
      const mode = isChatMode ? 'chat' as const : 'interview' as const;
      const newConversation = await createConversation({journeyMapId: journeyMapRecord.id, mode});
      setConversationRecord(newConversation);
      setMessages([]);
      setIsSessionPickerOpen(false);
      setLastUpdateSummaries([]);
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to create conversation.'));
    } finally {
      setIsLoadingSessions(false);
    }
  }, [journeyMapRecord, isChatMode]);

  const handleRenameSession = useCallback(async (conversationId: number, title: string) => {
    if (!journeyMapRecord || !title.trim()) return;
    try {
      const updated = await updateConversation({journeyMapId: journeyMapRecord.id, conversationId, title: title.trim()});
      if (conversationRecord?.id === conversationId) {
        setConversationRecord(updated);
      }
      setConversationList((list) => list.map((item) => item.id === conversationId ? {...item, title: updated.title} : item));
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to rename conversation.'));
    } finally {
      setIsRenamingSession(null);
    }
  }, [journeyMapRecord, conversationRecord?.id]);

  const handleDeleteSession = useCallback(async (conversationId: number) => {
    if (!journeyMapRecord) return;
    setXanoError(null);
    try {
      await deleteConversation(journeyMapRecord.id, conversationId);
      const nextList = conversationList.filter((item) => item.id !== conversationId);
      setConversationList(nextList);
      if (conversationRecord?.id === conversationId) {
        const next = nextList[0]; // list is already sorted by last_message_at desc
        if (next) {
          const result = await getConversation(journeyMapRecord.id, next.id);
          setConversationRecord(result.conversation);
          setMessages(result.messages);
          setIsChatMode(result.conversation.mode === 'chat');
          setLastUpdateSummaries([]);
        } else {
          setConversationRecord(null);
          setMessages([]);
          setLastUpdateSummaries([]);
        }
      }
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to delete conversation.'));
    } finally {
      setConfirmDeleteId(null);
    }
  }, [journeyMapRecord, conversationRecord?.id, conversationList]);

  const handleDeleteMessage = useCallback(async (msgId: string) => {
    if (!journeyMapRecord || !conversationRecord) return;
    const numericId = parseInt(msgId, 10);
    if (isNaN(numericId)) return;
    try {
      await deleteMessage(journeyMapRecord.id, conversationRecord.id, numericId);
      setMessages((prev) => prev.filter((m) => m.id !== msgId));
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to delete message.'));
    }
  }, [journeyMapRecord, conversationRecord]);

  const showWorkspace = initialLoadState === 'ready';
  const isScaffoldFallback = Boolean(journeyMapRecord) && matrixSyncSource === 'map-only';
  const selectedCell = cells.find((cell) => cell.id === selectedCellId) ?? null;
  const selectedStageLabel = selectedCell ? stages.find((stage) => stage.id === selectedCell.stageId)?.label ?? null : null;
  const selectedLensLabel = selectedCell ? lenses.find((lens) => lens.id === selectedCell.lensId)?.label ?? null : null;
  const selectedCellReference = buildCellReferenceLabel(selectedStageLabel, selectedLensLabel);
  const selectedCellShorthand = buildCellShorthand(selectedCell, stages, lenses);
  const selectedCellContext = buildSelectedCellContext({cell: selectedCell, stages, lenses, journeyMapId: journeyMapRecord?.id});
  const selectedCellLens = selectedCell ? lenses.find((l) => l.id === selectedCell.lensId) ?? null : null;

  /**
   * SE-B3: Memoized stage health for the detail panel.
   * Prefers explicit stage_health; falls back to calcStageHealth from sibling fields.
   */
  const metricsStageHealth = useMemo<number | null>(() => {
    if (!selectedCell?.actorFields || !isMetricsActorFields(selectedCell.actorFields)) return null;
    const f = selectedCell.actorFields;
    const explicit = parseMetricValue(f.stage_health);
    return explicit ?? calcStageHealth(f);
  }, [selectedCell?.actorFields]);

  const handleSendMessage = useCallback(async () => {
    const messageText = inputText.trim();
    if (!messageText) {
      return;
    }

    if (!journeyMapRecord) {
      setXanoError('Create or load a journey map before sending a message.');
      return;
    }

    setIsSendingMessage(true);
    setXanoError(null);
    setInputText('');

    // Show the user's message immediately — don't wait for the AI round-trip.
    setMessages((prev) => [
      ...prev,
      {
        id: `optimistic-${Date.now()}`,
        role: 'expert' as const,
        content: messageText,
        timestamp: new Date(),
      },
    ]);

    const currentMode = isChatMode ? 'chat' as const : 'interview' as const;
    const selectedCellPayload = buildSelectedCellPayload(selectedCellContext);

    try {
      const aiThread = await sendAiMessage({
        journeyMapId: journeyMapRecord.id,
        conversationId: conversationRecord?.id,
        content: messageText,
        mode: currentMode,
        selectedCell: selectedCellPayload,
        journeySettings,
        parentContext: inboundContext,
      });

      setConversationRecord(aiThread.conversation);
      setIsChatMode(aiThread.conversation?.mode === 'chat');
      setSuggestedPrompts(aiThread.suggestedPrompts.length > 0 ? aiThread.suggestedPrompts : []);

      // Build activity metadata for the last AI message (Layers 1-3 transparency)
      const activity: MessageActivity = {
        cellsUpdated: aiThread.cellUpdates.length,
        cellsSkipped: 0,
        structureChanged: aiThread.structuralChanges.stages_changed || aiThread.structuralChanges.lenses_changed,
        progress: aiThread.progress,
        updatedCells: aiThread.cellUpdates.map((u) => {
          const stg = stages.find((s) => s.xanoId === u.stage_id);
          const lns = lenses.find((l) => l.xanoId === u.lens_id);
          return { stageLabel: stg?.label ?? `Stage ${u.stage_id}`, lensLabel: lns?.label ?? `Lens ${u.lens_id}` };
        }),
        toolTrace: aiThread.toolTrace,
        thinking: aiThread.thinking,
        turnId: aiThread.turnId,
        stepLimitWarning: aiThread.stepLimitWarning,
      };

      // Always tag the last AI message so Layer 2 & 3 panels can render
      const taggedMessages = aiThread.messages.map((msg, idx) =>
        msg.role === 'ai' && idx === aiThread.messages.length - 1
          ? { ...msg, activity }
          : msg
      );

      setMessages(taggedMessages);

      // Apply cell updates from the AI agent to the matrix
      if (aiThread.cellUpdates.length > 0) {
        setCells((currentCells) =>
          currentCells.map((cell) => {
            const update = aiThread.cellUpdates.find(
              (u) => u.cell_id === cell.xanoId || u.cell_id === cell.journeyCellId,
            );
            if (!update) return cell;
            return {
              ...cell,
              content: update.content ?? cell.content,
              status: (update.status as CellStatus) ?? cell.status,
              isLocked: update.is_locked ?? cell.isLocked,
            };
          }),
        );
      }

      // If structural changes occurred (stages/lenses added or removed), reload the full bundle
      if (aiThread.structuralChanges.stages_changed || aiThread.structuralChanges.lenses_changed) {
        const bundle = await loadJourneyMapBundle(journeyMapRecord.id, journeyMapRecord);
        applyJourneyMapBundle(bundle);
      }
    } catch (error) {
      setInputText(messageText);
      setXanoError(getErrorMessage(error, 'Unable to send AI message.'));
    } finally {
      setIsSendingMessage(false);
    }
  }, [conversationRecord?.id, inputText, isChatMode, journeyMapRecord, selectedCellContext, lenses, stages]);

  const handleSaveAllSettings = useCallback(async () => {
    if (!journeyMapRecord) return;
    setIsSavingSettings(true);
    setSettingsSaved(false);
    try {
      await saveJourneySettings(journeyMapRecord.id, settingsDraft);
      setJourneySettings(settingsDraft);
      setSettingsSaved(true);
      setTimeout(() => setSettingsSaved(false), 2500);
    } catch {
      // non-critical
    } finally {
      setIsSavingSettings(false);
    }
  }, [journeyMapRecord, settingsDraft]);

  const handleSmartAiSettingChange = useCallback(async (patch: Partial<SmartAiSettings>) => {
    if (!journeyMapRecord) return;
    setSmartAiSettings((prev) => ({...prev, ...patch}));
    setIsSmartAiSettingsSaving(true);
    setSmartAiSettingsError(null);
    try {
      await saveSmartAiSettings(journeyMapRecord.id, patch);
    } catch {
      setSmartAiSettingsError('Unable to save — please try again.');
    } finally {
      setIsSmartAiSettingsSaving(false);
    }
  }, [journeyMapRecord]);

  const persistCellChanges = useCallback(
    async (cell: MatrixCell | null | undefined, rollbackCell?: MatrixCell | null) => {
      if (!cell) {
        return true;
      }

      const baselineCell = resolveCellPersistenceBaseline(rollbackCell, selectedCellSnapshot);
      if (!hasPendingCellChanges(cell, baselineCell)) {
        return true;
      }

      setIsXanoSyncing(true);
      setXanoError(null);

      try {
        const persistedCell = await updateJourneyCell({
          journeyCellId: resolveXanoId(cell, 'cell'),
          content: cell.content,
          status: cell.status,
          isLocked: Boolean(cell.isLocked),
          actorFields: cell.actorFields,
        });

        const nextCell: MatrixCell = {
          ...cell,
          xanoId: persistedCell.id,
          journeyCellId: persistedCell.id,
          journeyMapId: persistedCell.journey_map,
          content: persistedCell.content ?? '',
          stageXanoId: persistedCell.stage,
          stageKey: cell.stageKey ?? cell.stageId,
          status: normalizePersistedCellStatus(persistedCell.status, cell.status),
          isLocked: Boolean(persistedCell.is_locked),
          lensXanoId: persistedCell.lens,
          lensKey: cell.lensKey ?? cell.lensId,
          lastUpdated: persistedCell.last_updated_at ? new Date(persistedCell.last_updated_at) : new Date(),
          actorFields: (persistedCell.actor_fields ?? cell.actorFields) as MatrixCell['actorFields'],
        };

        setCells((currentCells) => currentCells.map((entry) => (entry.id === cell.id ? nextCell : entry)));

        if (selectedCellId === cell.id) {
          setSelectedCellSnapshot(cloneCellSnapshot(nextCell));
        }

        // Debounced scorecard refresh after cell save (SE-D1)
        if (persistedCell.journey_map) debouncedRefreshScorecard(persistedCell.journey_map);

        return true;
      } catch (error) {
        if (baselineCell) {
          setCells((currentCells) => currentCells.map((entry) => (entry.id === cell.id ? baselineCell : entry)));

          if (selectedCellId === cell.id) {
            setSelectedCellSnapshot(cloneCellSnapshot(baselineCell));
          }
        }

        setXanoError(getErrorMessage(error, 'Unable to save cell changes.'));
        return false;
      } finally {
        setIsXanoSyncing(false);
      }
    },
    [selectedCellId, selectedCellSnapshot, debouncedRefreshScorecard],
  );

  const handleSelectCell = useCallback(
    (nextCellId: string) => {
      void (async () => {
        if (selectedCellId === nextCellId) {
          return;
        }

        const didPersistCurrentCell = await persistCellChanges(selectedCell);
        if (!didPersistCurrentCell) {
          return;
        }

        const nextSelectedCell = cells.find((cell) => cell.id === nextCellId) ?? null;
        setSelectedCellId(nextCellId);
        setSelectedCellSnapshot(cloneCellSnapshot(nextSelectedCell));
      })();
    },
    [cells, persistCellChanges, selectedCell, selectedCellId],
  );

  const handleCloseSelectedCell = useCallback(() => {
    void (async () => {
      const didPersistCurrentCell = await persistCellChanges(selectedCell);
      if (!didPersistCurrentCell) {
        return;
      }

      setSelectedCellId(null);
      setSelectedCellSnapshot(null);
    })();
  }, [persistCellChanges, selectedCell]);

  const updateCellStatus = (id: string, status: CellStatus) => {
    setCells((currentCells) => currentCells.map((cell) => (cell.id === id ? {...cell, status} : cell)));
  };

  const updateCellContent = (id: string, content: string) => {
    setCells((currentCells) => currentCells.map((cell) => (cell.id === id ? {...cell, content} : cell)));
  };

  const updateCellActorField = (id: string, fieldKey: string, value: string) => {
    setCells((currentCells) =>
      currentCells.map((cell) =>
        cell.id === id
          ? {...cell, actorFields: {...(cell.actorFields as Record<string, string | null> ?? {}), [fieldKey]: value || null}}
          : cell,
      ),
    );
  };

  /** Updates a numeric MetricsActorFields field, converting the raw input string to number | null. */
  const updateCellMetricField = (id: string, fieldKey: string, raw: string) => {
    const num = raw.trim() === '' ? null : Number(raw);
    const value = num === null || isNaN(num) ? null : num;
    setCells((currentCells) =>
      currentCells.map((cell) =>
        cell.id === id
          ? {...cell, actorFields: {...(cell.actorFields as Record<string, unknown> ?? {}), [fieldKey]: value}}
          : cell,
      ),
    );
  };

  const toggleCellLock = (id: string) => {
    setCells((currentCells) => currentCells.map((cell) => (cell.id === id ? {...cell, isLocked: !cell.isLocked} : cell)));
  };

  const updateStageLabel = (id: string, label: string) => {
    const currentStage = stages.find((stage) => stage.id === id);
    if (!currentStage) {
      return;
    }

    const nextLabel = label.trim();
    if (!nextLabel) {
      setXanoError('Stage label is required.');
      return;
    }

    if (nextLabel === currentStage.label) {
      return;
    }

    // Spread preserves the canonical key — only the display label changes.
    setStages((currentStages) => currentStages.map((stage) => (stage.id === id ? {...stage, label: nextLabel} : stage)));
    setLastUpdateSummaries([]);

    void (async () => {
      setIsXanoSyncing(true);
      setXanoError(null);

      try {
        await renameJourneyStage({journeyStageId: resolveXanoId(currentStage, 'stage'), label: nextLabel});
      } catch (error) {
        setStages((currentStages) => currentStages.map((stage) => (stage.id === id ? {...stage, label: currentStage.label} : stage)));
        setXanoError(getErrorMessage(error, 'Unable to rename stage.'));
      } finally {
        setIsXanoSyncing(false);
      }
    })();
  };

  const updateLensLabel = (id: string, label: string) => {
    const currentLens = lenses.find((lens) => lens.id === id);
    if (!currentLens) {
      return;
    }

    const nextLabel = label.trim();
    if (!nextLabel) {
      setXanoError('Lens label is required.');
      return;
    }

    if (nextLabel === currentLens.label) {
      return;
    }

    // Spread preserves the canonical key — only the display label changes.
    setLenses((currentLenses) => currentLenses.map((lens) => (lens.id === id ? {...lens, label: nextLabel} : lens)));
    setLastUpdateSummaries([]);

    void (async () => {
      setIsXanoSyncing(true);
      setXanoError(null);

      try {
        await renameJourneyLens({journeyLensId: resolveXanoId(currentLens, 'lens'), label: nextLabel});
      } catch (error) {
        setLenses((currentLenses) => currentLenses.map((lens) => (lens.id === id ? {...lens, label: currentLens.label} : lens)));
        setXanoError(getErrorMessage(error, 'Unable to rename lens.'));
      } finally {
        setIsXanoSyncing(false);
      }
    })();
  };

  const addStage = async () => {
    const didPersistCurrentCell = await persistCellChanges(selectedCell);
    if (!didPersistCurrentCell) {
      return;
    }

    if (!journeyMapRecord) {
      setXanoError(DEFAULT_MATRIX_EDIT_ERROR);
      return;
    }

    setIsXanoSyncing(true);
    setXanoError(null);
    setLastUpdateSummaries([]);

    try {
      await addJourneyStage({journeyMapId: journeyMapRecord.id});
      await refreshCurrentJourneyMap(journeyMapRecord);
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to add stage.'));
    } finally {
      setIsXanoSyncing(false);
    }
  };

  const removeStage = async (id: string) => {
    if (stages.length <= 1) {
      return;
    }

    const stageToRemove = stages.find((stage) => stage.id === id);
    if (!stageToRemove) {
      return;
    }

    const didPersistCurrentCell = await persistCellChanges(selectedCell);
    if (!didPersistCurrentCell) {
      return;
    }

    setIsXanoSyncing(true);
    setXanoError(null);
    setLastUpdateSummaries([]);

    try {
      await removeJourneyStage({journeyStageId: resolveXanoId(stageToRemove, 'stage')});
      await refreshCurrentJourneyMap(journeyMapRecord);
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to remove stage.'));
    } finally {
      setIsXanoSyncing(false);
    }
  };

  const addLens = async (actorInput?: ActorWizardInput) => {
    const didPersistCurrentCell = await persistCellChanges(selectedCell);
    if (!didPersistCurrentCell) {
      return;
    }

    if (!journeyMapRecord) {
      setXanoError(DEFAULT_MATRIX_EDIT_ERROR);
      return;
    }

    setIsXanoSyncing(true);
    setXanoError(null);
    setLastUpdateSummaries([]);

    try {
      await addJourneyLens({
        journeyMapId: journeyMapRecord.id,
        ...(actorInput && {
          label: actorInput.label,
          actorType: actorInput.actorType,
          templateKey: actorInput.templateKey,
          rolePrompt: actorInput.rolePrompt,
          personaDescription: actorInput.personaDescription,
          primaryGoal: actorInput.primaryGoal,
          standingConstraints: actorInput.standingConstraints,
        }),
      });
      await refreshCurrentJourneyMap(journeyMapRecord);
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to add lens.'));
    } finally {
      setIsXanoSyncing(false);
    }
  };

  const handleActorWizardConfirm = async (input: ActorWizardInput) => {
    if (actorWizardEditTarget?.xanoId) {
      // Edit mode — PATCH existing lens actor fields
      await updateLensActorFields({
        journeyLensId: actorWizardEditTarget.xanoId,
        label: input.label,
        actorType: input.actorType,
        templateKey: input.templateKey,
        rolePrompt: input.rolePrompt,
        personaDescription: input.personaDescription,
        primaryGoal: input.primaryGoal,
        standingConstraints: input.standingConstraints,
      });
      if (journeyMapRecord) {
        await refreshCurrentJourneyMap(journeyMapRecord);
      }
    } else {
      // Create mode — add a new lens row
      await addLens(input);
    }
    setShowActorWizard(false);
    setActorWizardEditTarget(null);
  };

  const handleEditActorOpen = (lens: Lens) => {
    setActorWizardEditTarget(lens);
    setShowActorWizard(true);
  };

  const handleLensEditFromMatrix = (lensId: string) => {
    const lens = lenses.find((l) => l.id === lensId);
    if (lens) {
      handleEditActorOpen(lens);
    }
  };

  const removeLens = async (id: string) => {
    if (lenses.length <= 1) {
      return;
    }

    const lensToRemove = lenses.find((lens) => lens.id === id);
    if (!lensToRemove) {
      return;
    }

    const didPersistCurrentCell = await persistCellChanges(selectedCell);
    if (!didPersistCurrentCell) {
      return;
    }

    setIsXanoSyncing(true);
    setXanoError(null);
    setLastUpdateSummaries([]);

    try {
      await removeJourneyLens({journeyLensId: resolveXanoId(lensToRemove, 'lens')});
      await refreshCurrentJourneyMap(journeyMapRecord);
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to remove lens.'));
    } finally {
      setIsXanoSyncing(false);
    }
  };

  const userInitials = user?.name
    ? user.name.split(' ').map((w: string) => w[0]).join('').slice(0, 2).toUpperCase()
    : 'U';

  return (
    <div className="flex flex-col h-screen overflow-hidden bg-zinc-50 font-sans">
      {/* Editor top bar */}
      <div className="h-10 border-b border-zinc-200 bg-white flex items-center justify-between px-4 shrink-0 z-20">
        <button
          onClick={() => navigate(
            architectureId
              ? fromScenarios
                ? `/architectures/${architectureId}?tab=scenarios`
                : `/architectures/${architectureId}`
              : '/dashboard'
          )}
          className="flex items-center gap-1.5 text-xs text-zinc-500 hover:text-zinc-900 transition-colors"
        >
          <ArrowLeft className="w-3.5 h-3.5" />
          <span className="font-medium">
            {architectureId ? (fromScenarios ? 'Scenarios' : 'Architecture') : 'Dashboard'}
          </span>
        </button>
        <span className="text-xs font-semibold text-zinc-700 truncate max-w-xs px-2">
          {journeyMapRecord?.title ?? ''}
        </span>
        <div className="flex items-center gap-2">
          <div className="w-6 h-6 rounded-full bg-zinc-800 text-white flex items-center justify-center text-[10px] font-bold">{userInitials}</div>
          <button
            onClick={() => { logout(); navigate('/login'); }}
            title="Sign out"
            className="p-1 text-zinc-400 hover:text-zinc-700 transition-colors"
          >
            <LogOut className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* Parent Journey Context Strip — shown when this map is a child (anti-journey / exception / sub-journey) */}
      {inboundContext && (() => {
        const LINK_TYPE_LABEL: Record<string, string> = {exception: 'Exception', anti_journey: 'Anti-Journey', sub_journey: 'Sub-Journey'};
        const LINK_TYPE_ICON: Record<string, string> = {exception: '⚠', anti_journey: '↩', sub_journey: '⤵'};
        const truncated = inboundContext.trigger_content
          ? (inboundContext.trigger_content.length > 120
              ? inboundContext.trigger_content.slice(0, 117) + '…'
              : inboundContext.trigger_content)
          : null;
        return (
          <div className="shrink-0 border-b border-amber-200 bg-amber-50 px-4 py-1.5 flex items-center gap-3 z-10">
            <span className="text-sm shrink-0" title={LINK_TYPE_LABEL[inboundContext.link_type]}>{LINK_TYPE_ICON[inboundContext.link_type]}</span>
            <span className="text-[11px] font-semibold text-amber-700 shrink-0 uppercase tracking-wider">{LINK_TYPE_LABEL[inboundContext.link_type]}</span>
            <span className="text-zinc-300 shrink-0">·</span>
            <span className="text-[11px] font-semibold text-zinc-600 shrink-0 truncate max-w-[120px]" title={inboundContext.parent_map_title}>{inboundContext.parent_map_title}</span>
            <span className="text-zinc-300 shrink-0">·</span>
            <span className="text-[11px] text-zinc-500 shrink-0">{inboundContext.source_stage_label} × {inboundContext.source_lens_label}</span>
            {truncated ? (
              <>
                <span className="text-zinc-300 shrink-0">·</span>
                <span className="text-[11px] text-zinc-500 italic truncate min-w-0" title={inboundContext.trigger_content ?? undefined}>"{truncated}"</span>
              </>
            ) : (
              <>
                <span className="text-zinc-300 shrink-0">·</span>
                <span className="text-[11px] text-zinc-400 italic shrink-0">No content recorded at this cell</span>
              </>
            )}
            <button
              onClick={() => navigate(`/maps/${inboundContext.parent_map_id}?arch=${architectureId}`)}
              className="ml-auto shrink-0 text-[11px] font-medium text-amber-700 hover:text-amber-900 flex items-center gap-1 transition-colors"
            >
              View source <ArrowLeft className="w-3 h-3 rotate-180" />
            </button>
          </div>
        );
      })()}

      {/* Main Content */}
      <main ref={mainRef} className="flex-1 flex flex-col overflow-hidden relative">
        {!showWorkspace ? (
          <section className="flex-1 bg-zinc-100 p-6">
            <div className="flex h-full min-h-[520px] items-center justify-center rounded-sm border border-zinc-200 bg-white shadow-sm">
              {initialLoadState === 'loading' && (
                <div className="max-w-md px-6 text-center">
                  <RotateCcw className="mx-auto h-8 w-8 animate-spin text-zinc-400" />
                  <h2 className="mt-4 text-sm font-semibold text-zinc-900">Loading journey map from Xano</h2>
                  <p className="mt-2 text-xs leading-6 text-zinc-500">
                    Fetching the latest saved map so the matrix and chat start from backend state instead of local mock data.
                  </p>
                </div>
              )}

              {initialLoadState === 'empty' && (
                <div className="max-w-md px-6 text-center">
                  <LayoutGrid className="mx-auto h-8 w-8 text-zinc-400" />
                  <h2 className="mt-4 text-sm font-semibold text-zinc-900">No saved journey maps yet</h2>
                  <p className="mt-2 text-xs leading-6 text-zinc-500">
                    Xano is connected, but there is no persisted journey map to load on startup yet.
                  </p>
                  <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
                    <button
                      onClick={() => void handleCreateXanoDraft()}
                      disabled={isXanoSyncing}
                      className="inline-flex items-center gap-2 rounded-md bg-zinc-900 px-3 py-2 text-xs font-medium text-white transition-colors hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      <Play className="h-3.5 w-3.5" />
                      Create Xano Draft
                    </button>
                    <button
                      onClick={() => void syncLatestJourneyMap()}
                      disabled={isXanoSyncing}
                      className="inline-flex items-center gap-2 rounded-md border border-zinc-200 bg-white px-3 py-2 text-xs font-medium text-zinc-600 transition-colors hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      <RotateCcw className="h-3.5 w-3.5" />
                      Retry Load
                    </button>
                  </div>
                </div>
              )}

              {initialLoadState === 'error' && (
                <div className="max-w-lg px-6 text-center">
                  <Info className="mx-auto h-8 w-8 text-rose-500" />
                  <h2 className="mt-4 text-sm font-semibold text-zinc-900">Unable to load journey map</h2>
                  <p className="mt-2 text-xs leading-6 text-zinc-500">
                    {xanoError ?? 'The app could not reach Xano during startup.'}
                  </p>
                  <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
                    <button
                      onClick={() => void syncLatestJourneyMap()}
                      disabled={isXanoSyncing}
                      className="inline-flex items-center gap-2 rounded-md bg-zinc-900 px-3 py-2 text-xs font-medium text-white transition-colors hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      <RotateCcw className="h-3.5 w-3.5" />
                      Retry Load
                    </button>
                    <button
                      onClick={() => void handleCreateXanoDraft()}
                      disabled={isXanoSyncing}
                      className="inline-flex items-center gap-2 rounded-md border border-zinc-200 bg-white px-3 py-2 text-xs font-medium text-zinc-600 transition-colors hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      <Play className="h-3.5 w-3.5" />
                      Create Xano Draft
                    </button>
                  </div>
                </div>
              )}
            </div>
          </section>
        ) : (
          <>
            {/* Journey Map Matrix Section (Now Full Screen) */}
            <section className="flex-1 min-h-0 flex flex-col bg-zinc-100 overflow-hidden relative">
              {xanoError && (
                <div className="border-b border-rose-200 bg-rose-50 px-6 py-3 text-xs text-rose-900">
                  <div className="font-semibold">Latest Xano action failed</div>
                  <div className="mt-1 text-rose-700">{xanoError}</div>
                </div>
              )}

              {isScaffoldFallback && (
                <div className="border-b border-amber-200 bg-amber-50 px-6 py-3 text-xs text-amber-900">
                  <div className="font-semibold">Backend map loaded without persisted matrix records</div>
                  <div className="mt-1 text-amber-800">
                    Showing the local scaffold as an explicit fallback until stages, lenses, and cells are saved in Xano.
                  </div>
                </div>
              )}

              {/* Matrix Controls & Stats */}
              <div
                className={`min-h-12 border-b border-zinc-200 bg-white px-6 py-3 shrink-0 transition-[padding] duration-200 ${
                  selectedCell ? 'pr-[22rem]' : ''
                }`}
              >
                <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex flex-wrap items-center gap-6">
                  <div className="flex items-center gap-2">
                    <LayoutGrid className="w-4 h-4 text-zinc-400" />
                    <span className="text-xs font-semibold text-zinc-700 uppercase tracking-tight">Journey Matrix</span>
                  </div>
                  <div className="flex items-center gap-4 text-[11px] font-medium">
                    <div className="flex items-center gap-1.5 text-emerald-600">
                      <CheckCircle2 className="w-3.5 h-3.5" />
                      {cells.filter(c => c.status === 'confirmed').length} Confirmed
                    </div>
                    <div className="flex items-center gap-1.5 text-amber-600">
                      <CircleDashed className="w-3.5 h-3.5" />
                      {cells.filter(c => c.status === 'draft').length} Drafts
                    </div>
                    <div className="flex items-center gap-1.5 text-zinc-400">
                      <HelpCircle className="w-3.5 h-3.5" />
                      {cells.filter(c => c.status === 'open').length} Open
                    </div>
                  </div>
                </div>

                <div className="flex flex-wrap items-center gap-2">
                  <button
                    onClick={() => void addStage()}
                    disabled={isXanoSyncing}
                    className="inline-flex items-center gap-1.5 rounded border border-zinc-200 bg-white px-2.5 py-1.5 text-[11px] font-medium text-zinc-600 transition-colors hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    <Plus className="h-3.5 w-3.5" />
                    Add Column
                  </button>
                  <button
                    onClick={() => { setActorWizardEditTarget(null); setShowActorWizard(true); }}
                    disabled={isXanoSyncing}
                    className="inline-flex items-center gap-1.5 rounded border border-zinc-200 bg-white px-2.5 py-1.5 text-[11px] font-medium text-zinc-600 transition-colors hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    <Plus className="h-3.5 w-3.5" />
                    Add Row
                  </button>
                  <button
                    onClick={() => selectedCell && void removeStage(selectedCell.stageId)}
                    disabled={!selectedCell || stages.length <= 1 || isXanoSyncing}
                    title={selectedStageLabel ? `Remove ${selectedStageLabel}` : 'Select a cell to remove its column'}
                    className="inline-flex items-center gap-1.5 rounded border border-zinc-200 bg-white px-2.5 py-1.5 text-[11px] font-medium text-zinc-600 transition-colors hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                    Remove Column
                  </button>
                  <button
                    onClick={() => selectedCell && void removeLens(selectedCell.lensId)}
                    disabled={!selectedCell || lenses.length <= 1 || isXanoSyncing}
                    title={selectedLensLabel ? `Remove ${selectedLensLabel}` : 'Select a cell to remove its row'}
                    className="inline-flex items-center gap-1.5 rounded border border-zinc-200 bg-white px-2.5 py-1.5 text-[11px] font-medium text-zinc-600 transition-colors hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                    Remove Row
                  </button>
                  <div className="relative">
                    <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-zinc-400" />
                    <input value={searchTerm} onChange={(e) => setSearchTerm(e.target.value)} type="text" placeholder="Search matrix..." className="pl-8 pr-3 py-1.5 bg-zinc-100 border-none rounded text-xs focus:ring-1 focus:ring-zinc-300 w-48" />
                  </div>
                  {/* US-MET-19 — Journey Health chip: always-visible signal, toggles right sidebar */}
                  {METRICS_ACTOR_ENABLED && journeyMapRecord && (
                    <button
                      onClick={() => setWidgetVisible(v => !v)}
                      title="Journey Health"
                      className={`inline-flex items-center gap-1.5 rounded border px-2.5 py-1.5 text-[11px] font-medium transition-colors ${widgetVisible ? 'border-indigo-300 bg-indigo-50 text-indigo-700' : 'border-zinc-200 bg-white text-zinc-600 hover:bg-zinc-50'}`}
                    >
                      <BarChart2 className="h-3.5 w-3.5" />
                      {scorecard?.metrics_rollup?.map_health != null
                        ? scorecard.metrics_rollup.map_health.toFixed(1)
                        : '—'}
                      <span className={`text-[10px] ${scorecard?.metrics_rollup?.map_hl === 'healthy' ? 'text-emerald-500' : scorecard?.metrics_rollup?.map_hl === 'at_risk' ? 'text-amber-500' : scorecard?.metrics_rollup?.map_hl === 'critical' ? 'text-red-500' : 'text-zinc-300'}`}>●</span>
                    </button>
                  )}
                  <button
                    onClick={() => setIsSettingsOpen((v) => !v)}
                    title="Journey Settings"
                    className={`inline-flex items-center gap-1.5 rounded border px-2.5 py-1.5 text-[11px] font-medium transition-colors ${isSettingsOpen ? 'border-zinc-400 bg-zinc-100 text-zinc-900' : 'border-zinc-200 bg-white text-zinc-600 hover:bg-zinc-50'}`}
                  >
                    <Settings className="h-3.5 w-3.5" />
                    Settings
                  </button>
                </div>
                </div>
              </div>

              <div className="flex-1 min-h-0 overflow-hidden p-6">
                <div className="h-full min-h-0 overflow-hidden rounded-sm border border-zinc-200 bg-white shadow-sm">
                  <JourneyMatrixTabulator
                    stages={stages}
                    lenses={lenses}
                    cells={cells}
                    selectedCellId={selectedCellId}
                    searchTerm={searchTerm}
                    onSelectCell={handleSelectCell}
                    onUpdateLensLabel={updateLensLabel}
                    onUpdateStageLabel={updateStageLabel}
                    linkedCells={cellLinkMap}
                    onEditLens={handleLensEditFromMatrix}
                  />
                </div>
              </div>

              {/* Journey Settings Panel (Left Side) */}
              <AnimatePresence>
                {isSettingsOpen && (
                  <motion.div
                    initial={{ x: '-100%' }}
                    animate={{ x: 0 }}
                    exit={{ x: '-100%' }}
                    transition={{ type: 'spring', damping: 25, stiffness: 200 }}
                    className="absolute left-0 top-0 bottom-0 w-96 bg-white border-r border-zinc-200 shadow-2xl z-40 flex flex-col"
                  >
                    <div className="h-14 flex items-center justify-between px-4 border-b border-zinc-200 bg-zinc-50 shrink-0">
                      <div className="flex items-center gap-2">
                        <Settings className="w-4 h-4 text-zinc-400" />
                        <span className="text-xs font-semibold text-zinc-700 uppercase tracking-tight">Journey Settings</span>
                      </div>
                      <button onClick={() => setIsSettingsOpen(false)} className="p-1.5 hover:bg-zinc-200 rounded text-zinc-400 transition-colors">
                        <X className="w-4 h-4" />
                      </button>
                    </div>
                    <div className="flex-1 overflow-y-auto p-4 space-y-4">
                      {([
                        {field: 'primary_actor',       label: 'Primary Actor',              placeholder: 'e.g. Residential customer purchasing appliance', long: false},
                        {field: 'journey_scope',        label: 'Journey Scope',              placeholder: 'e.g. From order placement to delivery, excludes post-delivery support', long: true},
                        {field: 'start_point',          label: 'Start Point',               placeholder: 'e.g. Customer places order online', long: false},
                        {field: 'end_point',            label: 'End Point',                 placeholder: 'e.g. Delivery completed and signed off', long: false},
                        {field: 'duration',             label: 'Duration',                  placeholder: 'e.g. 7 to 14 days from order to delivery', long: false},
                        {field: 'success_metrics',      label: 'Success Metrics',           placeholder: 'e.g. On-time delivery, satisfaction score above 4.5 stars', long: true},
                        {field: 'key_stakeholders',     label: 'Key Stakeholders',          placeholder: 'e.g. Customer, driver, warehouse, AI system', long: true},
                        {field: 'dependencies',         label: 'Dependencies & Assumptions', placeholder: 'e.g. Inventory available, customer home during window', long: true},
                        {field: 'pain_points_summary',  label: 'Pain Points Summary',       placeholder: 'e.g. Last-minute cancellations, address issues', long: true},
                        {field: 'opportunities',        label: 'Opportunities',             placeholder: 'e.g. Better real-time tracking, predictive availability', long: true},
                        {field: 'version',              label: 'Version / Last Updated',    placeholder: 'e.g. Version 2.1, updated April 2026', long: false},
                      ] as {field: keyof JourneySettings; label: string; placeholder: string; long: boolean}[]).map(({field, label, placeholder, long}) => (
                        <div key={field}>
                          <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-1">{label}</label>
                          {long ? (
                            <textarea
                              value={settingsDraft[field] ?? ''}
                              onChange={(e) => setSettingsDraft((d) => ({...d, [field]: e.target.value}))}
                              placeholder={placeholder}
                              disabled={!journeyMapRecord}
                              rows={3}
                              className="w-full p-2.5 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-300 resize-none disabled:opacity-50"
                            />
                          ) : (
                            <input
                              type="text"
                              value={settingsDraft[field] ?? ''}
                              onChange={(e) => setSettingsDraft((d) => ({...d, [field]: e.target.value}))}
                              placeholder={placeholder}
                              disabled={!journeyMapRecord}
                              className="w-full p-2.5 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-300 disabled:opacity-50"
                            />
                          )}
                        </div>
                      ))}
                      {!journeyMapRecord && (
                        <p className="text-[10px] text-zinc-400 italic">Create or load a journey map to edit settings.</p>
                      )}
                    </div>
                    <div className="shrink-0 border-t border-zinc-200 px-4 py-3 flex items-center justify-between bg-zinc-50">
                      {settingsSaved ? (
                        <span className="text-[11px] text-emerald-600 font-medium">✓ Saved</span>
                      ) : (
                        <span className="text-[11px] text-zinc-400">Unsaved changes</span>
                      )}
                      <button
                        onClick={() => void handleSaveAllSettings()}
                        disabled={!journeyMapRecord || isSavingSettings}
                        className="px-3 py-1.5 bg-zinc-900 text-white text-[11px] font-medium rounded hover:bg-zinc-700 disabled:opacity-40 transition-colors"
                      >
                        {isSavingSettings ? 'Saving...' : 'Save'}
                      </button>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>

              {/* AI Chat Slider (Right Side) */}
              <AnimatePresence>
                {isChatOpen && (
                  <motion.div 
                    initial={{ x: '100%' }}
                    animate={{ x: 0 }}
                    exit={{ x: '100%' }}
                    transition={{ type: 'spring', damping: 25, stiffness: 200 }}
                    className="absolute right-0 top-0 bottom-0 w-96 bg-white border-l border-zinc-200 shadow-2xl z-40 flex flex-col"
                  >
                <div className="border-b border-zinc-200 shrink-0 bg-zinc-50">
                  <div className="h-14 flex items-center justify-between px-4">
                    <div className="flex items-center gap-3">
                      <div className="flex flex-col gap-1">
                        <button
                          type="button"
                          onClick={handleToggleSessionPicker}
                          className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg border text-[10px] font-bold uppercase tracking-widest leading-none transition-colors ${isSessionPickerOpen ? 'border-zinc-400 bg-zinc-100 text-zinc-900' : 'border-zinc-200 bg-white text-zinc-700 hover:bg-zinc-50 hover:border-zinc-300'} shadow-sm`}
                        >
                          {conversationRecord?.title ?? 'AI Interviewer'}
                          <ChevronDown className={`w-3 h-3 transition-transform ${isSessionPickerOpen ? 'rotate-180' : ''}`} />
                        </button>
                        <span className="text-[9px] text-zinc-400 font-medium ml-0.5">{isChatMode ? 'Chat Mode' : 'Interview Mode'}</span>
                      </div>
                      <div className="flex items-center rounded-lg border border-zinc-200 bg-white p-0.5 shadow-sm">
                        <button
                          type="button"
                          onClick={() => setIsChatMode(false)}
                          disabled={isSendingMessage}
                          aria-pressed={!isChatMode}
                          className={`px-2.5 py-1 rounded-md text-[10px] font-semibold transition-colors ${!isChatMode ? 'bg-zinc-900 text-white shadow-sm' : 'text-zinc-500 hover:text-zinc-900'} disabled:opacity-50`}
                        >
                          Interview
                        </button>
                        <button
                          type="button"
                          onClick={() => setIsChatMode(true)}
                          disabled={isSendingMessage}
                          aria-pressed={isChatMode}
                          className={`px-2.5 py-1 rounded-md text-[10px] font-semibold transition-colors ${isChatMode ? 'bg-zinc-900 text-white shadow-sm' : 'text-zinc-500 hover:text-zinc-900'} disabled:opacity-50`}
                        >
                          Chat
                        </button>
                      </div>
                    </div>
                    <div className="flex items-center gap-1">
                      <button
                        onClick={() => { setIsSmartAiSettingsOpen((o) => !o); setSmartAiSettingsError(null); }}
                        title="Smart AI Settings"
                        className={`p-1.5 rounded transition-colors ${isSmartAiSettingsOpen ? 'bg-zinc-900 text-white' : 'hover:bg-zinc-200 text-zinc-400'}`}
                      >
                        <Settings className="w-4 h-4" />
                      </button>
                      <button onClick={() => { setIsChatOpen(false); setIsSmartAiSettingsOpen(false); }} className="p-1.5 hover:bg-zinc-200 rounded text-zinc-400 transition-colors">
                        <X className="w-4 h-4" />
                      </button>
                    </div>
                  </div>

                  {/* Smart AI Settings Panel */}
                  {isSmartAiSettingsOpen && (
                    <div className="border-t border-zinc-200 bg-white overflow-y-auto max-h-[70%]">
                      <div className="p-4 space-y-5">
                        <div className="flex items-center justify-between">
                          <span className="text-[11px] font-bold text-zinc-900 uppercase tracking-wider">Smart AI Settings</span>
                          {isSmartAiSettingsSaving && <span className="text-[10px] text-zinc-400 animate-pulse">Saving…</span>}
                        </div>
                        {smartAiSettingsError && (
                          <div className="text-[10px] text-red-600 bg-red-50 border border-red-200 rounded px-2 py-1.5">{smartAiSettingsError}</div>
                        )}

                        {/* Interview Depth */}
                        <div>
                          <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider block mb-0.5">Interview Depth</label>
                          <p className="text-[10px] text-zinc-400 mb-2">How deeply the AI works each stage before moving on</p>
                          <div className="flex rounded-lg border border-zinc-200 overflow-hidden text-[10px] font-semibold">
                            {(['strategic', 'discovery', 'rapid_capture'] as InterviewDepth[]).map((v) => (
                              <button key={v} disabled={!journeyMapRecord}
                                onClick={() => void handleSmartAiSettingChange({interview_depth: v})}
                                className={`flex-1 py-1.5 transition-colors ${smartAiSettings.interview_depth === v ? 'bg-zinc-900 text-white' : 'text-zinc-500 hover:bg-zinc-50'} disabled:opacity-40`}
                              >{v === 'rapid_capture' ? 'Rapid' : v.charAt(0).toUpperCase() + v.slice(1)}</button>
                            ))}
                          </div>
                        </div>

                        {/* Insight Standard */}
                        <div>
                          <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider block mb-0.5">Insight Standard</label>
                          <p className="text-[10px] text-zinc-400 mb-2">Write first, then probe — Deep Dive uses 5-Whys to enrich across turns</p>
                          <div className="flex rounded-lg border border-zinc-200 overflow-hidden text-[10px] font-semibold">
                            {(['surface', 'discovery', 'deep_dive'] as InsightStandard[]).map((v) => (
                              <button key={v} disabled={!journeyMapRecord}
                                onClick={() => void handleSmartAiSettingChange({insight_standard: v})}
                                className={`flex-1 py-1.5 transition-colors ${smartAiSettings.insight_standard === v ? 'bg-zinc-900 text-white' : 'text-zinc-500 hover:bg-zinc-50'} disabled:opacity-40`}
                              >{v === 'deep_dive' ? 'Deep Dive' : v.charAt(0).toUpperCase() + v.slice(1)}</button>
                            ))}
                          </div>
                        </div>

                        {/* Lens Priority */}
                        <div>
                          <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider block mb-0.5">Lens Priority</label>
                          <p className="text-[10px] text-zinc-400 mb-2">Which rows the AI focuses on first in Interview Mode</p>
                          <div className="flex rounded-lg border border-zinc-200 overflow-hidden text-[10px] font-semibold">
                            {(['balanced', 'customer', 'operations', 'engineering'] as LensPriority[]).map((v) => (
                              <button key={v} disabled={!journeyMapRecord}
                                onClick={() => void handleSmartAiSettingChange({lens_priority: v})}
                                className={`flex-1 py-1.5 transition-colors ${smartAiSettings.lens_priority === v ? 'bg-zinc-900 text-white' : 'text-zinc-500 hover:bg-zinc-50'} disabled:opacity-40`}
                              >{v.charAt(0).toUpperCase() + v.slice(1)}</button>
                            ))}
                          </div>
                        </div>

                        {/* Toggle settings */}
                        {(
                          [
                            {key: 'emotional_mapping',        label: 'Emotional Mapping',        desc: 'Always probe for customer emotional state at each touchpoint'},
                            {key: 'business_impact_framing',  label: 'Business Impact Framing',  desc: 'Frame every pain point with frequency, severity and business consequence'},
                            {key: 'auto_confirm_writes',      label: 'Auto-Confirm AI Writes',   desc: 'AI-written cells land as Confirmed (not Draft)'},
                            {key: 'show_reasoning',           label: 'Show AI Reasoning',        desc: "Show the AI's thinking process beneath each message"},
                          ] as {key: keyof SmartAiSettings; label: string; desc: string}[]
                        ).map(({key, label, desc}) => (
                          <div key={key} className="flex items-start justify-between gap-3">
                            <div className="flex-1 min-w-0">
                              <p className="text-[10px] font-semibold text-zinc-700">{label}</p>
                              <p className="text-[10px] text-zinc-400 leading-snug mt-0.5">{desc}</p>
                            </div>
                            <button
                              disabled={!journeyMapRecord}
                              onClick={() => void handleSmartAiSettingChange({[key]: !smartAiSettings[key]})}
                              className={`shrink-0 mt-0.5 w-8 h-4 rounded-full transition-colors relative ${smartAiSettings[key] ? 'bg-zinc-900' : 'bg-zinc-200'} disabled:opacity-40`}
                            >
                              <span className={`absolute top-0.5 w-3 h-3 rounded-full bg-white shadow transition-transform ${smartAiSettings[key] ? 'translate-x-4' : 'translate-x-0.5'}`} />
                            </button>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Session Picker Dropdown */}
                  {isSessionPickerOpen && (
                    <div className="border-t border-zinc-200 bg-white max-h-64 overflow-y-auto">
                      <div className="p-2">
                        <button
                          type="button"
                          onClick={() => void handleCreateSession()}
                          disabled={isLoadingSessions}
                          className="w-full flex items-center gap-2 px-3 py-2 rounded-md text-xs font-medium text-zinc-600 hover:bg-zinc-50 transition-colors disabled:opacity-50"
                        >
                          <Plus className="w-3.5 h-3.5" />
                          New Session
                        </button>
                      </div>
                      <div className="border-t border-zinc-100">
                        {isLoadingSessions && conversationList.length === 0 && (
                          <div className="px-4 py-3 text-[10px] text-zinc-400 text-center">Loading sessions…</div>
                        )}
                        {!isLoadingSessions && conversationList.length === 0 && (
                          <div className="px-4 py-3 text-[10px] text-zinc-400 text-center">No sessions yet</div>
                        )}
                        {conversationList.map((item) => (
                          <div
                            key={item.id}
                            className={`group flex items-center gap-2 px-3 py-2 hover:bg-zinc-50 transition-colors ${conversationRecord?.id === item.id ? 'bg-zinc-100' : ''}`}
                          >
                            {isRenamingSession === item.id ? (
                              <form
                                className="flex-1 flex items-center gap-1"
                                onSubmit={(e) => { e.preventDefault(); void handleRenameSession(item.id, renameText); }}
                              >
                                <input
                                  autoFocus
                                  value={renameText}
                                  onChange={(e) => setRenameText(e.target.value)}
                                  onBlur={() => setIsRenamingSession(null)}
                                  className="flex-1 text-xs border border-zinc-300 rounded px-2 py-1 focus:outline-none focus:ring-1 focus:ring-zinc-400"
                                />
                                <button type="submit" className="p-1 text-emerald-600 hover:bg-emerald-50 rounded">
                                  <Check className="w-3 h-3" />
                                </button>
                              </form>
                            ) : confirmDeleteId === item.id ? (
                              <div className="flex-1 flex items-center justify-between">
                                <span className="text-[10px] text-rose-600 font-medium">Delete this session?</span>
                                <div className="flex items-center gap-1">
                                  <button
                                    type="button"
                                    onClick={() => void handleDeleteSession(item.id)}
                                    className="px-2 py-0.5 text-[10px] font-medium text-white bg-rose-500 rounded hover:bg-rose-600"
                                  >
                                    Yes
                                  </button>
                                  <button
                                    type="button"
                                    onClick={() => setConfirmDeleteId(null)}
                                    className="px-2 py-0.5 text-[10px] font-medium text-zinc-500 bg-zinc-100 rounded hover:bg-zinc-200"
                                  >
                                    No
                                  </button>
                                </div>
                              </div>
                            ) : (
                              <>
                                <button
                                  type="button"
                                  onClick={() => void handleSwitchSession(item.id)}
                                  className="flex-1 text-left"
                                >
                                  <div className="text-xs font-medium text-zinc-700 truncate">{item.title ?? 'Untitled'}</div>
                                  <div className="text-[9px] text-zinc-400 mt-0.5">
                                    {item.mode ?? 'interview'} · {item.message_count} msg{item.message_count !== 1 ? 's' : ''}
                                  </div>
                                </button>
                                <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                                  <button
                                    type="button"
                                    onClick={() => { setIsRenamingSession(item.id); setRenameText(item.title ?? ''); }}
                                    className="p-1 text-zinc-400 hover:text-zinc-600 hover:bg-zinc-100 rounded"
                                  >
                                    <Edit2 className="w-3 h-3" />
                                  </button>
                                  <button
                                    type="button"
                                    onClick={() => setConfirmDeleteId(item.id)}
                                    className="p-1 text-zinc-400 hover:text-rose-500 hover:bg-rose-50 rounded"
                                  >
                                    <Trash2 className="w-3 h-3" />
                                  </button>
                                </div>
                              </>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>

                <div className="flex-1 overflow-y-auto p-6 space-y-4 bg-white">
                  {messages.map((msg) => (
                    <div key={msg.id} className="space-y-1 group">
                      <div className={`flex items-start gap-1 ${msg.role === 'ai' ? 'justify-start' : 'justify-end'}`}>
                        {/* Delete button — left side for expert messages */}
                        {msg.role !== 'ai' && (
                          <button
                            type="button"
                            onClick={() => void handleDeleteMessage(msg.id)}
                            className="opacity-0 group-hover:opacity-100 transition-opacity self-center p-1 text-zinc-300 hover:text-rose-400 hover:bg-rose-50 rounded shrink-0"
                            title="Delete message"
                          >
                            <Trash2 className="w-3 h-3" />
                          </button>
                        )}
                        <div className={`max-w-[85%] flex gap-2 ${msg.role === 'ai' ? '' : 'flex-row-reverse'}`}>
                          <div className={`w-6 h-6 rounded-full shrink-0 flex items-center justify-center text-[8px] font-bold ${msg.role === 'ai' ? 'bg-zinc-900 text-white' : 'bg-zinc-200 text-zinc-600'}`}>
                            {msg.role === 'ai' ? 'AI' : 'EX'}
                          </div>
                          <div className={`p-3 rounded-xl text-xs leading-relaxed ${msg.role === 'ai' ? 'bg-zinc-100 text-zinc-800' : 'bg-zinc-900 text-white'}`}>
                            {msg.content}
                          </div>
                        </div>
                        {/* Delete button — right side for AI messages */}
                        {msg.role === 'ai' && (
                          <button
                            type="button"
                            onClick={() => void handleDeleteMessage(msg.id)}
                            className="opacity-0 group-hover:opacity-100 transition-opacity self-center p-1 text-zinc-300 hover:text-rose-400 hover:bg-rose-50 rounded shrink-0"
                            title="Delete message"
                          >
                            <Trash2 className="w-3 h-3" />
                          </button>
                        )}
                      </div>
                      {/* Transparency layers 1-3 */}
                      {msg.role === 'ai' && msg.activity && (
                        <ActivityPanel
                          msgId={msg.id}
                          activity={msg.activity}
                          isTraceExpanded={
                            expandedPanels[msg.id] === 'trace' ||
                            expandedPanels[msg.id] === 'reasoning'
                          }
                          isReasoningExpanded={expandedPanels[msg.id] === 'reasoning'}
                          onToggleTrace={() =>
                            setExpandedPanels((prev) => ({
                              ...prev,
                              [msg.id]:
                                prev[msg.id] === 'trace' || prev[msg.id] === 'reasoning'
                                  ? null
                                  : 'trace',
                            }))
                          }
                          onToggleReasoning={() =>
                            setExpandedPanels((prev) => ({
                              ...prev,
                              [msg.id]: prev[msg.id] === 'reasoning' ? 'trace' : 'reasoning',
                            }))
                          }
                          showReasoning={smartAiSettings.show_reasoning ?? true}
                        />
                      )}
                      {/* Layer 4: Debug panel — only when ?debug=1 and turn_id available */}
                      {isDebugMode && msg.role === 'ai' && msg.activity?.turnId && journeyMapRecord && (
                        <DebugPanel
                          journeyMapId={journeyMapRecord.id}
                          turnId={msg.activity.turnId}
                          stepLimitWarning={msg.activity.stepLimitWarning ?? false}
                        />
                      )}
                    </div>
                  ))}
                  {/* Thinking indicator — shown while the AI is processing */}
                  {isSendingMessage && (
                    <div className="flex items-start gap-2">
                      <div className="w-6 h-6 rounded-full shrink-0 flex items-center justify-center text-[8px] font-bold bg-zinc-900 text-white">
                        AI
                      </div>
                      <div className="p-3 rounded-xl bg-zinc-100 flex gap-1 items-center">
                        <span className="w-1.5 h-1.5 bg-zinc-400 rounded-full animate-bounce [animation-delay:0ms]" />
                        <span className="w-1.5 h-1.5 bg-zinc-400 rounded-full animate-bounce [animation-delay:150ms]" />
                        <span className="w-1.5 h-1.5 bg-zinc-400 rounded-full animate-bounce [animation-delay:300ms]" />
                      </div>
                    </div>
                  )}
                  {lastUpdateSummaries.length > 0 && (
                    <div className="mx-2 p-3 rounded-lg bg-zinc-50 border border-zinc-200 space-y-1.5">
                      <div className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider">Cell updates</div>
                      {lastUpdateSummaries.map((summary, index) => (
                        <div key={index} className="flex items-center gap-2 text-xs">
                          <span className={`inline-block w-1.5 h-1.5 rounded-full shrink-0 ${summary.status === 'applied' ? 'bg-emerald-500' : 'bg-amber-500'}`} />
                          <span className="font-medium text-zinc-700">{summary.reference}</span>
                          <span className={`text-[10px] ${summary.status === 'applied' ? 'text-emerald-600' : 'text-amber-600'}`}>
                            {summary.status === 'applied' ? 'applied' : `skipped${summary.reason ? ` · ${summary.reason}` : ''}`}
                          </span>
                        </div>
                      ))}
                    </div>
                  )}
                  <div ref={chatEndRef} />
                </div>

                <div className="p-4 border-t border-zinc-100 bg-zinc-50/80">
                  <div className="space-y-3">
                    {suggestedPrompts.length > 0 && (
                      <div className="flex flex-wrap gap-1.5">
                        {suggestedPrompts.map(chip => (
                          <button key={chip} onClick={() => setInputText(chip)} className="px-2 py-1 bg-white border border-zinc-200 rounded-full text-[10px] text-zinc-500 hover:border-zinc-400 transition-colors">
                            {chip}
                          </button>
                        ))}
                      </div>
                    )}
                    
                    <div className="bg-white border border-zinc-200 rounded-xl overflow-hidden focus-within:ring-2 focus-within:ring-zinc-900/5 focus-within:border-zinc-400 transition-all shadow-sm">
                      {/* Context Bar */}
                      <div className="px-3 py-2 bg-zinc-50/50 border-b border-zinc-100 flex items-center gap-3 overflow-x-auto no-scrollbar">
                        <div className="flex items-center gap-2 shrink-0">
                          <AtSign className="w-3.5 h-3.5 text-zinc-400 hover:text-zinc-600 cursor-pointer" />
                          <Box className="w-3.5 h-3.5 text-zinc-400 hover:text-zinc-600 cursor-pointer" />
                          <Bookmark className="w-3.5 h-3.5 text-zinc-400 hover:text-zinc-600 cursor-pointer" />
                          <MousePointer2 className="w-3.5 h-3.5 text-zinc-400 hover:text-zinc-600 cursor-pointer" />
                        </div>
                        <div className="h-3 w-px bg-zinc-200 shrink-0" />
                        <div className="flex items-center gap-1.5 px-2 py-0.5 bg-zinc-100 rounded-md shrink-0 border border-zinc-200">
                          <Folder className="w-3 h-3 text-zinc-500" />
                          <span className="text-[9px] font-bold text-zinc-600 uppercase tracking-tighter">emgram1010</span>
                        </div>
                        {selectedCellContext && (
                          <div className="flex items-center gap-1.5 px-2 py-0.5 bg-blue-50 rounded-md shrink-0 border border-blue-200">
                            <LayoutGrid className="w-3 h-3 text-blue-600" />
                            <span className="text-[9px] font-bold text-blue-700 uppercase tracking-tighter">{selectedCellContext.reference}</span>
                            {selectedCellContext.shorthand && (
                              <span className="text-[9px] font-semibold text-blue-500">{selectedCellContext.shorthand}</span>
                            )}
                          </div>
                        )}
                      </div>

                      <div className="px-3 pt-3 flex items-start gap-2">
                        {isQuestionMode && (
                          <div className="flex items-center gap-1.5 px-2 py-1 bg-blue-600 text-white rounded-md shrink-0 shadow-sm">
                            <MessageSquare className="w-3 h-3" />
                            <span className="text-[10px] font-bold whitespace-nowrap">Ask a Question</span>
                          </div>
                        )}
                        <textarea 
                          value={inputText}
                          onChange={(e) => setInputText(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' && !e.shiftKey) {
                              e.preventDefault();
                              void handleSendMessage();
                            }
                          }}
                          placeholder="Type your message..."
                          rows={2}
                          disabled={isSendingMessage}
                          className="w-full bg-transparent border-none p-0 text-xs focus:ring-0 resize-none min-h-[40px] placeholder:text-zinc-400"
                        />
                      </div>
                      
                      <div className="px-3 py-2 flex items-center justify-between bg-zinc-50/50 border-t border-zinc-100">
                        <div className="flex items-center gap-2">
                          <button 
                            onClick={() => setIsQuestionMode(!isQuestionMode)}
                            className={`p-1.5 rounded-md transition-all ${isQuestionMode ? 'bg-blue-100 text-blue-600' : 'hover:bg-zinc-200 text-zinc-400'}`}
                          >
                            <MessageSquare className="w-3.5 h-3.5" />
                          </button>
                        </div>
                        
                        <div className="flex items-center gap-1.5">
                          <button 
                            onClick={() => void handleSendMessage()}
                            disabled={!inputText.trim() || isSendingMessage}
                            className="p-1.5 bg-zinc-900 text-white rounded-lg hover:bg-zinc-800 disabled:opacity-30 transition-all shadow-sm"
                          >
                            <Send className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
                  </motion.div>
                )}
              </AnimatePresence>

              {/* Floating AI Toggle Button */}
              <AnimatePresence>
                {!isChatOpen && !selectedCellId && (
                  <motion.button 
                    initial={{ scale: 0, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    exit={{ scale: 0, opacity: 0 }}
                    onClick={() => setIsChatOpen(true)}
                    className="absolute bottom-6 right-6 w-14 h-14 rounded-full shadow-xl flex items-center justify-center transition-all z-50 bg-zinc-900 text-white hover:scale-110"
                  >
                    <MessageSquare className="w-6 h-6" />
                    <span className="absolute -top-1 -right-1 w-4 h-4 bg-amber-500 border-2 border-white rounded-full animate-pulse" />
                  </motion.button>
                )}
              </AnimatePresence>

              {/* Detail Panel (Docked) */}
              <AnimatePresence>
                {selectedCell && (
                  <motion.div 
                    initial={{ x: '100%' }}
                    animate={{ x: 0 }}
                    exit={{ x: '100%' }}
                    transition={{ type: 'spring', damping: 25, stiffness: 200 }}
                    className="absolute right-0 top-0 bottom-0 w-80 bg-white border-l border-zinc-200 shadow-2xl z-30 flex flex-col"
                  >
                <div className="h-12 border-b border-zinc-200 flex items-center justify-between px-4 shrink-0">
                  <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">Cell Detail</span>
                  <button onClick={handleCloseSelectedCell} disabled={isXanoSyncing} className="p-1 hover:bg-zinc-100 rounded text-zinc-400 disabled:cursor-not-allowed disabled:opacity-40">
                    <X className="w-4 h-4" />
                  </button>
                </div>
                
                <div className="flex-1 overflow-y-auto p-6 space-y-6">
                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Context</label>
                    <div className="text-xs font-semibold text-zinc-900">{selectedCellReference ?? `${selectedStageLabel} • ${selectedLensLabel}`}</div>
                    {selectedCellShorthand && (
                      <div className="mt-1 text-[10px] font-medium uppercase tracking-wider text-zinc-400">{selectedCellShorthand}</div>
                    )}
                  </div>

                  {/* Actor context — shown when the parent lens has an actor type */}
                  {(() => {
                    const cellLens = selectedCell ? lenses.find((l) => l.id === selectedCell.lensId) : null;
                    if (!cellLens?.actorType) return null;
                    return (
                      <div>
                        <div className="flex items-center justify-between mb-2">
                          <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider">Actor</label>
                          <button
                            type="button"
                            onClick={() => handleEditActorOpen(cellLens)}
                            className="text-[10px] text-zinc-400 hover:text-zinc-800 font-medium transition-colors"
                          >
                            Edit
                          </button>
                        </div>
                        <div className="p-3 bg-zinc-50 border border-zinc-200 rounded space-y-1.5">
                          <div className="flex items-center gap-2">
                            <span className="text-xs font-semibold text-zinc-900">{cellLens.label}</span>
                            <span className="text-[9px] font-bold uppercase tracking-wider bg-zinc-200 text-zinc-600 px-1.5 py-0.5 rounded">
                              {cellLens.actorType.replace('_', ' ')}
                            </span>
                          </div>
                          {cellLens.personaDescription && (
                            <p className="text-[11px] text-zinc-500 leading-snug">{cellLens.personaDescription}</p>
                          )}
                          {cellLens.primaryGoal && (
                            <p className="text-[11px] text-zinc-600 leading-snug">
                              <span className="font-medium">Goal:</span> {cellLens.primaryGoal}
                            </p>
                          )}
                          {cellLens.standingConstraints && (
                            <p className="text-[11px] text-zinc-600 leading-snug">
                              <span className="font-medium">Constraints:</span> {cellLens.standingConstraints}
                            </p>
                          )}
                        </div>
                      </div>
                    );
                  })()}

                  {/* Metrics cell panel — structured scorecard, replaces generic field list */}
                  {METRICS_ACTOR_ENABLED && selectedCellLens?.actorType === 'metrics' && selectedCell.actorFields && isMetricsActorFields(selectedCell.actorFields) && (() => {
                    const mf = selectedCell.actorFields as MetricsActorFields;
                    const healthColor = metricsStageHealth != null ? getMetricColor('stage_health', metricsStageHealth) : null;
                    const healthDotColors: Record<string, string> = {green: '#22c55e', yellow: '#f59e0b', red: '#ef4444'};
                    const dot = (key: string, val: number | null) => (
                      <span style={{display: 'inline-block', width: 8, height: 8, borderRadius: '50%', background: healthDotColors[getMetricColor(key, val)], flexShrink: 0}} />
                    );
                    const numericRows: Array<[keyof MetricsActorFields, string, string, string]> = [
                      ['csat_score',          'CSAT Score',           '1–10',    'healthy ≥ 8.0'],
                      ['completion_rate',     'Completion Rate',      '%',       'healthy ≥ 90%'],
                      ['drop_off_rate',       'Drop-off Rate',        '%',       'healthy ≤ 10%'],
                      ['error_rate',          'Error Rate',           '%',       'healthy ≤ 5%'],
                      ['sla_compliance_rate', 'SLA Compliance',       '%',       'healthy ≥ 90%'],
                      ['avg_time_to_complete','Avg Time (min)',        'min',     ''],
                    ];
                    return (
                      <div className="space-y-3">
                        {/* AI Infer button */}
                        <button
                          type="button"
                          disabled={true}
                          title="Available after Epic C — AI integration"
                          className="w-full flex items-center justify-center gap-2 py-2 rounded border border-dashed border-zinc-300 text-[10px] font-semibold text-zinc-400 cursor-not-allowed"
                        >
                          <Sparkles className="w-3 h-3" /> AI Infer from Actors
                        </button>

                        {/* Stage health headline */}
                        <div className="p-3 rounded-lg border border-zinc-200 bg-zinc-50 flex items-center justify-between">
                          <div>
                            <div className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider mb-0.5">Stage Health</div>
                            <div className="flex items-center gap-1.5">
                              <span className="text-2xl font-bold text-zinc-900">{metricsStageHealth != null ? metricsStageHealth.toFixed(1) : '—'}</span>
                              <span className="text-xs text-zinc-400">/10</span>
                              {healthColor && <span style={{display: 'inline-block', width: 10, height: 10, borderRadius: '50%', background: healthDotColors[healthColor]}} />}
                            </div>
                            <div className="text-[9px] text-zinc-400 mt-0.5">Auto-calculated · override via Stage Health field</div>
                          </div>
                        </div>

                        {/* Numeric metric rows */}
                        <div className="space-y-2">
                          {numericRows.map(([key, label, unit, benchmark]) => {
                            const val = parseMetricValue(mf[key]);
                            return (
                              <div key={key} className="flex items-center gap-2">
                                <div className="flex-1 min-w-0">
                                  <div className="text-[10px] font-medium text-zinc-500">{label}</div>
                                  {benchmark && <div className="text-[9px] text-zinc-300">{benchmark}</div>}
                                </div>
                                <div className="flex items-center gap-1.5 shrink-0">
                                  <input
                                    type="number"
                                    value={val ?? ''}
                                    onChange={(e) => updateCellMetricField(selectedCell.id, key, e.target.value)}
                                    disabled={selectedCell.isLocked}
                                    placeholder="—"
                                    className="w-16 text-right p-1 bg-white border border-zinc-200 rounded text-xs font-semibold focus:outline-none focus:ring-1 focus:ring-zinc-300 disabled:opacity-50"
                                  />
                                  <span className="text-[9px] text-zinc-400 w-5">{unit}</span>
                                  {dot(key, val)}
                                </div>
                              </div>
                            );
                          })}
                        </div>

                        {/* Volume / Frequency (text) */}
                        <div>
                          <label className="text-[10px] font-medium text-zinc-500 block mb-1">Volume / Frequency</label>
                          <input
                            type="text"
                            value={mf.volume_frequency ?? ''}
                            onChange={(e) => updateCellActorField(selectedCell.id, 'volume_frequency', e.target.value)}
                            disabled={selectedCell.isLocked}
                            placeholder="e.g. ~300 interactions/day"
                            className="w-full p-2 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-300 disabled:opacity-50"
                          />
                        </div>

                        {/* Explicit stage_health override */}
                        <div>
                          <label className="text-[10px] font-medium text-zinc-500 block mb-1">Stage Health Override</label>
                          <input
                            type="number"
                            value={parseMetricValue(mf.stage_health) ?? ''}
                            onChange={(e) => updateCellMetricField(selectedCell.id, 'stage_health', e.target.value)}
                            disabled={selectedCell.isLocked}
                            placeholder="Leave blank to auto-calculate"
                            className="w-full p-2 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-300 disabled:opacity-50"
                          />
                        </div>
                      </div>
                    );
                  })()}

                  {/* Structured actor cell fields — rendered when the parent lens has a defined template (non-metrics) */}
                  {(() => {
                    const cellLensForFields = selectedCellLens;
                    if (cellLensForFields?.actorType === 'metrics') return null;
                    const template = cellLensForFields?.actorType
                      ? ACTOR_TEMPLATES.find((t) => t.actorType === cellLensForFields.actorType)
                      : null;
                    if (!template || template.cellFields.length === 0 || !selectedCell.actorFields) return null;
                    return (
                      <div className="space-y-3">
                        <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">
                          {template.label} Fields
                        </label>
                        {template.cellFields.map((field) => {
                          const rawVal = (selectedCell.actorFields as Record<string, string | null> | null | undefined)?.[field.key];
                          const fieldValue = rawVal ?? '';
                          return (
                            <div key={field.key}>
                              <label className="text-[10px] font-medium text-zinc-500 block mb-1">{field.label}</label>
                              <div className="relative">
                                <textarea
                                  value={fieldValue}
                                  onChange={(e) => updateCellActorField(selectedCell.id, field.key, e.target.value)}
                                  disabled={selectedCell.isLocked}
                                  placeholder={field.placeholder}
                                  rows={2}
                                  className={`w-full p-2.5 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-300 resize-none ${selectedCell.isLocked ? 'opacity-60 cursor-not-allowed' : ''}`}
                                />
                                {selectedCell.isLocked && (
                                  <div className="absolute inset-0 bg-zinc-50/20 backdrop-blur-[1px] pointer-events-none" />
                                )}
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    );
                  })()}

                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">
                      {(() => {
                        const cellLensForNotes = selectedCell ? lenses.find((l) => l.id === selectedCell.lensId) : null;
                        return cellLensForNotes?.actorType ? 'Notes' : 'Content';
                      })()}
                    </label>
                    <div className="relative">
                      <textarea
                        value={selectedCell.content}
                        onChange={(e) => updateCellContent(selectedCell.id, e.target.value)}
                        disabled={selectedCell.isLocked}
                        placeholder="Enter expert knowledge..."
                        className={`w-full h-32 p-3 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-300 resize-none ${selectedCell.isLocked ? 'opacity-60 cursor-not-allowed' : ''}`}
                      />
                      {selectedCell.isLocked && (
                        <div className="absolute inset-0 bg-zinc-50/20 backdrop-blur-[1px] flex items-center justify-center pointer-events-none">
                          <Lock className="w-6 h-6 text-zinc-300" />
                        </div>
                      )}
                    </div>
                  </div>

                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Cell Controls</label>
                    <button 
                      onClick={() => toggleCellLock(selectedCell.id)}
                      disabled={isXanoSyncing}
                      className={`w-full flex items-center justify-between p-3 rounded border transition-all ${selectedCell.isLocked ? 'bg-zinc-900 border-zinc-900 text-white' : 'bg-white border-zinc-200 text-zinc-700 hover:bg-zinc-50'}`}
                    >
                      <div className="flex items-center gap-3">
                        {selectedCell.isLocked ? <Lock className="w-4 h-4" /> : <Unlock className="w-4 h-4" />}
                        <span className="text-xs font-medium">{selectedCell.isLocked ? 'Cell Locked' : 'Cell Unlocked'}</span>
                      </div>
                      <div className={`text-[9px] font-bold uppercase tracking-wider ${selectedCell.isLocked ? 'text-zinc-400' : 'text-zinc-400'}`}>
                        {selectedCell.isLocked ? 'AI Cannot Edit' : 'AI Can Edit'}
                      </div>
                    </button>
                  </div>

                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Verification Status</label>
                    <div className="space-y-2">
                      {[
                        { id: 'confirmed', label: 'Expert Confirmed', icon: CheckCircle2, color: 'text-emerald-600', bg: 'bg-emerald-50' },
                        { id: 'draft', label: 'Draft Inference', icon: CircleDashed, color: 'text-amber-600', bg: 'bg-amber-50' },
                        { id: 'open', label: 'Open Question', icon: HelpCircle, color: 'text-zinc-500', bg: 'bg-zinc-100' },
                      ].map(status => (
                        <button 
                          key={status.id}
                          onClick={() => updateCellStatus(selectedCell.id, status.id as CellStatus)}
                          disabled={isXanoSyncing}
                          className={`
                            w-full flex items-center justify-between p-3 rounded border transition-all
                            ${selectedCell.status === status.id 
                              ? `border-${status.id === 'confirmed' ? 'emerald' : status.id === 'draft' ? 'amber' : 'zinc'}-200 ${status.bg}` 
                              : 'border-transparent hover:bg-zinc-50'}
                          `}
                        >
                          <div className="flex items-center gap-3">
                            <status.icon className={`w-4 h-4 ${status.color}`} />
                            <span className="text-xs font-medium text-zinc-700">{status.label}</span>
                          </div>
                          {selectedCell.status === status.id && <div className="w-1.5 h-1.5 rounded-full bg-zinc-900" />}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>

                {/* ── Link to Map (only when inside an architecture) ──────── */}
                {architectureId && (
                  <div className="px-4 pb-4 space-y-3">
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Link to Map</label>

                    {/* Link type */}
                    <div className="flex rounded-lg border border-zinc-200 overflow-hidden">
                      {(['exception', 'anti_journey', 'sub_journey'] as JourneyLinkType[]).map((t) => {
                        const icons = { exception: '⚠', anti_journey: '↩', sub_journey: '⤵' };
                        const labels = { exception: 'Exception', anti_journey: 'Anti-Journey', sub_journey: 'Sub-Journey' };
                        return (
                          <button key={t} onClick={() => { setCellLinkType(t); setCellLinkSuccess(false); }}
                            className={`flex-1 py-1.5 text-[10px] font-medium transition-colors ${cellLinkType === t ? 'bg-indigo-600 text-white' : 'bg-white text-zinc-500 hover:bg-zinc-50'}`}>
                            {icons[t]} {labels[t]}
                          </button>
                        );
                      })}
                    </div>

                    {/* Target map dropdown */}
                    <select
                      value={String(cellLinkTargetId)}
                      onChange={(e) => { setCellLinkTargetId(e.target.value === 'new' ? 'new' : Number(e.target.value)); setCellLinkSuccess(false); }}
                      className="w-full px-2.5 py-2 text-xs bg-white border border-zinc-200 rounded-lg text-zinc-700 focus:outline-none focus:ring-2 focus:ring-indigo-300">
                      <option value="">Select target map…</option>
                      {siblingMaps.map((m) => <option key={m.id} value={m.id}>{m.title}</option>)}
                      <option value="new">+ Create new map…</option>
                    </select>

                    {/* New map title (shown when "Create new map" is selected) */}
                    {cellLinkTargetId === 'new' && (
                      <input
                        value={cellLinkNewTitle}
                        onChange={(e) => setCellLinkNewTitle(e.target.value)}
                        placeholder="e.g. Anti-Journey — Driver Can't Find Address"
                        className="w-full px-2.5 py-2 text-xs bg-white border border-zinc-200 rounded-lg text-zinc-700 focus:outline-none focus:ring-2 focus:ring-indigo-300"
                      />
                    )}

                    {/* Error */}
                    {cellLinkError && (
                      <p className="text-[11px] text-rose-600 bg-rose-50 border border-rose-200 rounded-lg px-3 py-1.5">{cellLinkError}</p>
                    )}

                    {/* Submit */}
                    {cellLinkSuccess ? (
                      <div className="flex items-center gap-2 text-xs text-emerald-600 font-medium py-1">
                        <span>✓</span> Link created
                      </div>
                    ) : (
                      <button
                        onClick={() => void handleCreateCellLink()}
                        disabled={!cellLinkTargetId || cellLinkCreating}
                        className="w-full py-2 bg-indigo-600 text-white rounded-lg text-xs font-semibold hover:bg-indigo-700 disabled:opacity-50 transition-colors flex items-center justify-center gap-2">
                        {cellLinkCreating ? (
                          <><span className="animate-spin">↻</span> Creating…</>
                        ) : (
                          <>→ {cellLinkTargetId === 'new' ? 'Create Map & Link' : 'Add Link'}</>
                        )}
                      </button>
                    )}
                  </div>
                )}

                <div className="p-4 border-t border-zinc-100 bg-zinc-50">
                  <button
                    onClick={handleCloseSelectedCell}
                    disabled={isXanoSyncing}
                    className="w-full py-2 bg-zinc-900 text-white rounded text-xs font-semibold hover:bg-zinc-800 transition-colors disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Save & Close
                  </button>
                </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </section>
          </>
        )}
      </main>

      {/* Journey Health Widget (US-MET-12/14/19) — right sidebar, always mounted, slides in/out */}
      {METRICS_ACTOR_ENABLED && journeyMapRecord && (
        <JourneyHealthWidget
          journeyMapId={journeyMapRecord.id}
          scorecard={scorecard}
          baseline={scorecardBaseline}
          isOpen={widgetVisible}
          onClose={() => setWidgetVisible(false)}
          onAiNudge={(prompt) => {
            setIsChatMode(true);
            setIsChatOpen(true);
            setInputText(prompt);
          }}
        />
      )}

      {/* Actor Setup Wizard */}
      <ActorSetupWizard
        isOpen={showActorWizard}
        onClose={() => { setShowActorWizard(false); setActorWizardEditTarget(null); }}
        onConfirm={handleActorWizardConfirm}
        existingLens={actorWizardEditTarget}
      />

      {/* Footer / Legend */}
      <footer className="h-8 border-t border-zinc-200 bg-white flex items-center justify-between px-6 shrink-0 text-[10px] text-zinc-400 font-medium">
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-1.5">
            <div className="w-2 h-2 rounded-full bg-emerald-500" />
            Confirmed
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-2 h-2 rounded-full bg-amber-500" />
            AI Draft
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-2 h-2 rounded-full bg-zinc-200" />
            Pending
          </div>
        </div>
        <div>
          Last updated: Today at 04:24 PM • Version 1.0.4
        </div>
      </footer>
    </div>
  );
}
