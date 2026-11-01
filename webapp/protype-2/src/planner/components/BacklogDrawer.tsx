import type React from 'react';
import { Fragment, useEffect, useState, useRef } from 'react';
import {
  Inbox,
  Plus,
  ArrowUpRight,
  GripVertical,
  GripHorizontal,
  CalendarPlus,
  Clock,
  User,
  Trash2,
  CornerDownRight,
  AlertTriangle,
  AlertCircle,
  Ban,
  ChevronDown,
  ChevronRight,
  X
} from 'lucide-react';
import { Task, Timeline, Agent, Workspace, AppSettings, Throughput } from '../types';
import { getWindowBounds, getWindowDays, formatShortDate, isDateOutOfWindow } from '../utils/dateUtils';
import { calculateWorkspaceCapacitySummary } from '../utils/agentUtils';
import { calculateWorkspaceCostSummary, formatMoney } from '../utils/costUtils';
import { listBacklogWork, type BacklogCard } from '../plannerApi';
import { formatMinutes } from '../varianceDisplay';
import { groupCardsByJob, classifyUnscheduleTarget } from '../boardModel';
import { EstimateBadge } from './EstimateBadge';
import JobPeekSheet from '../../exceptions/JobPeekSheet';

interface BacklogDrawerProps {
  backlogTasks: Task[];
  tasks: Task[];
  agents: Agent[];
  workspace: Workspace | null;
  timelinesInWorkspace: Timeline[];
  visibleDates: string[];
  showCapacityPanel: boolean;
  /** Plan view keeps a roster rail, so the panel stacks instead of sitting side-by-side. */
  compactMetrics?: boolean;
  settings: AppSettings;
  throughput: Throughput;
  onOpenSettings: () => void;
  activeModalTaskId?: string | null;
  isDraggingTaskFromTimeline: boolean;
  confirmationMessage?: string | null;
  onOpenTaskEditModal?: (taskId: string) => void;
  onSelectTask?: (taskId: string) => void;
  onAddToAgentDay: (taskId: string, agentId: string, day: string, targetIndex?: number) => void;
  onCreateBacklogTask: (title: string, duration: number, assignee?: string) => void;
  onDeleteTask: (taskId: string) => void;
  onDropTaskIntoBucket: (taskId: string) => void;
  /** QUE-1 (US-QUE-1-05/06) — a job slot dragged back onto this panel
      confirms first; see `classifyUnscheduleTarget`. */
  onRequestUnscheduleJobSlot: (workTaskId: number, jobTitle: string, dayLabel: string) => void;
  /** QUE-1 (US-QUE-1-02) — Unscheduled now owns the 559 fetch BOARD-1 gave
      the Jobs column: every role line with no day shows here automatically
      (Q-1, resolved 2026-10-30 — not behind a release step). */
  workspaceId: string | null;
  /** Bumped by PlannerApp after any board mutation; this panel refetches. */
  jobsReloadNonce: number;
  /** PlannerApp owns the schedule rule (ensure the day, 583, refresh). True = placed. */
  onPlaceCard: (card: BacklogCard, agentId: string, day: string) => Promise<boolean>;
}

export function BacklogDrawer({
  backlogTasks,
  tasks,
  agents,
  workspace,
  timelinesInWorkspace,
  visibleDates,
  showCapacityPanel,
  compactMetrics,
  settings,
  throughput,
  onOpenSettings,
  activeModalTaskId,
  isDraggingTaskFromTimeline,
  confirmationMessage,
  onOpenTaskEditModal,
  onSelectTask,
  onAddToAgentDay,
  onCreateBacklogTask,
  onDeleteTask,
  onDropTaskIntoBucket,
  onRequestUnscheduleJobSlot,
  workspaceId,
  jobsReloadNonce,
  onPlaceCard,
}: BacklogDrawerProps) {
  // QUE-1 (US-QUE-1-01): open by default — this is the queue a planner
  // works from, not an out-of-the-way bin. Still collapsible; the bar
  // stays visible and remains a drop target either way.
  const [isCollapsed, setIsCollapsed] = useState(false);
  const [isAdding, setIsAdding] = useState(false);
  const [newTitle, setNewTitle] = useState('');
  const [newDuration, setNewDuration] = useState(30);
  const [newAssignee, setNewAssignee] = useState('');

  // "Add to timeline..." dialog state: pick an agent + a day; the target
  // timeline is created on confirm if that agent has none on that day yet.
  const [keyboardModalTask, setKeyboardModalTask] = useState<Task | null>(null);
  const [targetAgentId, setTargetAgentId] = useState<string>(agents[0]?.id || '');
  const [targetDay, setTargetDay] = useState<string>(workspace?.planningWindowStart || '');
  const [targetPosition, setTargetPosition] = useState<'end' | 'start' | 'index'>('end');
  const [targetIndex, setTargetIndex] = useState<number>(0);
  // WIN-1 (US-WIN-1-02): the window's real days, not a fixed fortnight
  // from its start. A 3-day plan offered 14 choosable days here, 11 of
  // which the server now refuses.
  const modalDays = workspace
    ? getWindowDays(workspace.planningWindowStart, workspace.planningWindowEnd)
    : [];
  // min/max for every picker in this drawer that writes a planned date.
  const windowBounds = getWindowBounds(
    workspace?.planningWindowStart,
    workspace?.planningWindowEnd
  );

  // Drag over bucket state (for Section 3.E: Timeline -> Backlog)
  const [isDragOverBucket, setIsDragOverBucket] = useState(false);
  const dragCounterRef = useRef(0);

  // QUE-1 (US-QUE-1-02) — role lines with no day, moved here from the
  // Jobs column (BOARD-1). Same fetch, same shape, new home: 559's
  // "waiting for a day" list shows automatically (Q-1), never behind a
  // release step.
  const [waitingCards, setWaitingCards] = useState<BacklogCard[]>([]);
  const [isLoadingCards, setIsLoadingCards] = useState(false);
  const [cardsError, setCardsError] = useState<string | null>(null);
  // Founder, 2026-10-30: steps no longer expand inline under the row —
  // clicking the row selects it and its steps render in the panel on the
  // right, so the grid keeps its one-line row height either way.
  const [selectedCardKey, setSelectedCardKey] = useState<string | null>(null);
  const [placingFor, setPlacingFor] = useState<string | null>(null);
  const [placeAgentId, setPlaceAgentId] = useState<string>('');
  const [placeDay, setPlaceDay] = useState<string>('');
  const [isPlacingCard, setIsPlacingCard] = useState(false);
  // WIN-1 (US-WIN-1-02): a typed date can still land outside the picker's
  // min/max in some browsers, so Place is also refused here.
  const placeDayOutOfWindow = !!workspace && isDateOutOfWindow(
    placeDay,
    workspace.planningWindowStart,
    workspace.planningWindowEnd
  );
  // EXC chips open the shared read-only job view (D-2 of EXC-2), never a rebuild of it.
  const [peekId, setPeekId] = useState<number | null>(null);

  useEffect(() => {
    if (!workspaceId) {
      setWaitingCards([]);
      return;
    }
    let current = true;
    setIsLoadingCards(true);
    setCardsError(null);
    listBacklogWork(Number(workspaceId))
      .then((data) => {
        if (!current) return;
        setWaitingCards(data.backlog);
        // The selected card may have just been placed (and so left this
        // list) by the very mutation that triggered this refetch — drop a
        // selection that no longer points at anything real rather than
        // show stale steps beside an empty panel.
        setSelectedCardKey((prev) => (prev && data.backlog.some((c) => c.card_key === prev) ? prev : null));
      })
      .catch((err) => {
        if (current) setCardsError(err instanceof Error ? err.message : "Couldn't load the waiting work.");
      })
      .finally(() => {
        if (current) setIsLoadingCards(false);
      });
    return () => {
      current = false;
    };
  }, [workspaceId, jobsReloadNonce]);

  const cardGroups = groupCardsByJob(waitingCards);

  // The selected row's card + its job title, for the Stages panel.
  // `null` when nothing is selected or the selection no longer exists
  // (the fetch effect above already clears a stale `selectedCardKey`,
  // but this guards the one render in between).
  let selectedCard: BacklogCard | null = null;
  let selectedJobTitle = '';
  for (const group of cardGroups) {
    const found = group.cards.find((c) => c.card_key === selectedCardKey);
    if (found) {
      selectedCard = found;
      selectedJobTitle = group.jobTitle;
      break;
    }
  }

  const openPlaceForm = (cardKey: string) => {
    setPlacingFor((prev) => (prev === cardKey ? null : cardKey));
    setPlaceAgentId((prev) => prev || agents[0]?.id || '');
    // WIN-1 (US-WIN-1-02): never carry a day held over from another
    // plan's window into this one.
    setPlaceDay((prev) => {
      const fallback = workspace?.planningWindowStart || new Date().toISOString().slice(0, 10);
      if (!prev) return fallback;
      const stale = !!workspace && isDateOutOfWindow(
        prev,
        workspace.planningWindowStart,
        workspace.planningWindowEnd
      );
      return stale ? fallback : prev;
    });
  };

  const handlePlaceCard = async (card: BacklogCard) => {
    if (!placeAgentId || !placeDay || placeDayOutOfWindow) return;
    setIsPlacingCard(true);
    const ok = await onPlaceCard(card, placeAgentId, placeDay);
    setIsPlacingCard(false);
    if (ok) {
      setPlacingFor(null);
      setSelectedCardKey(null);
    }
  };

  const dayHasTimeline = (agentId: string, date: string) =>
    timelinesInWorkspace.some((t) => t.agentId === agentId && t.plannedDate === date);
  const agentName = (id: string) => agents.find((a) => a.id === id)?.name ?? '';

  // User-adjustable panel height (drag the grip above the list). Starts at
  // roughly the old 30vh cap; clamped so it never collapses to nothing or
  // swallows the whole board.
  const [backlogHeight, setBacklogHeight] = useState(() =>
    typeof window !== 'undefined' ? Math.round(window.innerHeight * 0.3) : 240
  );
  const isResizingRef = useRef(false);

  const handleResizeStart = (e: React.MouseEvent) => {
    e.preventDefault();
    isResizingRef.current = true;
    const startY = e.clientY;
    const startHeight = backlogHeight;
    const minHeight = 100;
    const maxHeight = Math.round(window.innerHeight * 0.7);

    const handleMouseMove = (moveEvent: MouseEvent) => {
      if (!isResizingRef.current) return;
      // Dragging the handle up (negative clientY delta) grows the panel,
      // since the panel is anchored to the bottom of the screen.
      const delta = startY - moveEvent.clientY;
      setBacklogHeight(Math.min(maxHeight, Math.max(minHeight, startHeight + delta)));
    };
    const handleMouseUp = () => {
      isResizingRef.current = false;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };

    document.body.style.cursor = 'row-resize';
    document.body.style.userSelect = 'none';
    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
  };

  // The seam between the drawer's two panes. The Unscheduled grid holds a
  // user-set width and the Stages panel takes whatever is left, so this one
  // handle moves the boundary: drag left and Stages expands, drag right and
  // the grid does. It was two adjacent handles, each sizing its own pane to
  // a fixed width, which left the right of a wide screen empty because
  // neither pane ever grew to fill the row (founder, 2026-10-31).
  const SEAM_CHROME_PX = 42; // row p-3 (24) + the handle (6) + its two gap-1.5 (12)
  const STAGES_MIN_PX = 320; // below ~280 a stage title clips to "1. Receive da…"
  const [unscheduledPaneWidth, setUnscheduledPaneWidth] = useState(480);
  const isResizingUnscheduledPaneRef = useRef(false);
  const paneRowRef = useRef<HTMLDivElement | null>(null);

  const handleUnscheduledPaneResizeStart = (e: React.MouseEvent) => {
    e.preventDefault();
    isResizingUnscheduledPaneRef.current = true;
    const startX = e.clientX;
    const startWidth = unscheduledPaneWidth;
    const minWidth = 280;
    // With Stages open the seam can only travel as far right as still leaves
    // the panel readable; with it closed there is no panel to crowd.
    const rowWidth = paneRowRef.current?.clientWidth ?? 0;
    const maxWidth = selectedCard && rowWidth > 0
      ? Math.max(minWidth, rowWidth - SEAM_CHROME_PX - STAGES_MIN_PX)
      : 960;

    const handleMouseMove = (moveEvent: MouseEvent) => {
      if (!isResizingUnscheduledPaneRef.current) return;
      // The handle sits on the pane's right edge; dragging it right grows it.
      const delta = moveEvent.clientX - startX;
      setUnscheduledPaneWidth(Math.min(maxWidth, Math.max(minWidth, startWidth + delta)));
    };
    const handleMouseUp = () => {
      isResizingUnscheduledPaneRef.current = false;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };

    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
  };

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault();
    if (newTitle.trim()) {
      onCreateBacklogTask(newTitle.trim(), Number(newDuration) || 30, newAssignee.trim() || undefined);
      setNewTitle('');
      setNewAssignee('');
      setIsAdding(false);
    }
  };

  const handleDragEnterBucketZone = (e: React.DragEvent) => {
    e.preventDefault();
    dragCounterRef.current += 1;
    if (!isDragOverBucket) {
      setIsDragOverBucket(true);
    }
  };

  const handleDragOverBucketZone = (e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    if (!isDragOverBucket) {
      setIsDragOverBucket(true);
    }
  };

  const handleDragLeaveBucketZone = () => {
    dragCounterRef.current -= 1;
    if (dragCounterRef.current <= 0) {
      dragCounterRef.current = 0;
      setIsDragOverBucket(false);
    }
  };

  const handleDropIntoBucketZone = (e: React.DragEvent) => {
    e.preventDefault();
    dragCounterRef.current = 0;
    setIsDragOverBucket(false);
    try {
      const dataStr = e.dataTransfer.getData('application/json') || e.dataTransfer.getData('text/plain');
      if (!dataStr) return;
      const data = JSON.parse(dataStr);
      if (data.type === 'timeline-task' && data.taskId) {
        // QUE-1 (US-QUE-1-05) — a JOB slot dragged back here is NOT the
        // plain-task path (it would call PLN-7's bare unplace, the exact
        // "strand the link" risk BOARD-1's own comments warn against).
        // Same rule as the day slot's own menu — pure, tested apart from
        // this DOM in `boardModel.test.ts`.
        const intent = classifyUnscheduleTarget({workItemId: data.workItemId, workTaskId: data.workTaskId});
        if (intent === 'confirm-job-slot') {
          onRequestUnscheduleJobSlot(Number(data.workTaskId), data.jobTitle || `Job #${data.workItemId}`, data.dayLabel || 'that day');
        } else if (intent === 'plain-task') {
          onDropTaskIntoBucket(data.taskId);
        } else {
          // 'invalid' (a job slot with no work_task_id) — still a no-op
          // rather than guessing which endpoint to call, but it says so:
          // nothing visible happens on this drop, and a silent one leaves
          // no way to tell a malformed payload from a dead drop zone.
          console.error('Unscheduled drop ignored — job slot payload has no work_task_id:', data);
        }
      }
    } catch (err) {
      console.error('Failed to drop task into bucket:', err);
    }
  };

  const handleOpenKeyboardModal = (task: Task) => {
    setKeyboardModalTask(task);
    setTargetAgentId(agents[0]?.id || '');
    setTargetDay(workspace?.planningWindowStart || '');
    setTargetPosition('end');
  };

  const handleConfirmKeyboardPlacement = () => {
    if (!keyboardModalTask || !targetAgentId || !targetDay) return;

    let indexToPlace: number | undefined = undefined;
    if (targetPosition === 'start') {
      indexToPlace = 0;
    } else if (targetPosition === 'index') {
      indexToPlace = targetIndex;
    }

    onAddToAgentDay(keyboardModalTask.id, targetAgentId, targetDay, indexToPlace);
    setKeyboardModalTask(null);
  };

  const count = backlogTasks.length;
  // US-QUE-1-02 — one header count across both row shapes: a role line
  // and a plain task are both "waiting," and the planner reading the bar
  // should not have to add two numbers themselves.
  const totalWaitingCount = waitingCards.length + count;
  const countText = totalWaitingCount === 1 ? '1 waiting' : `${totalWaitingCount} waiting`;

  // Plan Health metrics (Schedule view only — see showCapacityPanel).
  // Scoped to the workspace's whole planning window, not whatever slice
  // happens to be scrolled into view on the Grid, so the numbers stay
  // stable across paging/1-2 week toggles.
  const capacitySummary = showCapacityPanel
    ? calculateWorkspaceCapacitySummary(agents, visibleDates, timelinesInWorkspace, tasks)
    : null;
  const costSummary = showCapacityPanel
    ? calculateWorkspaceCostSummary(agents, visibleDates, timelinesInWorkspace, tasks, settings, throughput)
    : null;
  const unplannedMinutes =
    backlogTasks.reduce((sum, t) => sum + (t.duration || 0), 0) +
    waitingCards.reduce((sum, c) => sum + (c.expected_minutes || 0), 0);
  const unplannedHours = Math.round((unplannedMinutes / 60) * 10) / 10;
  const blockedTaskCount = tasks.filter(t => t.timelineId && t.status === 'needs_info').length;
  const outOfWindowCount = workspace
    ? timelinesInWorkspace.filter(tl => isDateOutOfWindow(tl.plannedDate, workspace.planningWindowStart, workspace.planningWindowEnd)).length
    : 0;
  // Six fills the two-column layout evenly (3 rows) without overflowing
  // the strip at its default height.
  const topOpenAgents = capacitySummary ? capacitySummary.perAgent.slice(0, 6) : [];

  return (
    <div 
      id="backlog-drawer-container"
      onDragEnter={handleDragEnterBucketZone}
      onDragOver={handleDragOverBucketZone}
      onDragLeave={handleDragLeaveBucketZone}
      onDrop={handleDropIntoBucketZone}
      className={`border-t bg-neutral-50 shrink-0 transition-all select-none relative ${
        isDragOverBucket
          ? 'border-neutral-900 bg-neutral-100 ring-2 ring-neutral-900/20 shadow-inner'
          : isDraggingTaskFromTimeline
          ? 'border-dashed border-neutral-400 bg-neutral-100/60 ring-2 ring-neutral-400/30'
          : 'border-neutral-200'
      }`}
    >
      {/* Return to queue drag overlay notice */}
      {isDragOverBucket && (
        <div className="absolute inset-0 bg-neutral-900/90 text-white z-30 flex items-center justify-center text-xs font-semibold gap-2 animate-in fade-in duration-75 pointer-events-none">
          <Inbox className="w-4 h-4" />
          <span>Drop to return task to Unscheduled</span>
        </div>
      )}

      {/* Section Header — click to expand/collapse the panel */}
      <div
        id="backlog-drawer-bar"
        className="h-10 px-4 flex items-center justify-between border-b border-neutral-200 bg-neutral-50 select-none"
      >
        <button
          id="backlog-toggle-btn"
          type="button"
          onClick={() => setIsCollapsed(prev => !prev)}
          aria-expanded={!isCollapsed}
          className="flex items-center gap-2.5 h-full"
          title={isCollapsed ? 'Expand Unscheduled' : 'Collapse Unscheduled'}
        >
          {isCollapsed ? <ChevronRight className="w-3.5 h-3.5 text-neutral-400" /> : <ChevronDown className="w-3.5 h-3.5 text-neutral-400" />}
          <Inbox className="w-4 h-4 text-neutral-500" />
          <span className="text-xs font-semibold text-neutral-800">
            Unscheduled
          </span>
          <span className="text-[11px] font-mono text-neutral-600 bg-neutral-200/80 px-2 py-0.2 rounded-full font-medium">
            {countText}
          </span>
          {isCollapsed && unplannedHours > 0 && (
            <span className="text-[11px] text-neutral-500">{unplannedHours}h unplanned</span>
          )}
        </button>
        <div className="flex-1 flex items-center px-2.5">
          {confirmationMessage && (
            <span
              id="backlog-placement-confirmation"
              className="text-[11px] font-medium text-emerald-700 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded-full animate-in fade-in duration-150"
            >
              ✓ {confirmationMessage}
            </span>
          )}
        </div>

        <div className="flex items-center gap-2">
          <button
            id="quick-add-backlog-btn"
            onClick={() => { setIsAdding(isCollapsed ? true : !isAdding); setIsCollapsed(false); }}
            className="px-2 py-0.5 text-xs font-medium text-neutral-600 hover:text-neutral-900 hover:bg-neutral-200/60 rounded flex items-center gap-1 transition-colors"
            title="Add task directly to Unscheduled"
          >
            <Plus className="w-3.5 h-3.5" />
            Add to Unscheduled
          </button>
        </div>
      </div>

      {!isCollapsed && (<>
      {/* Resize handle: drag to adjust the Unscheduled panel's height */}
      <div
        id="backlog-resize-handle"
        onMouseDown={handleResizeStart}
        className="h-2.5 flex items-center justify-center cursor-row-resize group bg-neutral-50 hover:bg-neutral-200/60 transition-colors border-b border-neutral-200/70"
        title="Drag to resize the Unscheduled panel"
      >
        <GripHorizontal className="w-4 h-2.5 text-neutral-300 group-hover:text-neutral-500" />
      </div>

      {/* Unscheduled content: open by default (US-QUE-1-01); height is user-adjustable
          via the grip above. The grid itself has a user-adjustable WIDTH too
          (founder, 2026-10-30) instead of stretching to fill the row — on a wide
          screen (e.g. Schedule view with the roster rail hidden) that stretch
          used to leave a big dead gap between short role names and the
          right-aligned numeric columns. The reclaimed width goes to the Plan
          Health panel instead (Schedule view only, currently parked — see PlannerApp.tsx). */}
      <div
        id="backlog-drawer-content"
        ref={paneRowRef}
        style={{ height: backlogHeight }}
        className="p-3 bg-neutral-100/50 flex items-stretch gap-1.5 min-h-0"
      >
        {/* `shrink` (not `shrink-0`) with a floor of its own: the seam's
            clamp only runs while the seam is being dragged, so without this
            the grid kept a width won earlier and squashed the Stages panel
            when it opened later — or overflowed the row when the window got
            narrower. Letting flexbox enforce both floors covers both cases
            with no measuring (Opus review, 2026-10-31). */}
        <div style={{ width: unscheduledPaneWidth }} className="shrink min-w-[280px] flex flex-col min-h-0 overflow-y-auto">
          {/* Quick Add Inline Form */}
          {isAdding && (
            <form 
              onSubmit={handleCreate}
              className="p-2.5 bg-white border border-neutral-300 rounded-md shadow-xs flex items-center gap-2 mb-2 shrink-0 animate-in fade-in duration-75"
            >
              <input
                type="text"
                placeholder="Unplanned task title..."
                value={newTitle}
                onChange={(e) => setNewTitle(e.target.value)}
                className="flex-1 px-2.5 py-1 text-xs border border-neutral-300 rounded focus:outline-none focus:border-neutral-900"
                autoFocus
              />
              <div className="flex items-center gap-1 text-xs text-neutral-500">
                <input
                  type="number"
                  min="5"
                  step="5"
                  value={newDuration}
                  onChange={(e) => setNewDuration(Number(e.target.value))}
                  className="w-14 px-1.5 py-1 text-xs border border-neutral-300 rounded text-center"
                />
                <span className="text-[10px]">m</span>
              </div>
              <input
                type="text"
                placeholder="Assignee (opt)"
                value={newAssignee}
                onChange={(e) => setNewAssignee(e.target.value)}
                className="w-24 px-2 py-1 text-xs border border-neutral-300 rounded text-neutral-700"
              />
              <button
                type="button"
                onClick={() => setIsAdding(false)}
                className="px-2 py-1 text-xs text-neutral-600 hover:text-neutral-900"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={!newTitle.trim()}
                className="px-3 py-1 bg-neutral-900 text-white rounded text-xs font-medium hover:bg-neutral-800 disabled:opacity-50"
              >
                Save
              </button>
            </form>
          )}

          {/* Role lines + plain tasks / Empty State. A GRID, not stacked
              cards (founder, 2026-10-30): column headers once, a compact
              one-line row per item, a group-header row per job (its own
              "row header" for the rows under it) instead of repeating the
              job name on every line. Steps and the Place… form still live
              in an expanded detail row — the default row height is what
              shrank, not what the row can show on demand. */}
          {totalWaitingCount === 0 && !isLoadingCards ? (
            <div className="flex-1 flex items-center justify-center text-center p-6 text-xs text-neutral-400">
              <span>Nothing unscheduled — everything is placed on a day.</span>
            </div>
          ) : (
            <div className="flex-1 overflow-y-auto pr-1">
              {cardsError && (
                <p role="alert" className="px-2 py-2 text-[11px] text-red-700 bg-red-50 border border-red-200 rounded mb-1.5">
                  {cardsError}
                </p>
              )}
              {isLoadingCards && waitingCards.length === 0 && (
                <p className="px-1 py-1 text-[11px] text-neutral-400">Loading…</p>
              )}

              {/* table-fixed (founder, 2026-10-30): with the pane width now
                  user-set (not flex-1), the one column with no declared
                  width (Role/Task) only ever absorbs what's actually left
                  over in THAT pane — shrink the pane and the gap before
                  Steps shrinks with it, instead of ballooning on its own. */}
              <table className="w-full table-fixed text-[11px] border-collapse bg-white border border-neutral-200 rounded-md overflow-hidden">
                <thead>
                  <tr className="text-[10px] text-neutral-500 bg-neutral-50 border-b border-neutral-200">
                    <th scope="col" className="text-left font-medium px-2 py-1">Role / Task</th>
                    <th scope="col" className="text-right font-medium px-2 py-1 w-12">Steps</th>
                    <th scope="col" className="text-right font-medium px-2 py-1 w-24">Min</th>
                    <th scope="col" className="text-left font-medium px-2 py-1 w-36">Est.</th>
                    <th scope="col" className="text-right font-medium px-2 py-1 w-[52px]"><span className="sr-only">Actions</span></th>
                  </tr>
                </thead>

                {/* ROW-1 (US-ROW-1-01): no job-header row — each role line is
                    ONE row that names its own job, because a job with a single
                    role line is the common case and the header cost it a row
                    every time. The per-job `<tbody>` stays (ROW-1 D-5): it has
                    no visual weight, and it is the scope 26 e2e locators across
                    three specs resolve against. */}
                {cardGroups.map((group) => (
                  <tbody key={group.workItemId} data-testid="unscheduled-job-group" className="border-b border-neutral-100 last:border-b-0">
                    {group.cards.map((card) => {
                      const isSelected = selectedCardKey === card.card_key;
                      const isPlacingThis = placingFor === card.card_key;
                      const stepWord = card.step_count === 1 ? 'step' : 'steps';
                      return (
                        <Fragment key={card.card_key}>
                          <tr
                            data-testid="unscheduled-card"
                            draggable
                            onDragStart={(e) => {
                              const payload = {
                                type: 'job-card',
                                workItemId: card.work_item_id,
                                lensKey: card.lens_key,
                                cardKey: card.card_key,
                              };
                              const str = JSON.stringify(payload);
                              e.dataTransfer.setData('application/json', str);
                              e.dataTransfer.setData('text/plain', str);
                              e.dataTransfer.effectAllowed = 'move';
                            }}
                            onClick={() => setSelectedCardKey((prev) => (prev === card.card_key ? null : card.card_key))}
                            aria-selected={isSelected}
                            title="Click to see its steps on the right. Drag onto someone's day, or use Place…"
                            className={`border-t border-neutral-100 cursor-grab active:cursor-grabbing ${
                              isSelected ? 'bg-neutral-100' : 'hover:bg-neutral-50/70'
                            }`}
                          >
                            {/* `Job · Role` as one truncating string (ROW-1 D-4):
                                Role/Task is the only column without a declared
                                width, so it is the only one that can absorb a long
                                job name — and must, rather than shoving the numeric
                                columns around. Full text on hover. */}
                            <td className="px-2 py-1 truncate" title={`${group.jobTitle} · ${card.lens_label || card.lens_key}`}>
                              <span className="inline-flex items-center gap-1 min-w-0">
                                <GripVertical className="w-3 h-3 shrink-0 text-neutral-300" />
                                {/* US-ROW-1-02: the read-only job view, NOT the
                                    modal that carries the "+ New job" form. Same
                                    `setPeekId` the exception chips below already
                                    use — one read-only job view everywhere. */}
                                <button
                                  type="button"
                                  data-testid="unscheduled-job-title"
                                  onClick={(e) => { e.stopPropagation(); setPeekId(card.work_item_id); }}
                                  title="Open this job (read-only)"
                                  className="shrink-0 max-w-[55%] truncate font-semibold text-neutral-900 hover:underline"
                                >
                                  {group.jobTitle}
                                </button>
                                <span className="shrink-0 text-neutral-300">·</span>
                                <span className="truncate" data-testid="unscheduled-card-handle">{card.lens_label || card.lens_key}</span>
                                {(card.parent_work_item_id ?? 0) > 0 && (
                                  <button
                                    type="button"
                                    data-testid="unscheduled-parent-chip"
                                    onClick={(e) => { e.stopPropagation(); setPeekId(card.parent_work_item_id!); }}
                                    className="shrink-0 rounded-full border border-amber-200 bg-amber-50 px-1.5 text-[9px] text-amber-800 hover:bg-amber-100"
                                  >
                                    from #{card.parent_work_item_id}
                                  </button>
                                )}
                                {(card.child_count ?? 0) > 0 && (
                                  <button
                                    type="button"
                                    data-testid="unscheduled-children-chip"
                                    onClick={(e) => { e.stopPropagation(); setPeekId(card.work_item_id); }}
                                    className="shrink-0 rounded-full border border-amber-200 bg-amber-50 px-1.5 text-[9px] text-amber-800 hover:bg-amber-100"
                                  >
                                    {card.child_count} sent on
                                  </button>
                                )}
                              </span>
                            </td>
                            <td className="px-2 py-1 text-right font-mono text-neutral-600">{card.step_count}</td>
                            <td className="px-2 py-1 text-right font-mono text-neutral-600">{formatMinutes(card.expected_minutes)}</td>
                            <td className="px-2 py-1"><EstimateBadge status={card.estimate_status} /></td>
                            <td className="px-2 py-1">
                              <div className="flex items-center justify-end gap-0.5">
                                <button
                                  type="button"
                                  data-testid="unscheduled-place"
                                  onClick={(e) => { e.stopPropagation(); openPlaceForm(card.card_key); }}
                                  title="Place…"
                                  className="p-0.5 text-neutral-500 hover:text-neutral-900 rounded"
                                >
                                  <CalendarPlus className="w-3 h-3" />
                                </button>
                              </div>
                            </td>
                          </tr>

                          {/* The click path (D-4) — identical rule to the drag, same handler upstream. */}
                          {isPlacingThis && (
                            <tr>
                              <td colSpan={5} className="px-2 py-1.5 bg-neutral-50/60">
                                <div className="flex flex-wrap items-end gap-1.5 bg-white border border-neutral-200 rounded-md px-2 py-1.5">
                                  <label className="flex flex-col gap-0.5">
                                    <span className="text-[10px] text-neutral-600">Who</span>
                                    <select
                                      value={placeAgentId}
                                      onChange={(e) => setPlaceAgentId(e.target.value)}
                                      className="text-[11px] px-1.5 py-1 border border-neutral-200 rounded bg-white max-w-[110px]"
                                    >
                                      {agents.length === 0 && <option value="">No agents in this plan</option>}
                                      {agents.map((a) => (
                                        <option key={a.id} value={a.id}>{a.name}</option>
                                      ))}
                                    </select>
                                  </label>
                                  <label className="flex flex-col gap-0.5">
                                    <span className="text-[10px] text-neutral-600">Day</span>
                                    <input
                                      type="date"
                                      value={placeDay}
                                      min={windowBounds.min}
                                      max={windowBounds.max}
                                      onChange={(e) => setPlaceDay(e.target.value)}
                                      className={`text-[11px] px-1.5 py-1 border rounded font-mono bg-white ${
                                        placeDayOutOfWindow ? 'border-red-500 bg-red-50/30' : 'border-neutral-200'
                                      }`}
                                    />
                                  </label>
                                  <button
                                    type="button"
                                    data-testid="unscheduled-place-confirm"
                                    onClick={() => void handlePlaceCard(card)}
                                    disabled={isPlacingCard || agents.length === 0 || !placeAgentId || !placeDay || placeDayOutOfWindow}
                                    className="px-2.5 py-1.5 bg-neutral-900 text-white rounded text-[11px] font-semibold hover:bg-neutral-800 disabled:opacity-60"
                                  >
                                    {isPlacingCard ? 'Placing…' : 'Place'}
                                  </button>
                                  {/* WIN-1 (US-WIN-1-02): min/max stops the picker reaching
                                      outside the window, but a typed date can still land
                                      there in some browsers — so say why Place is off and
                                      keep what they typed (CLAUDE.md). */}
                                  {placeDayOutOfWindow ? (
                                    <span className="text-[10px] text-red-600 basis-full flex items-center gap-1">
                                      <AlertTriangle className="w-3 h-3 shrink-0" />
                                      {placeDay} is outside this plan's window ({workspace?.planningWindowStart} to {workspace?.planningWindowEnd}). Pick a day inside it.
                                    </span>
                                  ) : (
                                    <span className="text-[10px] text-neutral-500 basis-full">
                                      All {card.step_count} {stepWord} go onto that day as one card.
                                    </span>
                                  )}
                                  {placeAgentId && placeDay && !placeDayOutOfWindow && !dayHasTimeline(placeAgentId, placeDay) && (
                                    <span className="text-[10px] text-neutral-500 basis-full">
                                      {agentName(placeAgentId)} has no day on {placeDay} yet — it will be created.
                                    </span>
                                  )}
                                  {placeAgentId && !agents.find((a) => a.id === placeAgentId)?.userId && (
                                    <span className="text-[10px] text-amber-700 basis-full flex items-center gap-1">
                                      <AlertTriangle className="w-3 h-3 shrink-0" />
                                      {agentName(placeAgentId)} has no login linked — they won't see this in Execution.
                                    </span>
                                  )}
                                </div>
                              </td>
                            </tr>
                          )}
                        </Fragment>
                      );
                    })}
                  </tbody>
                ))}

                {backlogTasks.length > 0 && (
                  <tbody data-testid="unscheduled-tasks">
                    {backlogTasks.map((task) => {
                      const isSelected = task.id === activeModalTaskId;
                      return (
                        <tr
                          key={task.id}
                          id={`backlog-row-${task.id}`}
                          onClick={() => {
                            if (onOpenTaskEditModal) onOpenTaskEditModal(task.id);
                            else if (onSelectTask) onSelectTask(task.id);
                          }}
                          draggable
                          onDragStart={(e) => {
                            const payload = JSON.stringify({ type: 'backlog-task', taskId: task.id });
                            e.dataTransfer.setData('text/plain', payload);
                            e.dataTransfer.setData('application/json', payload);
                            e.dataTransfer.effectAllowed = 'move';
                          }}
                          className={`border-t border-neutral-100 cursor-pointer hover:bg-neutral-50/70 ${
                            isSelected ? 'bg-neutral-50 ring-1 ring-inset ring-neutral-900/10' : ''
                          }`}
                        >
                          <td className="px-2 py-1 truncate">
                            <span className="inline-flex items-center gap-1 min-w-0">
                              <GripVertical className="w-3 h-3 shrink-0 text-neutral-300" />
                              <span className="font-medium text-neutral-900 truncate" title={task.title}>{task.title}</span>
                            </span>
                          </td>
                          <td className="px-2 py-1 text-right text-neutral-300 font-mono">—</td>
                          <td className="px-2 py-1 text-right font-mono text-neutral-600">{task.duration}m</td>
                          <td className="px-2 py-1 truncate text-neutral-600">
                            {task.assignee ? (
                              <span className="inline-flex items-center gap-1">
                                <User className="w-3 h-3 text-neutral-400 shrink-0" />
                                <span className="truncate">{task.assignee}</span>
                              </span>
                            ) : (
                              <span className="text-neutral-300 font-mono">—</span>
                            )}
                          </td>
                          <td className="px-2 py-1" onClick={(e) => e.stopPropagation()}>
                            <div className="flex items-center justify-end gap-0.5">
                              <button
                                id={`add-to-timeline-btn-${task.id}`}
                                onClick={() => handleOpenKeyboardModal(task)}
                                className="p-0.5 text-neutral-500 hover:text-neutral-900 rounded"
                                title="Add to timeline… (choose an agent and a day)"
                              >
                                <CornerDownRight className="w-3 h-3" />
                              </button>
                              <button
                                onClick={() => onDeleteTask(task.id)}
                                className="p-0.5 text-neutral-400 hover:text-red-600 rounded"
                                title="Delete task"
                              >
                                <Trash2 className="w-3 h-3" />
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                )}
              </table>
            </div>
          )}
        </div>

        {/* The seam. Always here, even with the Stages panel closed, so the
            grid can be pulled narrower on its own and not only as a side
            effect of opening the panel on the right. */}
        <div
          id="unscheduled-pane-seam"
          onMouseDown={handleUnscheduledPaneResizeStart}
          className="w-1.5 shrink-0 cursor-col-resize group flex items-center justify-center hover:bg-neutral-200/60 transition-colors rounded"
          title="Drag to move the divider between Unscheduled and Stages"
        >
          <GripVertical className="w-3 h-4 text-neutral-300 group-hover:text-neutral-500" />
        </div>

        {/* Stages panel (founder, 2026-10-30): the bottom drawer's RIGHT
            pane — click a role line on the left, its steps (the pinned
            version's stage order) show here, same content the old
            inline-expand row used to show. Nothing selected → no panel.
            It takes the rest of the row rather than a fixed width, so it
            reaches the right edge on a wide screen; the seam above sets
            where it starts (founder, 2026-10-31). */}
        {selectedCard && (
          <div
            id="unscheduled-stages-panel"
            className="flex-1 min-w-[320px] flex flex-col min-h-0 bg-white border border-neutral-200 rounded-md overflow-hidden"
          >
              <div className="h-8 px-2.5 flex items-center justify-between gap-2 border-b border-neutral-200 bg-neutral-50 shrink-0">
                <div className="min-w-0">
                  <p className="text-[11px] font-semibold text-neutral-900 truncate">{selectedJobTitle}</p>
                  <p className="text-[10px] text-neutral-500 truncate">{selectedCard.lens_label || selectedCard.lens_key} · Stages</p>
                </div>
                <button
                  type="button"
                  onClick={() => setSelectedCardKey(null)}
                  title="Close"
                  className="shrink-0 p-0.5 text-neutral-400 hover:text-neutral-800 rounded"
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              </div>
              {/* Same column grammar as the Unscheduled grid on the left —
                  labelled header, Min and Est. in the same widths — so the
                  two panes read as one table split by the seam rather than
                  a table next to a list (founder, 2026-10-31). */}
              <div className="flex-1 overflow-y-auto">
                <table className="w-full table-fixed text-[11px] border-collapse">
                  <thead>
                    <tr className="text-[10px] text-neutral-500 bg-neutral-50 border-b border-neutral-200">
                      <th scope="col" className="text-right font-medium px-2 py-1 w-8">#</th>
                      <th scope="col" className="text-left font-medium px-2 py-1">Stage / Task</th>
                      <th scope="col" className="text-right font-medium px-2 py-1 w-24">Min</th>
                      <th scope="col" className="text-left font-medium px-2 py-1 w-36">Est.</th>
                    </tr>
                  </thead>
                  <tbody>
                    {selectedCard.steps.map((step, index) => (
                      <tr key={step.work_task_id} className="border-t border-neutral-100">
                        <td className="px-2 py-1 text-right font-mono text-neutral-400 align-top">{index + 1}</td>
                        <td className="px-2 py-1 align-top">
                          <span className="block truncate text-neutral-800" title={step.stage_label || step.stage_key}>
                            {step.stage_label || step.stage_key}
                          </span>
                          {step.task && <span className="block text-[10px] text-neutral-500">{step.task}</span>}
                        </td>
                        <td className="px-2 py-1 text-right font-mono text-neutral-600 align-top">
                          {formatMinutes(step.expected_minutes)}
                        </td>
                        <td className="px-2 py-1 align-top">
                          <EstimateBadge status={step.estimate_status} source={step.estimate_source} />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
          </div>
        )}

        {/* Plan Health: fills the width reclaimed in Schedule view (no roster
            rail there) with numbers the backlog exists to answer — is there
            room for this work, and what's currently blocking the plan. */}
        {capacitySummary && (
          <div
            id="plan-health-panel"
            className={`${compactMetrics ? 'w-[392px]' : 'w-[728px]'} shrink-0 border-l border-neutral-200 pl-4 flex flex-col gap-2 min-h-0 overflow-y-auto`}
          >
            <div className={`${compactMetrics ? 'flex flex-col gap-3' : 'flex gap-4'} items-start shrink-0`}>
            {/* KPI column — tiles stack 3x2 so their top edge lines up with
                the first backlog row, no section header pushing them down */}
            <div className="grid grid-cols-3 auto-rows-min gap-2 shrink-0 w-[372px] content-start">
              <div className="px-2.5 py-1.5 bg-white border border-neutral-200 rounded-md">
                <div className="text-[10px] text-neutral-500 leading-tight">Planned cost</div>
                {costSummary && costSummary.isUnconfigured ? (
                  <>
                    <div className="text-sm font-semibold text-neutral-300 leading-snug">—</div>
                    <button
                      type="button"
                      onClick={onOpenSettings}
                      className="text-[10px] text-neutral-500 underline decoration-dotted underline-offset-2 hover:text-neutral-900 leading-tight"
                    >
                      Set rates
                    </button>
                  </>
                ) : (
                  <>
                    <div className="text-sm font-semibold text-neutral-900 leading-snug">
                      {formatMoney(costSummary?.totalCost ?? 0, settings.currencySymbol)}
                    </div>
                    <div className="text-[10px] text-neutral-400 leading-tight">
                      {formatMoney(costSummary?.blendedHourlyRate ?? 0, settings.currencySymbol)}/h blended
                    </div>
                  </>
                )}
              </div>
              <div className="px-2.5 py-1.5 bg-white border border-neutral-200 rounded-md">
                <div className="text-[10px] text-neutral-500 leading-tight">Human</div>
                <div className="text-sm font-semibold text-neutral-900 leading-snug">
                  {costSummary && costSummary.isUnconfigured ? '—' : formatMoney(costSummary?.humanCost ?? 0, settings.currencySymbol)}
                </div>
                <div className="text-[10px] text-neutral-400 leading-tight">{costSummary?.humanHours ?? 0}h planned</div>
              </div>
              <div className="px-2.5 py-1.5 bg-white border border-neutral-200 rounded-md">
                <div className="text-[10px] text-neutral-500 leading-tight">AI</div>
                <div className="text-sm font-semibold text-neutral-900 leading-snug">
                  {costSummary && costSummary.isUnconfigured ? '—' : formatMoney(costSummary?.aiCost ?? 0, settings.currencySymbol)}
                </div>
                <div className="text-[10px] text-neutral-400 leading-tight">{costSummary?.aiHours ?? 0}h planned</div>
              </div>
              <div className="px-2.5 py-1.5 bg-white border border-neutral-200 rounded-md">
                <div className="text-[10px] text-neutral-500 leading-tight">Open capacity</div>
                <div className="text-sm font-semibold text-neutral-900 leading-snug">{capacitySummary.openCapacityHours}h</div>
                <div className="text-[10px] text-neutral-400 leading-tight">of {capacitySummary.totalCapacityHours}h</div>
              </div>
              <div className="px-2.5 py-1.5 bg-white border border-neutral-200 rounded-md">
                <div className="text-[10px] text-neutral-500 leading-tight">Unplanned</div>
                <div className="text-sm font-semibold text-neutral-900 leading-snug">{unplannedHours}h</div>
                <div className="text-[10px] text-neutral-400 leading-tight">{count} {count === 1 ? 'task' : 'tasks'}</div>
              </div>
              <div className="px-2.5 py-1.5 bg-white border border-neutral-200 rounded-md">
                <div className="text-[10px] text-neutral-500 leading-tight">Blocked</div>
                <div className={`text-sm font-semibold leading-snug ${blockedTaskCount > 0 ? 'text-red-700' : 'text-neutral-900'}`}>
                  {blockedTaskCount}
                </div>
                <div className="text-[10px] text-neutral-400 leading-tight">need info</div>
              </div>
            </div>

            {/* Open-capacity column — fills the remaining width */}
            <div className={compactMetrics ? 'w-full' : 'flex-1 min-w-0'}>
              {topOpenAgents.length > 0 && (
                <div className="flex flex-col gap-1 content-start">
                  <div className="text-[10px] font-semibold text-neutral-400 uppercase tracking-wider leading-tight">
                    Most open capacity
                  </div>
                  {topOpenAgents.map(row => {
                    const cost = costSummary?.perAgent.find(c => c.agent.id === row.agent.id);
                    return (
                      <div key={row.agent.id} className="flex items-center gap-2 text-[11px] leading-tight">
                        <div className="w-2 h-2 rounded-xs shrink-0" style={{ backgroundColor: row.agent.color }} />
                        <span className="truncate text-neutral-700 w-[150px] shrink-0">{row.agent.name}</span>
                        <span
                          className="font-mono shrink-0 w-[52px] text-right text-neutral-400"
                          title={cost ? `${formatMoney(cost.hourlyRate, settings.currencySymbol)}/h × ${cost.plannedHours}h planned` : undefined}
                        >
                          {costSummary && !costSummary.isUnconfigured && cost
                            ? formatMoney(cost.cost, settings.currencySymbol)
                            : ''}
                        </span>
                        <span
                          className={`font-mono font-medium shrink-0 w-[76px] text-right ${row.openHours < 0 ? 'text-amber-700' : 'text-neutral-500'}`}
                          title={`${row.plannedHours}h planned of ${row.capacityHours}h capacity`}
                        >
                          {row.openHours < 0 ? `${Math.abs(row.openHours)}h over` : `${row.openHours}h free`}
                        </span>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
            </div>

            {/* Constraint violations — full-width footer of the panel; inline
                chips. Silence means healthy, same convention as the rest of
                the app. */}
            {(capacitySummary.overCapacityAgentDays > 0 || blockedTaskCount > 0 || outOfWindowCount > 0) && (
              <div className="flex flex-wrap items-center gap-1.5 shrink-0">
                  {capacitySummary.overCapacityAgentDays > 0 && (
                    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-amber-50 border border-amber-200 text-[11px] text-amber-800">
                      <AlertTriangle className="w-3 h-3 text-amber-600 shrink-0" />
                      {capacitySummary.overCapacityAgentDays} agent-day{capacitySummary.overCapacityAgentDays > 1 ? 's' : ''} over capacity
                    </span>
                  )}
                  {blockedTaskCount > 0 && (
                    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-red-50 border border-red-200 text-[11px] text-red-800">
                      <AlertCircle className="w-3 h-3 text-red-600 shrink-0" />
                      {blockedTaskCount} blocked task{blockedTaskCount > 1 ? 's' : ''} need info
                    </span>
                  )}
                {outOfWindowCount > 0 && (
                  <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-red-50 border border-red-200 text-[11px] text-red-800">
                    <Ban className="w-3 h-3 text-red-600 shrink-0" />
                    {outOfWindowCount} timeline{outOfWindowCount > 1 ? 's' : ''} outside planning window
                  </span>
                )}
              </div>
            )}
          </div>
        )}
        </div>
      </>)}

      {/* Keyboard Path Modal: "Add to timeline..." (Section 5) */}
      {keyboardModalTask && (
        <div 
          id="keyboard-add-timeline-modal"
          className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4 animate-in fade-in duration-100"
          onClick={() => setKeyboardModalTask(null)}
        >
          <div 
            className="bg-white rounded-lg shadow-xl border border-neutral-200 w-96 p-4 space-y-4 text-xs"
            onClick={(e) => e.stopPropagation()}
          >
            <div>
              <div className="text-[11px] font-semibold text-neutral-400 uppercase tracking-wider">
                Add to Timeline
              </div>
              <div className="text-sm font-bold text-neutral-900 mt-0.5">
                Add "{keyboardModalTask.title}" to timeline
              </div>
            </div>

            {/* Select Agent + Day: the target timeline is created automatically if this agent has none yet on this day */}
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-[11px] font-semibold text-neutral-600 mb-1">
                  Agent:
                </label>
                <select
                  value={targetAgentId}
                  onChange={(e) => setTargetAgentId(e.target.value)}
                  className="w-full px-2.5 py-1.5 border border-neutral-300 rounded text-xs focus:outline-none focus:border-neutral-900 bg-white"
                >
                  {agents.map(a => (
                    <option key={a.id} value={a.id}>{a.name}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-[11px] font-semibold text-neutral-600 mb-1">
                  Day:
                </label>
                <select
                  value={targetDay}
                  onChange={(e) => setTargetDay(e.target.value)}
                  className="w-full px-2.5 py-1.5 border border-neutral-300 rounded text-xs focus:outline-none focus:border-neutral-900 bg-white font-mono"
                >
                  {modalDays.map(d => (
                    <option key={d} value={d}>{formatShortDate(d)}</option>
                  ))}
                </select>
              </div>
            </div>

            {(() => {
              const existingTl = timelinesInWorkspace.find(tl => tl.agentId === targetAgentId && tl.plannedDate === targetDay);
              if (existingTl?.status === 'published') {
                return (
                  <p className="text-[11px] text-red-600 -mt-2">
                    That agent's timeline on this day is already published and locked. Choose a different agent or day.
                  </p>
                );
              }
              if (!existingTl) {
                return (
                  <p className="text-[11px] text-neutral-400 -mt-2">
                    No timeline exists yet for this agent/day — one will be created.
                  </p>
                );
              }
              return null;
            })()}

            {/* Select Position */}
            <div>
              <label className="block text-[11px] font-semibold text-neutral-600 mb-1">
                Placement Position:
              </label>
              <div className="space-y-1.5">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="placement-pos"
                    checked={targetPosition === 'end'}
                    onChange={() => setTargetPosition('end')}
                    className="text-neutral-900 focus:ring-0"
                  />
                  <span className="text-neutral-800">At the end of the timeline</span>
                </label>
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="placement-pos"
                    checked={targetPosition === 'start'}
                    onChange={() => setTargetPosition('start')}
                    className="text-neutral-900 focus:ring-0"
                  />
                  <span className="text-neutral-800">At the start (Position #1)</span>
                </label>
              </div>
            </div>

            {/* Modal Actions */}
            <div className="flex items-center justify-end gap-2 pt-2 border-t border-neutral-100">
              <button
                type="button"
                onClick={() => setKeyboardModalTask(null)}
                className="px-3 py-1.5 text-neutral-600 hover:text-neutral-900 rounded"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmKeyboardPlacement}
                disabled={!targetAgentId || !targetDay || timelinesInWorkspace.find(tl => tl.agentId === targetAgentId && tl.plannedDate === targetDay)?.status === 'published'}
                className="px-3.5 py-1.5 bg-neutral-900 text-white font-medium rounded hover:bg-neutral-800 disabled:opacity-50"
              >
                Add Task
              </button>
            </div>
          </div>
        </div>
      )}

      <JobPeekSheet workItemId={peekId ?? 0} open={peekId != null} onClose={() => setPeekId(null)} onOpenJob={setPeekId} />
    </div>
  );
}
