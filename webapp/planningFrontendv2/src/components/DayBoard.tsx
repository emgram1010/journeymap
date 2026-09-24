import { useState, useRef, useEffect } from 'react';
import {
  ChevronLeft,
  ChevronRight,
  Plus,
  Lock,
  RotateCcw,
  AlertCircle,
  AlertTriangle,
  MoreVertical,
  Focus,
  ArrowLeft,
  GripVertical,
  Send,
  ArrowUp,
  ArrowDown,
  ArrowRightLeft,
  ArrowDownToLine,
  Trash2,
  Clock
} from 'lucide-react';
import { Agent, Timeline, Task, Workspace } from '../types';
import { formatShortDate, formatMonthDayYear, generateDaysList } from '../utils/dateUtils';
import { calculateAgentDayLoad } from '../utils/agentUtils';
import { getTimelineReadiness } from '../utils/planningLogic';
import { PlanCanvas } from './PlanCanvas';

interface DayBoardProps {
  workspace: Workspace | null;
  agents: Agent[];
  timelines: Timeline[];
  tasks: Task[];
  activeDay: string;
  focusedAgentId: string | null;
  planningWindowStart: string;
  planningWindowEnd: string;
  onChangeDay: (newDay: string) => void;
  onFocusAgent: (agentId: string | null) => void;
  onOpenTaskEditModal: (taskId: string) => void;
  onOpenTimelineEditModal: (timelineId: string) => void;
  onStartTimelineForAgentDay: (agentId: string, day: string) => void;
  onReorderTasksInTimeline: (timelineId: string, reorderedTasks: Task[]) => void;
  onMoveTaskToAgentDayTimeline: (
    taskId: string, 
    targetTimelineId: string, 
    targetIndex: number
  ) => void;
  onAddTaskToTimeline: (
    timelineId: string, 
    title: string, 
    plannedStart: string, 
    duration: number, 
    assignee?: string
  ) => void;
  onPublishTimeline: (timelineId: string) => void;
  onReopenTimeline: (timelineId: string) => void;
  onDeleteTask: (taskId: string) => void;
  onMoveTaskToBacklog: (taskId: string) => void;
  onMoveTaskToAgentDay: (taskId: string, agentId: string, day: string) => void;
  onOpenBulkPublishModal: () => void;
  onRequestPublishConfirm: (timelineId: string) => void;
  viewSwitcher?: React.ReactNode;
  buildPlanButton?: React.ReactNode;
  onTimelineTaskDragStart?: (taskId: string) => void;
  onTimelineTaskDragEnd?: () => void;
}

export function DayBoard({
  workspace,
  agents,
  timelines,
  tasks,
  activeDay,
  focusedAgentId,
  planningWindowStart,
  planningWindowEnd,
  onChangeDay,
  onFocusAgent,
  onOpenTaskEditModal,
  onOpenTimelineEditModal,
  onStartTimelineForAgentDay,
  onReorderTasksInTimeline,
  onMoveTaskToAgentDayTimeline,
  onAddTaskToTimeline,
  onPublishTimeline,
  onReopenTimeline,
  onDeleteTask,
  onMoveTaskToBacklog,
  onMoveTaskToAgentDay,
  onOpenBulkPublishModal,
  onRequestPublishConfirm,
  viewSwitcher,
  buildPlanButton,
  onTimelineTaskDragStart,
  onTimelineTaskDragEnd,
}: DayBoardProps) {
  // Drag state across columns
  const [draggedTaskId, setDraggedTaskId] = useState<string | null>(null);
  const [dragOverColTimelineId, setDragOverColTimelineId] = useState<string | null>(null);
  const [dragSlotIndex, setDragSlotIndex] = useState<number | null>(null);

  // Column header menu popover
  const [activeMenuTimelineId, setActiveMenuTimelineId] = useState<string | null>(null);

  // Per-task "..." menu (Epic E3: click card = edit; menu = everything else)
  const [activeTaskMenuId, setActiveTaskMenuId] = useState<string | null>(null);

  // "Move…" agent/day picker for a task already on a timeline
  const [moveTaskInfo, setMoveTaskInfo] = useState<{ taskId: string; sourceTimelineId: string } | null>(null);
  const [moveTargetAgentId, setMoveTargetAgentId] = useState<string>('');
  const [moveTargetDay, setMoveTargetDay] = useState<string>('');

  // Inline add state per column
  const [addingTaskColId, setAddingTaskColId] = useState<string | null>(null);
  const [inlineTitle, setInlineTitle] = useState('');
  const [inlineDuration, setInlineDuration] = useState(30);

  // Story E2: clicking "Add task" on a column with no timeline yet creates
  // the timeline, then auto-opens the same inline add-task form once it
  // shows up in props — a single click, reusing the existing add flow.
  const [pendingAutoAddAgentId, setPendingAutoAddAgentId] = useState<string | null>(null);
  useEffect(() => {
    if (!pendingAutoAddAgentId) return;
    const tl = timelines.find(
      t => t.agentId === pendingAutoAddAgentId && t.plannedDate === activeDay && t.workspaceId === workspace?.id
    );
    if (tl) {
      setAddingTaskColId(tl.id);
      setInlineTitle('');
      setInlineDuration(30);
      setPendingAutoAddAgentId(null);
    }
  }, [timelines, pendingAutoAddAgentId, activeDay, workspace?.id]);

  const visibleAgents = agents.filter(a => a.isVisible);

  // Reorder a task with its immediate neighbor (Move up / Move down)
  const handleMoveTaskSeq = (timeline: Timeline, index: number, direction: 'up' | 'down') => {
    const timelineTasks = tasks.filter(t => t.timelineId === timeline.id).sort((a, b) => a.seq - b.seq);
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= timelineTasks.length) return;
    const updated = [...timelineTasks];
    const [moved] = updated.splice(index, 1);
    updated.splice(targetIndex, 0, moved);
    const resequenced = updated.map((t, idx) => ({ ...t, seq: idx + 1 }));
    onReorderTasksInTimeline(timeline.id, resequenced);
  };

  const modalDays = workspace ? generateDaysList(workspace.planningWindowStart, 14) : [];

  // Date stepper navigation bounds
  const canGoPrev = activeDay > planningWindowStart;
  const canGoNext = activeDay < planningWindowEnd;

  const handlePrevDay = () => {
    if (!canGoPrev) return;
    const parts = activeDay.split('-').map(Number);
    const d = new Date(parts[0], parts[1] - 1, parts[2]);
    d.setDate(d.getDate() - 1);
    const prevStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    onChangeDay(prevStr);
  };

  const handleNextDay = () => {
    if (!canGoNext) return;
    const parts = activeDay.split('-').map(Number);
    const d = new Date(parts[0], parts[1] - 1, parts[2]);
    d.setDate(d.getDate() + 1);
    const nextStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    onChangeDay(nextStr);
  };

  // Drag task from column
  const handleTaskDragStart = (e: React.DragEvent, taskId: string, sourceTimelineId: string) => {
    setDraggedTaskId(taskId);
    const payload = JSON.stringify({
      type: 'timeline-task',
      taskId,
      sourceTimelineId,
    });
    e.dataTransfer.setData('application/json', payload);
    e.dataTransfer.setData('text/plain', payload);
    e.dataTransfer.effectAllowed = 'move';
    onTimelineTaskDragStart?.(taskId);
  };

  const handleTaskDragEnd = () => {
    setDraggedTaskId(null);
    setDragOverColTimelineId(null);
    setDragSlotIndex(null);
    onTimelineTaskDragEnd?.();
  };

  // Drag over a column drop zone
  const handleDragOverColumn = (e: React.DragEvent, timelineId: string, index: number) => {
    e.preventDefault();
    e.stopPropagation();
    e.dataTransfer.dropEffect = 'move';
    setDragOverColTimelineId(timelineId);
    setDragSlotIndex(index);
  };

  // Drop onto a column
  const handleDropOnColumn = (
    e: React.DragEvent, 
    targetTimeline: Timeline, 
    targetIndex: number
  ) => {
    e.preventDefault();
    e.stopPropagation();
    setDragOverColTimelineId(null);
    setDragSlotIndex(null);
    setDraggedTaskId(null);
    onTimelineTaskDragEnd?.();

    if (targetTimeline.status === 'published') {
      return; // Locked
    }

    try {
      const dataStr = e.dataTransfer.getData('application/json') || e.dataTransfer.getData('text/plain');
      if (!dataStr) return;
      const data = JSON.parse(dataStr);

      if (data.taskId) {
        onMoveTaskToAgentDayTimeline(data.taskId, targetTimeline.id, targetIndex);
      }
    } catch (err) {
      console.error('Failed to parse dropped task on DayBoard column:', err);
    }
  };

  // Formatted date label for stepper
  const dateObj = new Date(activeDay + 'T00:00:00');
  const formattedDayTitle = dateObj.toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric'
  });

  // Calculate bulk readiness for "Publish day" button (§7)
  const dayTimelines = timelines.filter(
    t => t.plannedDate === activeDay && t.workspaceId === workspace?.id
  );
  const readyTimelinesCount = dayTimelines.filter(tl => {
    if (tl.status === 'published') return false;
    const tlTasks = tasks.filter(t => t.timelineId === tl.id);
    if (tlTasks.length === 0) return false;
    return !tlTasks.some(t => t.status === 'needs_info');
  }).length;

  // ══════════════════════════════════════════════════════════════════════
  // IF IN FOCUS MODE (§6) -> RENDER DETAILED TASK TABLE FULL-WIDTH
  // ══════════════════════════════════════════════════════════════════════
  if (focusedAgentId) {
    const focusedAgent = agents.find(a => a.id === focusedAgentId);
    const focusedTimeline = timelines.find(
      t => t.agentId === focusedAgentId && t.plannedDate === activeDay && t.workspaceId === workspace?.id
    );
    const focusedTasks = focusedTimeline 
      ? tasks.filter(t => t.timelineId === focusedTimeline.id).sort((a, b) => a.seq - b.seq)
      : [];

    return (
      <div id="plan-focus-mode-view" className="flex-1 flex flex-col h-full bg-white overflow-hidden select-none">
        {/* Focus Mode Top Banner with Clear "Back to all agents" button (§6) */}
        <div className="h-12 px-4 border-b border-neutral-200 bg-neutral-50 flex items-center justify-between shrink-0">
          <div className="flex items-center gap-3">
            <button
              id="back-to-all-agents-btn"
              type="button"
              onClick={() => onFocusAgent(null)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white border border-neutral-300 hover:border-neutral-400 hover:bg-neutral-100/60 text-neutral-800 rounded-md text-xs font-semibold transition-all shadow-2xs"
            >
              <ArrowLeft className="w-3.5 h-3.5" />
              <span>Back to all agents</span>
            </button>

            <span className="text-neutral-300">|</span>

            <div className="flex items-center gap-2">
              <div 
                className="w-3 h-3 rounded-xs shrink-0 shadow-2xs"
                style={{ backgroundColor: focusedAgent?.color }}
              />
              <span className="text-xs font-semibold text-neutral-900">
                {focusedAgent?.name}
              </span>
              <span className="text-xs text-neutral-500">
                · {formattedDayTitle} (Detailed View)
              </span>
            </div>
          </div>

          {/* Stepper still active in focus mode */}
          <div className="flex items-center gap-1.5">
            <button
              type="button"
              onClick={handlePrevDay}
              disabled={!canGoPrev}
              className={`p-1 rounded border border-neutral-200 bg-white ${
                canGoPrev ? 'hover:bg-neutral-100 text-neutral-700' : 'text-neutral-300 cursor-not-allowed'
              }`}
            >
              <ChevronLeft className="w-3.5 h-3.5" />
            </button>
            <span className="text-xs font-medium text-neutral-700 px-2">
              {formatShortDate(activeDay)}
            </span>
            <button
              type="button"
              onClick={handleNextDay}
              disabled={!canGoNext}
              className={`p-1 rounded border border-neutral-200 bg-white ${
                canGoNext ? 'hover:bg-neutral-100 text-neutral-700' : 'text-neutral-300 cursor-not-allowed'
              }`}
            >
              <ChevronRight className="w-3.5 h-3.5" />
            </button>
          </div>

          {/* Scoped Publish/Reopen for THIS agent's own focused timeline only */}
          {focusedTimeline && (() => {
            const focusedTlTasks = tasks.filter(t => t.timelineId === focusedTimeline.id);
            const readiness = getTimelineReadiness(focusedTimeline, focusedTlTasks, workspace);
            const isFocusPublished = focusedTimeline.status === 'published';
            return (
              <div className="flex items-center">
                {isFocusPublished ? (
                  <button
                    type="button"
                    id="focus-reopen-timeline-btn"
                    onClick={() => onReopenTimeline(focusedTimeline.id)}
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white border border-neutral-300 text-neutral-800 rounded-md text-xs font-medium hover:bg-neutral-50 transition-colors shadow-xs"
                    title="Reopen published timeline for revision (returns to draft)"
                  >
                    <RotateCcw className="w-3.5 h-3.5 text-neutral-600" />
                    Reopen to edit
                  </button>
                ) : (
                  <button
                    type="button"
                    id="focus-publish-timeline-btn"
                    disabled={!readiness.ready}
                    onClick={() => onRequestPublishConfirm(focusedTimeline.id)}
                    title={readiness.ready ? 'Publish this timeline' : readiness.reasons.join(' ')}
                    className={`inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-md text-xs font-medium transition-all shadow-xs ${
                      readiness.ready
                        ? 'bg-neutral-900 text-white hover:bg-neutral-800 active:bg-neutral-950 border border-neutral-900'
                        : 'bg-neutral-100 text-neutral-400 border border-neutral-200 cursor-not-allowed'
                    }`}
                  >
                    <Lock className="w-3.5 h-3.5" />
                    Publish Timeline
                  </button>
                )}
              </div>
            );
          })()}
        </div>

        {/* Existing detailed task table full width (§6) */}
        {focusedTimeline ? (
          <PlanCanvas
            timeline={focusedTimeline}
            tasks={focusedTasks}
            timelinesInWorkspace={timelines.filter(t => t.workspaceId === workspace?.id)}
            activeModalTaskId={null}
            acknowledgedTaskId={null}
            planningWindowStart={planningWindowStart}
            planningWindowEnd={planningWindowEnd}
            onOpenTaskEditModal={onOpenTaskEditModal}
            onOpenTimelineEditModal={() => onOpenTimelineEditModal(focusedTimeline.id)}
            onReorderTasks={(reordered) => onReorderTasksInTimeline(focusedTimeline.id, reordered)}
            onAddTask={(title, start, duration, assignee) => onAddTaskToTimeline(focusedTimeline.id, title, start, duration, assignee)}
            onMoveTaskToBacklog={() => {}}
            onMoveTaskToTimeline={() => {}}
            onDeleteTask={onDeleteTask}
            onReopenTimeline={onReopenTimeline}
            onDropFromBacklog={(taskId, targetIndex) => onMoveTaskToAgentDayTimeline(taskId, focusedTimeline.id, targetIndex)}
            onTimelineTaskDragStart={onTimelineTaskDragStart}
            onTimelineTaskDragEnd={onTimelineTaskDragEnd}
          />
        ) : (
          <div className="flex-1 flex flex-col items-center justify-center p-8 text-center text-neutral-400">
            <p className="text-sm font-medium text-neutral-600 mb-1">
              No timeline planned for {focusedAgent?.name} on {formatShortDate(activeDay)}
            </p>
            <button
              type="button"
              onClick={() => onStartTimelineForAgentDay(focusedAgent!.id, activeDay)}
              className="mt-3 px-3.5 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-medium hover:bg-neutral-800 transition-colors"
            >
              + Create draft timeline for {focusedAgent?.name}
            </button>
          </div>
        )}
      </div>
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // DEFAULT PLAN VIEW: DAY BOARD (Side-by-side agent columns) (§6)
  // ══════════════════════════════════════════════════════════════════════
  return (
    <div id="day-board-view" className="flex-1 flex flex-col h-full bg-neutral-100/60 overflow-hidden select-none">
      {/* Day Bar with Date Stepper & Bulk "Publish Day" (§6, §7) */}
      <div className="h-12 px-4 border-b border-neutral-200 bg-white flex items-center justify-between shrink-0">
        {/* Left zone — flex-1, paired with a flex-1 right zone so the view
            switcher stays pinned at true centre and does not shift when
            you toggle between Plan and Schedule. */}
        <div className="flex-1 flex items-center gap-3 min-w-0">
          <div className="flex items-center gap-1 bg-neutral-100 p-0.5 rounded-md border border-neutral-200">
            <button
              id="dayboard-prev-day-btn"
              type="button"
              onClick={handlePrevDay}
              disabled={!canGoPrev}
              className={`p-1 rounded transition-colors ${
                canGoPrev 
                  ? 'hover:bg-white text-neutral-700 hover:text-neutral-900 cursor-pointer shadow-2xs' 
                  : 'text-neutral-300 cursor-not-allowed'
              }`}
              title={canGoPrev ? 'Previous day' : 'At start of planning window'}
            >
              <ChevronLeft className="w-4 h-4" />
            </button>

            <span className="px-2 text-xs font-bold text-neutral-900 min-w-[140px] text-center font-mono">
              {formattedDayTitle}
            </span>

            <button
              id="dayboard-next-day-btn"
              type="button"
              onClick={handleNextDay}
              disabled={!canGoNext}
              className={`p-1 rounded transition-colors ${
                canGoNext 
                  ? 'hover:bg-white text-neutral-700 hover:text-neutral-900 cursor-pointer shadow-2xs' 
                  : 'text-neutral-300 cursor-not-allowed'
              }`}
              title={canGoNext ? 'Next day' : 'At end of planning window'}
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>

          <span className="text-neutral-300">|</span>

          <span className="text-xs text-neutral-500">
            Day Board · {visibleAgents.length} visible agents
          </span>
        </div>

        {/* Centre: view switcher */}
        <div className="shrink-0">{viewSwitcher}</div>

        {/* Right zone: Build Plan + Bulk "Publish day" Action (§7) */}
        <div className="flex-1 flex items-center justify-end gap-2 min-w-0">
          {buildPlanButton}
          <button
            id="publish-day-bulk-btn"
            type="button"
            onClick={onOpenBulkPublishModal}
            className="w-[161px] flex items-center justify-center gap-1.5 px-3 py-1.5 bg-neutral-900 hover:bg-neutral-800 text-white rounded-md text-xs font-semibold transition-colors shadow-2xs shrink-0"
            title="Publish all ready timelines for this day"
          >
            <Send className="w-3.5 h-3.5" />
            <span>Publish day</span>
            {readyTimelinesCount > 0 && (
              <span className="ml-1 px-1.5 py-0.2 text-[10px] bg-neutral-700 text-white rounded-full">
                {readyTimelinesCount} ready
              </span>
            )}
          </button>
        </div>
      </div>

      {/* Board Columns: Side-by-side agent columns, horizontal scroll (§6) */}
      <div 
        id="day-board-columns-container"
        className="flex-1 overflow-x-auto overflow-y-hidden p-4 flex gap-4 items-start"
      >
        {visibleAgents.length === 0 ? (
          <div className="w-full py-16 text-center text-sm text-neutral-400 bg-white rounded-lg border border-neutral-200">
            All agents are currently hidden. Toggle agent visibility in the roster rail on the left.
          </div>
        ) : (
          visibleAgents.map(agent => {
            const dayLoad = calculateAgentDayLoad(agent, activeDay, timelines, tasks);
            const timeline = dayLoad.timeline;
            const hasTimeline = Boolean(timeline);
            const isColDragOver = dragOverColTimelineId === (timeline?.id || '');

            return (
              <div
                key={agent.id}
                id={`dayboard-col-${agent.id}`}
                className="w-80 min-w-[300px] max-w-[320px] shrink-0 bg-white rounded-lg border border-neutral-200/90 shadow-2xs flex flex-col max-h-full"
                style={{
                  borderTopWidth: '4px',
                  borderTopColor: agent.color,
                }}
              >
                {/* Column Header (§6) */}
                <div className="p-3 border-b border-neutral-200 bg-neutral-50/50 flex flex-col gap-2 shrink-0">
                  <div className="flex items-center justify-between gap-2">
                    {/* Agent Swatch + Name + Marker (Clicking focuses agent!) */}
                    <div 
                      className="flex items-center gap-2 min-w-0 cursor-pointer flex-1 group"
                      onClick={() => onFocusAgent(agent.id)}
                      title={`Click to focus on ${agent.name} (full detailed table)`}
                    >
                      <div 
                        className="w-3 h-3 rounded-xs shrink-0 shadow-2xs"
                        style={{ backgroundColor: agent.color }}
                      />
                      <span className="text-xs font-bold text-neutral-900 truncate group-hover:text-neutral-700">
                        {agent.name}
                      </span>
                      {agent.kind === 'ai' ? (
                        <span className="text-[10px] text-purple-700 font-bold shrink-0">
                          ◆
                        </span>
                      ) : (
                        <span className="text-[9px] text-neutral-400 font-bold shrink-0">
                          ●
                        </span>
                      )}
                    </div>

                    <div className="flex items-center gap-1 shrink-0">
                      {/* Timeline start time — doubles as the entry point to
                          the timeline editor (date + start time). A column
                          *is* a timeline, so this is where it belongs. */}
                      {timeline && (
                        <button
                          type="button"
                          onClick={(e) => { e.stopPropagation(); onOpenTimelineEditModal(timeline.id); }}
                          className="flex items-center gap-0.5 px-1 py-0.5 rounded text-[10px] font-mono text-neutral-500 hover:text-neutral-900 hover:bg-neutral-200/60 transition-colors"
                          title={`Starts ${timeline.startTime} — click to edit planned date & start time`}
                        >
                          <Clock className="w-3 h-3" />
                          {timeline.startTime}
                        </button>
                      )}

                      {/* Focus Icon Shortcut */}
                      <button
                        type="button"
                        onClick={() => onFocusAgent(agent.id)}
                        className="p-1 rounded text-neutral-400 hover:text-neutral-900 hover:bg-neutral-200/50 transition-colors"
                        title="Focus full detailed task table"
                      >
                        <Focus className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>

                  {/* Header Sub-row: Load + Status + Readiness */}
                  <div className="flex items-center justify-between text-[11px] pt-1 border-t border-neutral-200/60">
                    <div className="flex items-center gap-1.5 font-mono">
                      <span className={dayLoad.isOverCapacity ? 'text-amber-700 font-semibold' : 'text-neutral-700 font-medium'}>
                        {dayLoad.hoursFormatted} / {dayLoad.capacityHours}h
                      </span>

                      {dayLoad.isOverCapacity && (
                        <span 
                          className="inline-flex items-center gap-0.5 px-1 py-0.2 text-[9px] font-semibold text-amber-800 bg-amber-100 rounded"
                          title={dayLoad.overCapacityReason}
                        >
                          <AlertTriangle className="w-2.5 h-2.5" />
                          <span>⚠ Over</span>
                        </span>
                      )}
                    </div>

                    {/* Timeline Status */}
                    {timeline ? (
                      <div className="flex items-center gap-1.5">
                        {dayLoad.isBlocked && (
                          <span
                            className="inline-flex items-center gap-0.5 px-1 py-0.2 text-[9px] font-semibold text-red-700 bg-red-100 rounded"
                            title={dayLoad.blockedReason}
                          >
                            <AlertCircle className="w-2.5 h-2.5" />
                            <span>{dayLoad.blockedCount} blocked</span>
                          </span>
                        )}

                        {timeline.status === 'published' ? (
                          <>
                            <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-medium text-neutral-600 bg-neutral-200/70 rounded">
                              <Lock className="w-2.5 h-2.5" />
                              <span>Published</span>
                            </span>
                            <button
                              type="button"
                              id={`col-reopen-btn-${agent.id}`}
                              onClick={(e) => { e.stopPropagation(); onReopenTimeline(timeline.id); }}
                              className="p-0.5 rounded text-neutral-400 hover:text-neutral-800 hover:bg-neutral-200/60 transition-colors"
                              title="Reopen for revision (returns to draft)"
                            >
                              <RotateCcw className="w-3 h-3" />
                            </button>
                          </>
                        ) : (
                          <>
                            <span className="text-[10px] font-medium text-neutral-500">
                              Draft
                            </span>
                            {(() => {
                              const colReadiness = getTimelineReadiness(timeline, dayLoad.tasks, workspace);
                              return (
                                <button
                                  type="button"
                                  id={`col-publish-btn-${agent.id}`}
                                  disabled={!colReadiness.ready}
                                  onClick={(e) => { e.stopPropagation(); onRequestPublishConfirm(timeline.id); }}
                                  className={`p-0.5 rounded transition-colors ${
                                    colReadiness.ready ? 'text-neutral-500 hover:text-neutral-900 hover:bg-neutral-200/60' : 'text-neutral-300 cursor-not-allowed'
                                  }`}
                                  title={colReadiness.ready ? 'Publish this timeline' : colReadiness.reasons.join(' ')}
                                >
                                  <Send className="w-3 h-3" />
                                </button>
                              );
                            })()}
                          </>
                        )}
                      </div>
                    ) : (
                      <span className="text-[10px] text-neutral-400 italic">
                        Empty
                      </span>
                    )}
                  </div>

                  {/* Load Line (§5) */}
                  <div className="w-full h-1 bg-neutral-200 rounded-full overflow-hidden">
                    <div 
                      className={`h-full rounded-full transition-all ${
                        dayLoad.isOverCapacity ? 'bg-amber-500' : 'bg-neutral-800'
                      }`}
                      style={{
                        width: `${Math.min(100, Math.round(dayLoad.loadRatio * 100))}%`,
                      }}
                    />
                  </div>
                </div>

                {/* Column Body: Tasks List (§6) */}
                <div className="flex-1 overflow-y-auto p-2.5 space-y-2 min-h-[220px]">
                  {!hasTimeline || !timeline ? (
                    <button
                      id={`create-timeline-${agent.id}-btn`}
                      type="button"
                      onClick={() => {
                        setPendingAutoAddAgentId(agent.id);
                        onStartTimelineForAgentDay(agent.id, activeDay);
                      }}
                      className="w-full h-full min-h-[160px] flex flex-col items-center justify-center gap-2 py-10 px-4 text-center rounded-md border-2 border-dashed border-neutral-200 text-neutral-500 hover:text-neutral-900 hover:border-neutral-400 hover:bg-neutral-50 transition-colors"
                    >
                      <Plus className="w-4 h-4" />
                      <span className="text-xs font-medium">Add task</span>
                    </button>
                  ) : dayLoad.tasks.length === 0 ? (
                    <button
                      type="button"
                      onClick={() => {
                        setAddingTaskColId(timeline.id);
                        setInlineTitle('');
                        setInlineDuration(30);
                      }}
                      onDragOver={(e) => handleDragOverColumn(e, timeline.id, 0)}
                      onDrop={(e) => handleDropOnColumn(e, timeline, 0)}
                      className={`w-full h-32 border-2 border-dashed rounded-md flex flex-col items-center justify-center gap-1 p-4 text-center transition-colors ${
                        isColDragOver ? 'border-neutral-900 bg-neutral-100' : 'border-neutral-200 text-neutral-500 hover:text-neutral-900 hover:border-neutral-400 hover:bg-neutral-50'
                      }`}
                    >
                      <Plus className="w-4 h-4" />
                      <span className="text-xs font-medium">Add task</span>
                      <span className="text-[10px] text-neutral-400 mt-0.5">
                        or drop tasks from backlog or other columns here
                      </span>
                    </button>
                  ) : (
                    dayLoad.tasks.map((task, index) => {
                      const isTaskLocked = timeline.status === 'published';
                      const isDragSlot = isColDragOver && dragSlotIndex === index;

                      return (
                        <div key={task.id} className="relative">
                          {/* Drop insertion line indicator */}
                          {isDragSlot && (
                            <div className="h-1 bg-neutral-900 rounded-full mb-1.5 transition-all shadow-xs" />
                          )}

                          <div
                            id={`dayboard-task-${task.id}`}
                            draggable={!isTaskLocked}
                            onDragStart={(e) => handleTaskDragStart(e, task.id, timeline.id)}
                            onDragEnd={handleTaskDragEnd}
                            onDragOver={(e) => handleDragOverColumn(e, timeline.id, index)}
                            onDrop={(e) => handleDropOnColumn(e, timeline, index)}
                            onClick={() => onOpenTaskEditModal(task.id)}
                            className={`relative p-2.5 rounded-md border text-xs bg-white transition-all shadow-2xs group cursor-pointer ${
                              isTaskLocked
                                ? 'border-neutral-200 bg-neutral-50/50 hover:bg-neutral-50'
                                : 'border-neutral-200/90 hover:border-neutral-400 hover:bg-neutral-50/40'
                            }`}
                          >
                            {/* Card Header: Seq, Start, Duration */}
                            <div className="flex items-center justify-between gap-1 text-[11px] text-neutral-500 mb-1">
                              <div className="flex items-center gap-1.5 font-mono">
                                {isTaskLocked ? (
                                  <Lock className="w-3 h-3 text-neutral-300 shrink-0" />
                                ) : (
                                  <GripVertical className="w-3 h-3 text-neutral-300 group-hover:text-neutral-500 cursor-grab active:cursor-grabbing shrink-0" />
                                )}
                                <span className="font-semibold text-neutral-900">
                                  #{task.seq}
                                </span>
                                <span className="text-neutral-700">
                                  {task.planned_start || '--:--'}
                                </span>
                                <span className="text-neutral-400">
                                  {task.duration}m
                                </span>
                              </div>

                              {!isTaskLocked && (
                                <button
                                  type="button"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    setActiveTaskMenuId(prev => prev === task.id ? null : task.id);
                                  }}
                                  className="p-0.5 rounded text-neutral-400 hover:text-neutral-800 hover:bg-neutral-200/60 transition-colors shrink-0"
                                  title="Task actions"
                                >
                                  <MoreVertical className="w-3.5 h-3.5" />
                                </button>
                              )}
                            </div>

                            {/* Task Title */}
                            <p className="text-xs font-medium text-neutral-900 leading-snug line-clamp-2">
                              {task.title}
                            </p>

                            {/* Blocked reason: the task's own chip, full reason, never truncated */}
                            {task.status === 'needs_info' && (
                              <div className="mt-1.5 flex items-start gap-1 px-1.5 py-1 text-[10px] font-medium text-red-700 bg-red-50 border border-red-200 rounded">
                                <AlertCircle className="w-2.5 h-2.5 shrink-0 mt-0.5" />
                                <span className="whitespace-normal break-words">
                                  {task.needsInfoReason || 'Missing required information'}
                                </span>
                              </div>
                            )}

                            {/* Per-task actions menu (§ Epic E3): click card = edit; menu = everything else */}
                            {activeTaskMenuId === task.id && !isTaskLocked && (
                              <div
                                className="absolute right-2 top-8 w-44 bg-white border border-neutral-200 rounded-md shadow-lg py-1 z-30 animate-in fade-in zoom-in-95 duration-75"
                                onClick={(e) => e.stopPropagation()}
                              >
                                <button
                                  type="button"
                                  onClick={() => { handleMoveTaskSeq(timeline, index, 'up'); setActiveTaskMenuId(null); }}
                                  disabled={index === 0}
                                  className="w-full px-3 py-1.5 text-xs text-neutral-700 hover:bg-neutral-100 disabled:opacity-30 disabled:hover:bg-transparent flex items-center gap-2 text-left font-medium"
                                >
                                  <ArrowUp className="w-3.5 h-3.5 text-neutral-500" />
                                  Move up
                                </button>
                                <button
                                  type="button"
                                  onClick={() => { handleMoveTaskSeq(timeline, index, 'down'); setActiveTaskMenuId(null); }}
                                  disabled={index === dayLoad.tasks.length - 1}
                                  className="w-full px-3 py-1.5 text-xs text-neutral-700 hover:bg-neutral-100 disabled:opacity-30 disabled:hover:bg-transparent flex items-center gap-2 text-left font-medium"
                                >
                                  <ArrowDown className="w-3.5 h-3.5 text-neutral-500" />
                                  Move down
                                </button>

                                <div className="border-t border-neutral-100 my-1"></div>

                                <button
                                  type="button"
                                  onClick={() => {
                                    setMoveTaskInfo({ taskId: task.id, sourceTimelineId: timeline.id });
                                    setMoveTargetAgentId(agent.id);
                                    setMoveTargetDay(activeDay);
                                    setActiveTaskMenuId(null);
                                  }}
                                  className="w-full px-3 py-1.5 text-xs text-neutral-700 hover:bg-neutral-100 flex items-center gap-2 text-left font-medium"
                                >
                                  <ArrowRightLeft className="w-3.5 h-3.5 text-neutral-500" />
                                  Move…
                                </button>
                                <button
                                  type="button"
                                  onClick={() => { onMoveTaskToBacklog(task.id); setActiveTaskMenuId(null); }}
                                  className="w-full px-3 py-1.5 text-xs text-neutral-700 hover:bg-neutral-100 flex items-center gap-2 text-left font-medium"
                                >
                                  <ArrowDownToLine className="w-3.5 h-3.5 text-neutral-500" />
                                  Return to backlog
                                </button>

                                <div className="border-t border-neutral-100 my-1"></div>

                                <button
                                  type="button"
                                  onClick={() => {
                                    if (confirm(`Delete task "${task.title}"?`)) {
                                      onDeleteTask(task.id);
                                    }
                                    setActiveTaskMenuId(null);
                                  }}
                                  className="w-full px-3 py-1.5 text-xs text-red-600 hover:bg-red-50 flex items-center gap-2 text-left"
                                >
                                  <Trash2 className="w-3.5 h-3.5 text-red-500" />
                                  Delete
                                </button>
                              </div>
                            )}
                          </div>
                        </div>
                      );
                    })
                  )}

                  {/* End of column drop target */}
                  {timeline && timeline.status !== 'published' && dayLoad.tasks.length > 0 && (
                    <div
                      onDragOver={(e) => handleDragOverColumn(e, timeline.id, dayLoad.tasks.length)}
                      onDrop={(e) => handleDropOnColumn(e, timeline, dayLoad.tasks.length)}
                      className={`h-4 rounded transition-all ${
                        isColDragOver && dragSlotIndex === dayLoad.tasks.length
                          ? 'h-6 border border-dashed border-neutral-900 bg-neutral-100'
                          : ''
                      }`}
                    />
                  )}
                </div>

                {/* Column Footer: Inline Add Task or Locked banner (§6) */}
                <div className="p-2 border-t border-neutral-200 bg-neutral-50/70 shrink-0">
                  {timeline ? (
                    timeline.status === 'published' ? (
                      <div className="py-1 text-center text-[11px] text-neutral-400 flex items-center justify-center gap-1 font-medium">
                        <Lock className="w-3 h-3" />
                        <span>(locked — timeline published)</span>
                      </div>
                    ) : addingTaskColId === timeline.id ? (
                      /* Inline Task Creation Form */
                      <div className="p-2 bg-white rounded border border-neutral-300 shadow-xs flex flex-col gap-2">
                        <input
                          type="text"
                          placeholder="Task title..."
                          value={inlineTitle}
                          onChange={(e) => setInlineTitle(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' && inlineTitle.trim()) {
                              onAddTaskToTimeline(timeline.id, inlineTitle.trim(), '09:00', inlineDuration, agent.name);
                              setInlineTitle('');
                              setAddingTaskColId(null);
                            } else if (e.key === 'Escape') {
                              setAddingTaskColId(null);
                            }
                          }}
                          autoFocus
                          className="w-full text-xs p-1.5 border border-neutral-200 rounded focus:outline-none focus:border-neutral-900"
                        />
                        <div className="flex items-center justify-between gap-2 text-[11px]">
                          <div className="flex items-center gap-1">
                            <span className="text-neutral-500">Duration:</span>
                            <select
                              value={inlineDuration}
                              onChange={(e) => setInlineDuration(Number(e.target.value))}
                              className="border border-neutral-200 rounded px-1 py-0.5 bg-white text-xs"
                            >
                              <option value={15}>15m</option>
                              <option value={30}>30m</option>
                              <option value={45}>45m</option>
                              <option value={60}>60m</option>
                              <option value={90}>90m</option>
                              <option value={120}>120m</option>
                            </select>
                          </div>
                          <div className="flex items-center gap-1">
                            <button
                              type="button"
                              onClick={() => setAddingTaskColId(null)}
                              className="px-2 py-0.5 text-neutral-600 hover:text-neutral-900"
                            >
                              Cancel
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                if (inlineTitle.trim()) {
                                  onAddTaskToTimeline(timeline.id, inlineTitle.trim(), '09:00', inlineDuration, agent.name);
                                  setInlineTitle('');
                                  setAddingTaskColId(null);
                                }
                              }}
                              className="px-2.5 py-0.5 bg-neutral-900 text-white rounded font-medium shadow-2xs"
                            >
                              Add
                            </button>
                          </div>
                        </div>
                      </div>
                    ) : (
                      <button
                        type="button"
                        onClick={() => {
                          setAddingTaskColId(timeline.id);
                          setInlineTitle('');
                          setInlineDuration(30);
                        }}
                        className="w-full py-1 text-xs text-neutral-600 hover:text-neutral-900 hover:bg-neutral-200/50 rounded flex items-center justify-center gap-1 font-medium transition-colors"
                      >
                        <Plus className="w-3.5 h-3.5 text-neutral-500" />
                        <span>Add task</span>
                      </button>
                    )
                  ) : null}
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* "Move…" picker: choose a target agent + day for a task already on a timeline */}
      {moveTaskInfo && (() => {
        const sourceTl = timelines.find(t => t.id === moveTaskInfo.sourceTimelineId);
        const task = tasks.find(t => t.id === moveTaskInfo.taskId);
        const existingTarget = timelines.find(t => t.agentId === moveTargetAgentId && t.plannedDate === moveTargetDay);
        const isSameSpot = existingTarget && existingTarget.id === moveTaskInfo.sourceTimelineId;
        const isRefused = existingTarget?.status === 'published' && !isSameSpot;

        return (
          <div
            id="move-task-modal-overlay"
            className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4 animate-in fade-in duration-100"
            onClick={() => setMoveTaskInfo(null)}
          >
            <div
              className="bg-white rounded-lg shadow-xl border border-neutral-200 w-96 p-4 space-y-4 text-xs"
              onClick={(e) => e.stopPropagation()}
            >
              <div>
                <div className="text-[11px] font-semibold text-neutral-400 uppercase tracking-wider">
                  Move Task
                </div>
                <div className="text-sm font-bold text-neutral-900 mt-0.5">
                  Move "{task?.title}" to a different agent/day
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-[11px] font-semibold text-neutral-600 mb-1">Agent:</label>
                  <select
                    value={moveTargetAgentId}
                    onChange={(e) => setMoveTargetAgentId(e.target.value)}
                    className="w-full px-2.5 py-1.5 border border-neutral-300 rounded text-xs focus:outline-none focus:border-neutral-900 bg-white"
                  >
                    {agents.map(a => (
                      <option key={a.id} value={a.id}>{a.name}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-[11px] font-semibold text-neutral-600 mb-1">Day:</label>
                  <select
                    value={moveTargetDay}
                    onChange={(e) => setMoveTargetDay(e.target.value)}
                    className="w-full px-2.5 py-1.5 border border-neutral-300 rounded text-xs focus:outline-none focus:border-neutral-900 bg-white font-mono"
                  >
                    {modalDays.map(d => (
                      <option key={d} value={d}>{formatShortDate(d)}</option>
                    ))}
                  </select>
                </div>
              </div>

              {isRefused && (
                <p className="text-[11px] text-red-600 -mt-2">
                  That agent's timeline on this day is already published and locked. Choose a different agent or day.
                </p>
              )}
              {!existingTarget && (
                <p className="text-[11px] text-neutral-400 -mt-2">
                  No timeline exists yet for this agent/day — one will be created.
                </p>
              )}

              <div className="flex items-center justify-end gap-2 pt-2 border-t border-neutral-100">
                <button
                  type="button"
                  onClick={() => setMoveTaskInfo(null)}
                  className="px-3 py-1.5 text-neutral-600 hover:text-neutral-900 rounded"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  disabled={!moveTargetAgentId || !moveTargetDay || Boolean(isRefused) || isSameSpot}
                  onClick={() => {
                    onMoveTaskToAgentDay(moveTaskInfo.taskId, moveTargetAgentId, moveTargetDay);
                    setMoveTaskInfo(null);
                  }}
                  className="px-3.5 py-1.5 bg-neutral-900 text-white font-medium rounded hover:bg-neutral-800 disabled:opacity-50"
                >
                  Move Task
                </button>
              </div>
            </div>
          </div>
        );
      })()}
    </div>
  );
}
