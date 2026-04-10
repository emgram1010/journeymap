import React, { useState, useRef, useEffect, useCallback } from 'react';
import { 
  Send, 
  Play, 
  RotateCcw, 
  CheckCircle2, 
  CircleDashed, 
  HelpCircle, 
  Info, 
  ChevronRight,
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
  Folder
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { Message, MatrixCell, CellStatus, Stage, Lens } from './types';
import {cloneCellSnapshot, hasPendingCellChanges, resolveCellPersistenceBaseline} from './cellPersistence';
import { STAGES as INITIAL_STAGES, LENSES as INITIAL_LENSES } from './constants';
import JourneyMatrixTabulator from './JourneyMatrixTabulator';
import {mergePersistedCellUpdates} from './persistedCellUpdates';
import {buildCellReferenceLabel, buildCellShorthand, buildCellUpdateSummaries, buildSelectedCellContext} from './cellIdentifiers';
import type {CellUpdateSummary} from './cellIdentifiers';
import {
  addJourneyLens,
  addJourneyStage,
  createDraftJourneyMap,
  listJourneyMaps,
  loadJourneyMapBundle,
  removeJourneyLens,
  removeJourneyStage,
  renameJourneyLens,
  renameJourneyStage,
  sendJourneyMapMessage,
  updateJourneyCell,
  type XanoAgentConversation,
  XanoJourneyMap,
  type HydratedJourneyMapBundle,
} from './xano';

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

export default function App() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [inputText, setInputText] = useState('');
  const [cells, setCells] = useState<MatrixCell[]>([]);
  const [stages, setStages] = useState<Stage[]>([]);
  const [lenses, setLenses] = useState<Lens[]>([]);
  const [journeyMapRecord, setJourneyMapRecord] = useState<XanoJourneyMap | null>(null);
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
  const [isQuestionMode, setIsQuestionMode] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  
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
      return;
    }

    setJourneyMapRecord(bundle.journeyMap);
    setConversationRecord(bundle.conversation);
    setMessages(bundle.messages);
    setIsChatMode(bundle.conversation?.mode === 'chat');

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

  useEffect(() => {
    void syncLatestJourneyMap();
  }, [syncLatestJourneyMap]);

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

  const showWorkspace = initialLoadState === 'ready';
  const isScaffoldFallback = Boolean(journeyMapRecord) && matrixSyncSource === 'map-only';
  const selectedCell = cells.find((cell) => cell.id === selectedCellId) ?? null;
  const selectedStageLabel = selectedCell ? stages.find((stage) => stage.id === selectedCell.stageId)?.label ?? null : null;
  const selectedLensLabel = selectedCell ? lenses.find((lens) => lens.id === selectedCell.lensId)?.label ?? null : null;
  const selectedCellReference = buildCellReferenceLabel(selectedStageLabel, selectedLensLabel);
  const selectedCellShorthand = buildCellShorthand(selectedCell, stages, lenses);
  const selectedCellContext = buildSelectedCellContext({cell: selectedCell, stages, lenses, journeyMapId: journeyMapRecord?.id});

  const handleSendMessage = useCallback(async () => {
    const messageText = inputText.trim();
    if (!messageText) {
      return;
    }

    if (!journeyMapRecord) {
      setXanoError('Create or load a journey map before sending a message.');
      return;
    }

    const assistantReply = isChatMode
      ? 'Understood. This thread is saved in chat mode, so I will keep the exchange conversational without proposing matrix edits yet.'
      : 'Got it. I saved this interview thread so we can resume later. What is the primary pain point they face during this initiation phase?';

    setIsSendingMessage(true);
    setXanoError(null);
    setInputText('');

    try {
      const persistedThread = await sendJourneyMapMessage({
        journeyMapId: journeyMapRecord.id,
        conversationId: conversationRecord?.id,
        content: messageText,
        mode: isChatMode ? 'chat' : 'interview',
        assistantReply,
        selectedCell: selectedCellContext,
      });

      setConversationRecord(persistedThread.conversation);
      setMessages(persistedThread.messages);
      setIsChatMode(persistedThread.conversation?.mode === 'chat');

      if (persistedThread.appliedUpdates.length > 0) {
        setCells((currentCells) => mergePersistedCellUpdates(currentCells, persistedThread.appliedUpdates, stages, lenses));
        setSelectedCellSnapshot((currentSnapshot) => {
          if (!currentSnapshot) {
            return currentSnapshot;
          }

          const [nextSnapshot] = mergePersistedCellUpdates([currentSnapshot], persistedThread.appliedUpdates, stages, lenses);
          return nextSnapshot ?? currentSnapshot;
        });
      }

      const summaries = buildCellUpdateSummaries(persistedThread.appliedUpdates, persistedThread.skippedUpdates);
      setLastUpdateSummaries(summaries);

      if (persistedThread.journeyMapUpdatedAt) {
        setJourneyMapRecord((currentJourneyMap) =>
          currentJourneyMap
            ? {
                ...currentJourneyMap,
                updated_at: persistedThread.journeyMapUpdatedAt ?? currentJourneyMap.updated_at,
                last_interaction_at: persistedThread.journeyMapUpdatedAt ?? currentJourneyMap.last_interaction_at,
              }
            : currentJourneyMap,
        );
      }
    } catch (error) {
      setInputText(messageText);
      setXanoError(error instanceof Error ? error.message : 'Unable to save conversation.');
    } finally {
      setIsSendingMessage(false);
    }
  }, [conversationRecord?.id, inputText, isChatMode, journeyMapRecord, selectedCellContext, lenses, stages]);

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
        };

        setCells((currentCells) => currentCells.map((entry) => (entry.id === cell.id ? nextCell : entry)));

        if (selectedCellId === cell.id) {
          setSelectedCellSnapshot(cloneCellSnapshot(nextCell));
        }

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
    [selectedCellId, selectedCellSnapshot],
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

  const addLens = async () => {
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
      await addJourneyLens({journeyMapId: journeyMapRecord.id});
      await refreshCurrentJourneyMap(journeyMapRecord);
    } catch (error) {
      setXanoError(getErrorMessage(error, 'Unable to add lens.'));
    } finally {
      setIsXanoSyncing(false);
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

  return (
    <div className="flex flex-col h-screen overflow-hidden bg-zinc-50 font-sans">
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
                    onClick={() => void addLens()}
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
                  />
                </div>
              </div>

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
                <div className="h-14 border-b border-zinc-200 flex items-center justify-between px-4 shrink-0 bg-zinc-50">
                  <div className="flex items-center gap-3">
                    <div className="flex flex-col">
                      <span className="text-[10px] font-bold text-zinc-900 uppercase tracking-widest leading-none">AI Interviewer</span>
                      <span className="text-[9px] text-zinc-400 font-medium mt-0.5">{isChatMode ? 'Chat Mode' : 'Interview Mode'}</span>
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
                    <button onClick={() => setIsChatOpen(false)} className="p-1.5 hover:bg-zinc-200 rounded text-zinc-400 transition-colors">
                      <X className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                <div className="flex-1 overflow-y-auto p-6 space-y-4 bg-white">
                  {messages.map((msg) => (
                    <div key={msg.id} className={`flex ${msg.role === 'ai' ? 'justify-start' : 'justify-end'}`}>
                      <div className={`max-w-[85%] flex gap-2 ${msg.role === 'ai' ? '' : 'flex-row-reverse'}`}>
                        <div className={`w-6 h-6 rounded-full shrink-0 flex items-center justify-center text-[8px] font-bold ${msg.role === 'ai' ? 'bg-zinc-900 text-white' : 'bg-zinc-200 text-zinc-600'}`}>
                          {msg.role === 'ai' ? 'AI' : 'EX'}
                        </div>
                        <div className={`p-3 rounded-xl text-xs leading-relaxed ${msg.role === 'ai' ? 'bg-zinc-100 text-zinc-800' : 'bg-zinc-900 text-white'}`}>
                          {msg.content}
                        </div>
                      </div>
                    </div>
                  ))}
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
                    <div className="flex flex-wrap gap-1.5">
                      {['Define Stage 2', 'List systems', 'Risks'].map(chip => (
                        <button key={chip} onClick={() => setInputText(chip)} className="px-2 py-1 bg-white border border-zinc-200 rounded-full text-[10px] text-zinc-500 hover:border-zinc-400 transition-colors">
                          {chip}
                        </button>
                      ))}
                    </div>
                    
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

                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Content</label>
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
