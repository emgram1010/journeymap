import { useState } from 'react';
import { 
  GripVertical, 
  Clock, 
  Calendar, 
  User, 
  Plus, 
  AlertCircle, 
  Lock,
  ArrowDownToLine,
  MoreHorizontal, 
  Trash2,
  FileText,
  ArrowRight,
  Ban,
  ArrowUp,
  ArrowDown,
  Edit2,
  Sliders
} from 'lucide-react';
import { Timeline, Task } from '../types';
import { isDateOutOfWindow, formatShortDate } from '../utils/dateUtils';

interface PlanCanvasProps {
  timeline: Timeline | null;
  tasks: Task[];
  timelinesInWorkspace: Timeline[];
  activeModalTaskId: string | null;
  acknowledgedTaskId: string | null;
  planningWindowStart: string;
  planningWindowEnd: string;
  onOpenTaskEditModal: (taskId: string) => void;
  onOpenTimelineEditModal: () => void;
  onReorderTasks: (reorderedTasks: Task[]) => void;
  onAddTask: (title: string, plannedStart: string, duration: number, assignee?: string) => void;
  onMoveTaskToBacklog: (taskId: string) => void;
  onMoveTaskToTimeline: (taskId: string, targetTimelineId: string) => void;
  onDeleteTask: (taskId: string) => void;
  onReopenTimeline: (timelineId: string) => void;
  onDropFromBacklog: (taskId: string, targetIndex: number) => void;
  onTimelineTaskDragStart?: (taskId: string) => void;
  onTimelineTaskDragEnd?: () => void;
}

export function PlanCanvas({
  timeline,
  tasks,
  timelinesInWorkspace,
  activeModalTaskId,
  acknowledgedTaskId,
  planningWindowStart,
  planningWindowEnd,
  onOpenTaskEditModal,
  onOpenTimelineEditModal,
  onReorderTasks,
  onAddTask,
  onMoveTaskToBacklog,
  onMoveTaskToTimeline,
  onDeleteTask,
  onReopenTimeline,
  onDropFromBacklog,
  onTimelineTaskDragStart,
  onTimelineTaskDragEnd,
}: PlanCanvasProps) {
  // Drag state
  const [draggedIndex, setDraggedIndex] = useState<number | null>(null);
  const [dragSlotIndex, setDragSlotIndex] = useState<number | null>(null);
  const [isDraggingBacklog, setIsDraggingBacklog] = useState(false);

  // Inline add state
  const [isAddingInline, setIsAddingInline] = useState(false);
  const [inlineTitle, setInlineTitle] = useState('');
  const [inlineDuration, setInlineDuration] = useState(30);

  // Row menu state
  const [menuTaskId, setMenuTaskId] = useState<string | null>(null);

  // Keyboard announcement banner
  const [reorderAnnouncement, setReorderAnnouncement] = useState<string | null>(null);

  // Compute default next start time from previous task
  const getNextStartTime = () => {
    if (tasks.length === 0) return '09:00';
    const lastTask = tasks[tasks.length - 1];
    if (!lastTask.planned_start) return '10:00';
    try {
      const [h, m] = lastTask.planned_start.split(':').map(Number);
      const totalMin = h * 60 + m + (lastTask.duration || 30);
      const nextH = Math.floor(totalMin / 60) % 24;
      const nextM = totalMin % 60;
      return `${String(nextH).padStart(2, '0')}:${String(nextM).padStart(2, '0')}`;
    } catch {
      return '10:00';
    }
  };

  const [inlineStart, setInlineStart] = useState(getNextStartTime());

  if (!timeline) {
    return (
      <main 
        id="plan-canvas-empty"
        className="flex-1 flex flex-col items-center justify-center p-8 text-neutral-400 bg-white select-none"
      >
        <Calendar className="w-10 h-10 text-neutral-300 mb-3 stroke-1" />
        <p className="text-sm font-medium text-neutral-600">No timeline selected</p>
        <p className="text-xs text-neutral-400 mt-1">Select a timeline from the rail or create a new one to begin planning.</p>
      </main>
    );
  }

  const isLocked = timeline.status === 'published';
  const isOutOfWindow = isDateOutOfWindow(timeline.plannedDate, planningWindowStart, planningWindowEnd);

  // Calculate total duration
  const totalMinutes = tasks.reduce((sum, t) => sum + (Number(t.duration) || 0), 0);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  const formattedDuration = hours > 0 ? `${hours}h ${minutes > 0 ? `${minutes}m` : ''}` : `${minutes}m`;

  const needsInfoTasks = tasks.filter(t => t.status === 'needs_info');

  // Drag handlers for reordering within timeline
  const handleDragStart = (e: React.DragEvent, index: number, taskId: string) => {
    if (isLocked) return;
    setDraggedIndex(index);
    setIsDraggingBacklog(false);
    const payload = JSON.stringify({ type: 'timeline-task', taskId, index });
    e.dataTransfer.setData('text/plain', payload);
    e.dataTransfer.setData('application/json', payload);
    e.dataTransfer.effectAllowed = 'move';
    onTimelineTaskDragStart?.(taskId);
  };

  const handleDragOverRow = (e: React.DragEvent, index: number) => {
    e.preventDefault();
    if (isLocked) return;

    // Detect if top half or bottom half of the row
    const rect = e.currentTarget.getBoundingClientRect();
    const midY = rect.top + rect.height / 2;
    const targetSlot = e.clientY < midY ? index : index + 1;

    if (dragSlotIndex !== targetSlot) {
      setDragSlotIndex(targetSlot);
    }
  };

  const handleDropOnSlot = (e: React.DragEvent, slot: number) => {
    e.preventDefault();
    setDragSlotIndex(null);
    setIsDraggingBacklog(false);

    if (isLocked) return;

    try {
      const dataStr = e.dataTransfer.getData('application/json') || e.dataTransfer.getData('text/plain');
      if (!dataStr) return;
      const data = JSON.parse(dataStr);

      if (data.type === 'backlog-task') {
        // Section 3.A & 3.B: Land backlog task at slot
        onDropFromBacklog(data.taskId, slot);
      } else if (data.type === 'timeline-task' && draggedIndex !== null) {
        // Reordering existing tasks
        if (draggedIndex === slot || draggedIndex === slot - 1) return;

        const updated = [...tasks];
        const [moved] = updated.splice(draggedIndex, 1);
        const adjustedSlot = draggedIndex < slot ? slot - 1 : slot;
        updated.splice(adjustedSlot, 0, moved);

        const resequenced = updated.map((t, idx) => ({
          ...t,
          seq: idx + 1,
        }));
        onReorderTasks(resequenced);
      }
    } catch (err) {
      console.error('Failed to parse drag payload:', err);
    } finally {
      setDraggedIndex(null);
      onTimelineTaskDragEnd?.();
    }
  };

  const handleDragEnd = () => {
    setDraggedIndex(null);
    setDragSlotIndex(null);
    setIsDraggingBacklog(false);
    onTimelineTaskDragEnd?.();
  };

  // Keyboard reordering handlers (Section 5)
  const handleKeyboardMove = (index: number, direction: 'up' | 'down') => {
    if (isLocked) return;
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= tasks.length) return;

    const updated = [...tasks];
    const [moved] = updated.splice(index, 1);
    updated.splice(targetIndex, 0, moved);

    const resequenced = updated.map((t, idx) => ({
      ...t,
      seq: idx + 1,
    }));
    onReorderTasks(resequenced);

    const announcement = `Moved step "${moved.title}" to position #${targetIndex + 1}`;
    setReorderAnnouncement(announcement);
    setTimeout(() => setReorderAnnouncement(null), 3000);
  };

  // Submit inline add
  const handleInlineSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!inlineTitle.trim()) return;

    onAddTask(inlineTitle.trim(), inlineStart, inlineDuration);
    setInlineTitle('');
    // auto-advance time for next one
    const [h, m] = inlineStart.split(':').map(Number);
    const totalMin = h * 60 + m + inlineDuration;
    const nextH = Math.floor(totalMin / 60) % 24;
    const nextM = totalMin % 60;
    setInlineStart(`${String(nextH).padStart(2, '0')}:${String(nextM).padStart(2, '0')}`);
  };

  return (
    <main 
      id="plan-canvas"
      className="flex-1 flex flex-col h-full bg-white overflow-hidden select-none relative"
    >
      {/* Sub-header / Timeline Details Context Strip */}
      <div 
        id="timeline-meta-bar"
        className="h-11 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50/50 shrink-0"
      >
        <div className="flex items-center gap-4 text-xs">
          <button
            id="meta-bar-timeline-edit-btn"
            onClick={onOpenTimelineEditModal}
            className="flex items-center gap-3 px-2 py-1 -ml-2 rounded-md hover:bg-neutral-200/60 transition-colors group cursor-pointer text-left"
            title="Click to edit timeline date and assignee"
          >
            <div className="flex items-center gap-1.5 text-neutral-600 group-hover:text-neutral-900">
              <Calendar className="w-3.5 h-3.5 text-neutral-400 group-hover:text-neutral-700" />
              <span className="font-medium text-neutral-800 underline decoration-dotted decoration-neutral-400 underline-offset-2">{timeline.plannedDate}</span>
              {isOutOfWindow && (
                <span className="ml-1 px-1.5 py-0.2 rounded bg-red-50 text-red-700 border border-red-200 text-[10px] font-semibold">
                  Out of window
                </span>
              )}
            </div>

            <div className="h-3 w-px bg-neutral-200"></div>

            <div className="flex items-center gap-1.5 text-neutral-600 group-hover:text-neutral-900" title="Default assignee for tasks in this timeline">
              <User className="w-3.5 h-3.5 text-neutral-400 group-hover:text-neutral-700" />
              <span>Assignee:</span>
              <span className="font-medium text-neutral-800 underline decoration-dotted decoration-neutral-400 underline-offset-2">{timeline.assignee || 'Unassigned'}</span>
            </div>
          </button>

          <div className="h-3 w-px bg-neutral-200"></div>

          <div className="flex items-center gap-1.5 text-neutral-600">
            <Clock className="w-3.5 h-3.5 text-neutral-400" />
            <span>Planned Run:</span>
            <span className="font-medium font-mono text-neutral-800">{formattedDuration}</span>
          </div>
        </div>

        {/* Readiness Count & Out of Window Alert */}
        <div className="flex items-center gap-2 text-xs">
          {isOutOfWindow && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-red-50 text-red-800 border border-red-200 text-[11px] font-medium">
              <AlertCircle className="w-3 h-3 text-red-600" />
              Date outside window ({formatShortDate(planningWindowStart)} – {formatShortDate(planningWindowEnd)})
            </span>
          )}

          {/* Story B1/B2: silence means ready — the only summary signal
              left here is the blocked count (this view's "column header"
              equivalent); the "All N planned" chip is gone entirely. */}
          {needsInfoTasks.length > 0 && (
            <span className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-red-50 text-red-800 border border-red-200 text-[11px] font-medium">
              <AlertCircle className="w-3 h-3 text-red-600" />
              {needsInfoTasks.length} blocked
            </span>
          )}
        </div>
      </div>

      {/* Accessible Keyboard Reorder Announcement */}
      {reorderAnnouncement && (
        <div className="bg-neutral-900 text-white text-xs px-4 py-1.5 text-center font-medium animate-in fade-in duration-75 shrink-0">
          {reorderAnnouncement}
        </div>
      )}

      {/* Published Locked Notice (Section 3.F). Story B3: exactly one
          "Reopen to edit" control per view — Focus mode's already lives in
          DayBoard's top banner above this canvas, so this notice is
          informational only and doesn't duplicate it. */}
      {isLocked && (
        <div
          id="published-lock-banner"
          className="bg-neutral-900 text-neutral-100 px-6 py-2.5 flex items-center gap-2 text-xs shrink-0"
        >
          <Lock className="w-4 h-4 text-emerald-400" />
          <span>
            <strong>Timeline Published (Locked).</strong> Tasks and sequencing are read-only.
          </span>
        </div>
      )}

      {/* Main Task List Table / Canvas */}
      <div 
        id="task-sequence-list"
        className="flex-1 overflow-y-auto p-6"
        onDragOver={(e) => {
          e.preventDefault();
          e.dataTransfer.dropEffect = isLocked ? 'none' : 'move';
        }}
        onDrop={(e) => {
          if (dragSlotIndex === null && !isLocked) {
            handleDropOnSlot(e, tasks.length);
          }
        }}
      >
        {/* Table Header */}
        <div className="grid grid-cols-[36px_40px_80px_70px_1fr_160px_140px_70px] items-center gap-2 px-3 py-2 text-[11px] font-semibold text-neutral-400 uppercase tracking-wider border-b border-neutral-200 mb-1">
          <span></span>
          <span>Seq</span>
          <span>Start</span>
          <span>Duration</span>
          <span>Task Title</span>
          <span>Assignee</span>
          <span>Readiness</span>
          <span></span>
        </div>

        {tasks.length === 0 ? (
          <div 
            onDragOver={(e) => {
              e.preventDefault();
              if (dragSlotIndex !== 0) setDragSlotIndex(0);
            }}
            onDrop={(e) => handleDropOnSlot(e, 0)}
            className={`py-16 text-center border rounded-lg my-4 transition-all ${
              dragSlotIndex === 0
                ? 'border-neutral-900 bg-neutral-50 ring-2 ring-neutral-900/10'
                : 'border-dashed border-neutral-200 bg-neutral-50/50'
            }`}
          >
            <p className="text-sm font-medium text-neutral-600">No tasks in this timeline</p>
            <p className="text-xs text-neutral-400 mt-1 max-w-sm mx-auto">
              Drop an unplanned task from the backlog here, or use the inline row below to add tasks sequentially.
            </p>
          </div>
        ) : (
          <div className="space-y-1 relative">
            {tasks.map((task, index) => {
              const isSelected = task.id === activeModalTaskId;
              const isAcknowledged = task.id === acknowledgedTaskId;
              const isDragging = draggedIndex === index;
              const isInheritedAssignee = !task.assignee;
              const effectiveAssignee = task.assignee || timeline.assignee || 'Unassigned';

              // Section 3.A: Preview shift in seq badges during drag!
              // If dragging into slot <= index, this row previews as index + 2 (shifted down by 1)
              let displaySeq = task.seq;
              let isPreviewingShift = false;
              if (dragSlotIndex !== null && dragSlotIndex <= index) {
                displaySeq = task.seq + 1;
                isPreviewingShift = true;
              }

              const isSlotAbove = dragSlotIndex === index;

              return (
                <div key={task.id} className="relative">
                  {/* Section 3.A: Drop Indicator bar above row */}
                  {isSlotAbove && !isLocked && (
                    <div 
                      id={`drop-indicator-${index}`}
                      className="h-1 bg-neutral-900 rounded-full my-1 shadow-xs animate-pulse flex items-center justify-between px-2"
                    >
                      <span className="text-[9px] bg-neutral-900 text-white font-mono px-1 rounded -translate-y-3 font-semibold">
                        Slot #{index + 1}
                      </span>
                    </div>
                  )}

                  {/* Task Row */}
                  <div
                    id={`task-row-${task.id}`}
                    tabIndex={0}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        onOpenTaskEditModal(task.id);
                      } else if (e.altKey && e.key === 'ArrowUp') {
                        e.preventDefault();
                        handleKeyboardMove(index, 'up');
                      } else if (e.altKey && e.key === 'ArrowDown') {
                        e.preventDefault();
                        handleKeyboardMove(index, 'down');
                      }
                    }}
                    draggable={!isLocked}
                    onDragStart={(e) => handleDragStart(e, index, task.id)}
                    onDragOver={(e) => handleDragOverRow(e, index)}
                    onDrop={(e) => handleDropOnSlot(e, dragSlotIndex ?? index)}
                    onDragEnd={handleDragEnd}
                    onClick={() => onOpenTaskEditModal(task.id)}
                    className={`grid grid-cols-[36px_40px_80px_70px_1fr_160px_140px_70px] items-center gap-2 px-3 py-2.5 rounded-lg border text-xs cursor-pointer transition-all focus:outline-none focus:ring-1 focus:ring-neutral-900 ${
                      isAcknowledged
                        ? 'bg-emerald-50/70 border-emerald-400 ring-2 ring-emerald-500/20 shadow-xs'
                        : isSelected
                        ? 'bg-neutral-100/80 border-neutral-400 shadow-xs ring-1 ring-neutral-900/10'
                        : 'bg-white border-neutral-200/90 hover:border-neutral-300 hover:bg-neutral-50/50'
                    } ${isDragging ? 'opacity-25 border-dashed border-neutral-400' : ''}`}
                  >
                    {/* Drag Grip Handle */}
                    <div 
                      className="flex items-center justify-center cursor-grab active:cursor-grabbing"
                      onClick={(e) => e.stopPropagation()}
                    >
                      {!isLocked ? (
                        <GripVertical className="w-4 h-4 text-neutral-400 hover:text-neutral-700 pointer-events-none" />
                      ) : (
                        <Lock className="w-3.5 h-3.5 text-neutral-300" />
                      )}
                    </div>

                    {/* Seq # with shift preview */}
                    <div 
                      className={`font-mono font-semibold text-center py-0.5 rounded text-[11px] transition-all ${
                        isPreviewingShift
                          ? 'bg-neutral-900 text-white font-bold scale-105 shadow-2xs'
                          : 'bg-neutral-100/90 text-neutral-600'
                      }`}
                      title={isPreviewingShift ? `Previews as #${displaySeq} on drop` : `Sequence #${displaySeq}`}
                    >
                      #{displaySeq}
                    </div>

                    {/* Planned Start Time */}
                    <div className="font-mono text-neutral-700 flex items-center gap-1 font-medium">
                      <Clock className="w-3 h-3 text-neutral-400 shrink-0" />
                      <span className={task.planned_start ? '' : 'text-amber-700 font-semibold'}>
                        {task.planned_start || 'None'}
                      </span>
                    </div>

                    {/* Duration */}
                    <div className="font-mono text-neutral-600 bg-neutral-100 px-1.5 py-0.5 rounded text-center text-[11px] w-fit font-medium">
                      {task.duration}m
                    </div>

                    {/* Title & Notes snippet */}
                    <div className="min-w-0 pr-2">
                      <div className="font-medium text-neutral-900 truncate">
                        {task.title}
                      </div>
                      {task.notes && (
                        <div className="text-[11px] text-neutral-400 truncate flex items-center gap-1 mt-0.5">
                          <FileText className="w-2.5 h-2.5 shrink-0" />
                          <span>{task.notes}</span>
                        </div>
                      )}
                    </div>

                    {/* Effective Assignee */}
                    <div className="truncate flex items-center gap-1.5 text-neutral-600">
                      <User className="w-3 h-3 text-neutral-400 shrink-0" />
                      <span className="truncate">{effectiveAssignee}</span>
                      {isInheritedAssignee && (
                        <span className="text-[10px] text-neutral-400 italic shrink-0" title="Inherited from timeline default">
                          (inherited)
                        </span>
                      )}
                    </div>

                    {/* Blocked reason: the task's own chip, full reason, never
                        truncated (Story B2). Ready tasks show nothing (B1). */}
                    <div>
                      {task.status === 'needs_info' && (
                        <div
                          className="inline-flex items-start gap-1 px-2 py-0.5 rounded bg-red-50 text-red-800 border border-red-200 text-[10px] font-semibold whitespace-normal break-words"
                          title={task.needsInfoReason || 'Missing required planning information'}
                        >
                          <AlertCircle className="w-2.5 h-2.5 text-red-600 shrink-0 mt-0.5" />
                          <span>{task.needsInfoReason || 'Needs info'}</span>
                        </div>
                      )}
                    </div>

                    {/* Row Actions Menu & Keyboard reorder buttons */}
                    <div className="relative flex items-center justify-end gap-1" onClick={(e) => e.stopPropagation()}>
                      {!isLocked && (
                        <>
                          {/* Keyboard Move Up / Down Buttons (Section 5) */}
                          <div className="hidden group-hover:flex items-center gap-0.5">
                            <button
                              onClick={() => handleKeyboardMove(index, 'up')}
                              disabled={index === 0}
                              className="p-1 text-neutral-400 hover:text-neutral-800 disabled:opacity-30 rounded"
                              title="Move step earlier (Alt+Up)"
                            >
                              <ArrowUp className="w-3 h-3" />
                            </button>
                            <button
                              onClick={() => handleKeyboardMove(index, 'down')}
                              disabled={index === tasks.length - 1}
                              className="p-1 text-neutral-400 hover:text-neutral-800 disabled:opacity-30 rounded"
                              title="Move step later (Alt+Down)"
                            >
                              <ArrowDown className="w-3 h-3" />
                            </button>
                          </div>

                          <button
                            onClick={() => setMenuTaskId(menuTaskId === task.id ? null : task.id)}
                            className="p-1 rounded hover:bg-neutral-200/60 text-neutral-400 hover:text-neutral-700 transition-colors"
                            title="Task actions"
                          >
                            <MoreHorizontal className="w-3.5 h-3.5" />
                          </button>

                          {menuTaskId === task.id && (
                            <div 
                              className="absolute right-0 top-full mt-1 w-48 bg-white border border-neutral-200 rounded-md shadow-lg py-1 z-30 animate-in fade-in zoom-in-95 duration-75"
                              onClick={(e) => e.stopPropagation()}
                            >
                              <button
                                onClick={() => {
                                  onOpenTaskEditModal(task.id);
                                  setMenuTaskId(null);
                                }}
                                className="w-full px-3 py-1.5 text-xs text-neutral-700 hover:bg-neutral-100 flex items-center gap-2 text-left font-medium"
                              >
                                <Edit2 className="w-3.5 h-3.5 text-neutral-500" />
                                Edit task
                              </button>

                              <div className="border-t border-neutral-100 my-1"></div>

                              {/* Section 5: Return to backlog */}
                              <button
                                onClick={() => {
                                  onMoveTaskToBacklog(task.id);
                                  setMenuTaskId(null);
                                }}
                                className="w-full px-3 py-1.5 text-xs text-neutral-700 hover:bg-neutral-100 flex items-center gap-2 text-left font-medium"
                              >
                                <ArrowDownToLine className="w-3.5 h-3.5 text-neutral-500" />
                                Return to backlog
                              </button>

                              {timelinesInWorkspace.filter(t => t.id !== timeline.id).length > 0 && (
                                <div className="border-t border-neutral-100 my-1">
                                  <div className="px-3 py-1 text-[10px] font-semibold text-neutral-400 uppercase tracking-wider">
                                    Move to Timeline
                                  </div>
                                  {timelinesInWorkspace
                                    .filter(t => t.id !== timeline.id)
                                    .map(tl => (
                                      <button
                                        key={tl.id}
                                        onClick={() => {
                                          onMoveTaskToTimeline(task.id, tl.id);
                                          setMenuTaskId(null);
                                        }}
                                        className="w-full px-3 py-1 text-xs text-neutral-700 hover:bg-neutral-100 flex items-center gap-1.5 text-left truncate"
                                      >
                                        <ArrowRight className="w-3 h-3 text-neutral-400 shrink-0" />
                                        <span className="truncate">{tl.name}</span>
                                      </button>
                                    ))}
                                </div>
                              )}

                              <div className="border-t border-neutral-100 my-1"></div>

                              <button
                                onClick={() => {
                                  if (confirm(`Delete task "${task.title}"?`)) {
                                    onDeleteTask(task.id);
                                  }
                                  setMenuTaskId(null);
                                }}
                                className="w-full px-3 py-1.5 text-xs text-red-600 hover:bg-red-50 flex items-center gap-2 text-left"
                              >
                                <Trash2 className="w-3.5 h-3.5 text-red-500" />
                                Delete Task
                              </button>
                            </div>
                          )}
                        </>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}

            {/* Drop Indicator if slot is at the very end */}
            {dragSlotIndex === tasks.length && !isLocked && (
              <div 
                id="drop-indicator-end"
                className="h-1 bg-neutral-900 rounded-full my-1 shadow-xs animate-pulse flex items-center justify-between px-2"
              >
                <span className="text-[9px] bg-neutral-900 text-white font-mono px-1 rounded -translate-y-3 font-semibold">
                  Slot #{tasks.length + 1} (End)
                </span>
              </div>
            )}
          </div>
        )}

        {/* Section 3.B: Dropping below or onto "+ Add Task to Timeline" row */}
        {!isLocked && (
          <div 
            className="mt-3"
            onDragOver={(e) => {
              e.preventDefault();
              if (dragSlotIndex !== tasks.length) {
                setDragSlotIndex(tasks.length);
              }
            }}
            onDrop={(e) => handleDropOnSlot(e, tasks.length)}
          >
            {isAddingInline ? (
              <form 
                onSubmit={handleInlineSubmit}
                className="grid grid-cols-[36px_40px_80px_70px_1fr_auto] items-center gap-2 px-3 py-2.5 rounded-lg border border-neutral-300 bg-neutral-50/70 text-xs shadow-xs"
              >
                <div className="flex justify-center text-neutral-400">
                  <Plus className="w-4 h-4" />
                </div>

                <div className="font-mono text-center text-neutral-400 text-[11px]">
                  #{tasks.length + 1}
                </div>

                {/* Start Time Input */}
                <input
                  type="time"
                  value={inlineStart}
                  onChange={(e) => setInlineStart(e.target.value)}
                  className="px-1.5 py-1 text-xs border border-neutral-300 rounded font-mono bg-white"
                />

                {/* Duration Input */}
                <div className="flex items-center gap-1">
                  <input
                    type="number"
                    min="5"
                    step="5"
                    value={inlineDuration}
                    onChange={(e) => setInlineDuration(Number(e.target.value))}
                    className="w-14 px-1 py-1 text-xs border border-neutral-300 rounded font-mono text-center bg-white"
                  />
                  <span className="text-[10px] text-neutral-400">m</span>
                </div>

                {/* Title Input */}
                <input
                  type="text"
                  placeholder="Task title (e.g., Validate database schemas)..."
                  value={inlineTitle}
                  onChange={(e) => setInlineTitle(e.target.value)}
                  className="w-full px-2.5 py-1 text-xs border border-neutral-300 rounded bg-white focus:outline-none focus:border-neutral-900"
                  autoFocus
                />

                {/* Actions */}
                <div className="flex items-center gap-1.5 pl-2">
                  <button
                    type="button"
                    onClick={() => setIsAddingInline(false)}
                    className="px-2 py-1 text-xs text-neutral-600 hover:text-neutral-900 rounded"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={!inlineTitle.trim()}
                    className="px-3 py-1 bg-neutral-900 text-white rounded text-xs font-medium hover:bg-neutral-800 disabled:opacity-50"
                  >
                    Add Task
                  </button>
                </div>
              </form>
            ) : (
              <button
                id="inline-add-task-btn"
                onClick={() => {
                  setInlineStart(getNextStartTime());
                  setIsAddingInline(true);
                }}
                className={`w-full py-2.5 px-4 border rounded-lg text-xs font-medium flex items-center justify-center gap-2 transition-all ${
                  dragSlotIndex === tasks.length
                    ? 'border-neutral-900 bg-neutral-100/90 text-neutral-900 ring-1 ring-neutral-900/10'
                    : 'border-dashed border-neutral-300 text-neutral-600 hover:text-neutral-900 hover:border-neutral-400 hover:bg-neutral-50'
                }`}
              >
                <Plus className="w-3.5 h-3.5" />
                <span>Add Task to Timeline (or drop backlog task to append)</span>
              </button>
            )}
          </div>
        )}
      </div>
    </main>
  );
}
