import { useState, useRef } from 'react';
import {
  Inbox,
  Plus,
  ArrowUpRight,
  GripVertical,
  GripHorizontal,
  Clock,
  User,
  Trash2,
  CornerDownRight,
  AlertTriangle,
  AlertCircle,
  Ban
} from 'lucide-react';
import { Task, Timeline, Agent, Workspace, AppSettings, Throughput } from '../types';
import { generateDaysList, formatShortDate, isDateOutOfWindow } from '../utils/dateUtils';
import { calculateWorkspaceCapacitySummary } from '../utils/agentUtils';
import { calculateWorkspaceCostSummary, formatMoney } from '../utils/costUtils';

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
}: BacklogDrawerProps) {
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
  const modalDays = workspace ? generateDaysList(workspace.planningWindowStart, 14) : [];

  // Drag over bucket state (for Section 3.E: Timeline -> Backlog)
  const [isDragOverBucket, setIsDragOverBucket] = useState(false);
  const dragCounterRef = useRef(0);

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
        onDropTaskIntoBucket(data.taskId);
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
  const countText = count === 1 ? '1 task waiting' : `${count} tasks waiting`;

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
  const unplannedMinutes = backlogTasks.reduce((sum, t) => sum + (t.duration || 0), 0);
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
      {/* Return to bucket drag overlay notice */}
      {isDragOverBucket && (
        <div className="absolute inset-0 bg-neutral-900/90 text-white z-30 flex items-center justify-center text-xs font-semibold gap-2 animate-in fade-in duration-75 pointer-events-none">
          <Inbox className="w-4 h-4" />
          <span>Drop to return task to unplanned backlog</span>
        </div>
      )}

      {/* Section Header — no collapse toggle; the panel stays permanently expanded */}
      <div
        id="backlog-drawer-bar"
        className="h-10 px-4 flex items-center justify-between border-b border-neutral-200 bg-neutral-50 select-none"
      >
        <div className="flex items-center gap-2.5">
          <Inbox className="w-4 h-4 text-neutral-500" />
          <span className="text-xs font-semibold text-neutral-800">
            Backlog
          </span>
          <span className="text-[11px] font-mono text-neutral-600 bg-neutral-200/80 px-2 py-0.2 rounded-full font-medium">
            {countText}
          </span>
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
            onClick={() => setIsAdding(!isAdding)}
            className="px-2 py-0.5 text-xs font-medium text-neutral-600 hover:text-neutral-900 hover:bg-neutral-200/60 rounded flex items-center gap-1 transition-colors"
            title="Add task directly to backlog"
          >
            <Plus className="w-3.5 h-3.5" />
            Add to backlog
          </button>
        </div>
      </div>

      {/* Resize handle: drag to adjust the backlog panel's height */}
      <div
        id="backlog-resize-handle"
        onMouseDown={handleResizeStart}
        className="h-2.5 flex items-center justify-center cursor-row-resize group bg-neutral-50 hover:bg-neutral-200/60 transition-colors border-b border-neutral-200/70"
        title="Drag to resize the backlog panel"
      >
        <GripHorizontal className="w-4 h-2.5 text-neutral-300 group-hover:text-neutral-500" />
      </div>

      {/* Backlog Content: permanently expanded; height is user-adjustable via the grip above.
          Row content is capped to a comfortable reading width (max-w-3xl) and left-aligned —
          otherwise, on wide screens (e.g. Schedule view with the roster rail hidden), each row
          stretches edge-to-edge with a big dead gap between the title and its actions. The
          reclaimed width goes to the Plan Health panel instead (Schedule view only). */}
      <div
        id="backlog-drawer-content"
        style={{ height: backlogHeight }}
        className="p-3 bg-neutral-100/50 flex items-stretch gap-4 min-h-0"
      >
        <div className="flex-1 min-w-0 max-w-3xl flex flex-col min-h-0 overflow-y-auto">
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

          {/* Task List / Empty State */}
          {backlogTasks.length === 0 ? (
            <div className="flex-1 flex items-center justify-center text-center p-6 text-xs text-neutral-400">
              <span>Backlog empty — all workspace tasks are placed on timelines.</span>
            </div>
          ) : (
            <div className="flex-1 space-y-1.5 overflow-y-auto pr-1">
              {backlogTasks.map((task) => {
                const isSelected = task.id === activeModalTaskId;

                return (
                  <div
                    key={task.id}
                    id={`backlog-row-${task.id}`}
                    onClick={() => {
                      if (onOpenTaskEditModal) {
                        onOpenTaskEditModal(task.id);
                      } else if (onSelectTask) {
                        onSelectTask(task.id);
                      }
                    }}
                    draggable
                    onDragStart={(e) => {
                      const payload = JSON.stringify({ type: 'backlog-task', taskId: task.id });
                      e.dataTransfer.setData('text/plain', payload);
                      e.dataTransfer.setData('application/json', payload);
                      e.dataTransfer.effectAllowed = 'move';
                    }}
                    className={`px-2.5 py-1.5 rounded-md border text-xs bg-white cursor-pointer hover:border-neutral-400 hover:bg-neutral-50/60 transition-all flex items-center justify-between gap-3 shadow-2xs group ${
                      isSelected ? 'border-neutral-900 ring-1 ring-neutral-900/10 bg-neutral-50' : 'border-neutral-200/90'
                    }`}
                  >
                    {/* Left: Checkbox Slot + Drag Grip + Title */}
                    <div className="flex items-center gap-2.5 min-w-0 flex-1">
                      {/* Drag Grip Handle */}
                      <div onClick={(e) => e.stopPropagation()}>
                        <GripVertical className="w-3.5 h-3.5 text-neutral-400 shrink-0 opacity-60 group-hover:opacity-100 cursor-grab active:cursor-grabbing" />
                      </div>

                      {/* Title */}
                      <span className="font-medium text-neutral-900 truncate" title={task.title}>
                        {task.title}
                      </span>
                    </div>

                    {/* Middle: Duration + Assignee */}
                    <div className="flex items-center gap-3 shrink-0 text-[11px] text-neutral-500">
                      {/* Duration Pill */}
                      <span className="font-mono font-medium text-neutral-600 bg-neutral-100 px-1.5 py-0.5 rounded text-[11px]">
                        {task.duration}m
                      </span>

                      {/* Assignee if set */}
                      <span className="truncate max-w-[120px] text-neutral-600">
                        {task.assignee ? (
                          <span className="inline-flex items-center gap-1">
                            <User className="w-3 h-3 text-neutral-400" />
                            {task.assignee}
                          </span>
                        ) : (
                          <span className="text-neutral-300 font-mono">—</span>
                        )}
                      </span>
                    </div>

                    {/* Right: Actions */}
                    <div className="flex items-center gap-1 shrink-0" onClick={(e) => e.stopPropagation()}>
                      {/* Add to timeline: pick an agent + day (creates the timeline if needed) */}
                      <button
                        id={`add-to-timeline-btn-${task.id}`}
                        onClick={() => handleOpenKeyboardModal(task)}
                        className="px-2 py-0.5 bg-neutral-100 hover:bg-neutral-900 hover:text-white text-neutral-700 rounded text-[11px] font-medium flex items-center gap-1 transition-colors border border-neutral-200"
                        title="Add to timeline… (choose an agent and a day)"
                      >
                        <CornerDownRight className="w-3 h-3" />
                        Add to timeline…
                      </button>

                      <button
                        onClick={() => onDeleteTask(task.id)}
                        className="p-1 rounded text-neutral-400 hover:text-red-600 hover:bg-red-50 transition-colors"
                        title="Delete task"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

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
    </div>
  );
}
