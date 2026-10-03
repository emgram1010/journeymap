import { useState, useEffect } from 'react';
import { 
  X, 
  ArrowUp, 
  ArrowDown, 
  Trash2, 
  Clock, 
  User, 
  Calendar, 
  FileText, 
  AlertCircle, 
  CheckCircle2, 
  Lock, 
  RotateCcw, 
  ArrowRight, 
  ArrowDownToLine,
  Sliders,
  Sparkles
} from 'lucide-react';
import { Task, Timeline, SelectedEntity, TaskPlanningStatus } from '../types';

interface InspectorProps {
  isOpen: boolean;
  selectedEntity: SelectedEntity;
  activeTimeline: Timeline | null;
  timelinesInWorkspace: Timeline[];
  tasksInTimeline: Task[];
  allTasksInWorkspace: Task[];
  onClose: () => void;
  onUpdateTask: (taskId: string, updates: Partial<Task>) => void;
  onUpdateTimeline: (timelineId: string, updates: Partial<Timeline>) => void;
  onMoveTaskSeq: (taskId: string, direction: 'up' | 'down') => void;
  onMoveTaskToTimeline: (taskId: string, targetTimelineId: string | null) => void;
  onDeleteTask: (taskId: string) => void;
  onDeleteTimeline: (timelineId: string) => void;
  onPublishTimeline: (timelineId: string) => void;
  onReopenTimeline: (timelineId: string) => void;
}

export function Inspector({
  isOpen,
  selectedEntity,
  activeTimeline,
  timelinesInWorkspace,
  tasksInTimeline,
  allTasksInWorkspace,
  onClose,
  onUpdateTask,
  onUpdateTimeline,
  onMoveTaskSeq,
  onMoveTaskToTimeline,
  onDeleteTask,
  onDeleteTimeline,
  onPublishTimeline,
  onReopenTimeline,
}: InspectorProps) {
  if (!isOpen) return null;

  // Determine which task or timeline to display
  let selectedTask: Task | null = null;
  if (selectedEntity?.type === 'task') {
    selectedTask = allTasksInWorkspace.find(t => t.id === selectedEntity.id) || null;
  }

  const isTimelineView = !selectedTask || selectedEntity?.type === 'timeline';

  return (
    <aside 
      id="inspector-panel"
      className="w-[320px] shrink-0 bg-white border-l border-neutral-200 flex flex-col h-full select-none shadow-xs z-10"
    >
      {/* Inspector Header */}
      <div className="h-11 px-4 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
        <div className="flex items-center gap-2">
          <Sliders className="w-3.5 h-3.5 text-neutral-500" />
          <span className="text-xs font-semibold text-neutral-800">
            {isTimelineView ? 'Timeline Inspector' : 'Task Inspector'}
          </span>
          {selectedTask && (
            <span className="text-[11px] font-mono text-neutral-600 bg-neutral-200/80 px-1.5 py-0.2 rounded font-medium">
              #{selectedTask.seq}
            </span>
          )}
        </div>

        <button
          id="close-inspector-btn"
          onClick={onClose}
          className="p-1 rounded text-neutral-400 hover:text-neutral-800 hover:bg-neutral-200/60 transition-colors"
          title="Close Inspector"
          aria-label="Close inspector"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Inspector Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-5 text-xs">
        {selectedTask ? (
          <TaskInspectorBody
            task={selectedTask}
            timeline={activeTimeline}
            timelinesInWorkspace={timelinesInWorkspace}
            tasksInTimeline={tasksInTimeline}
            onUpdateTask={onUpdateTask}
            onMoveTaskSeq={onMoveTaskSeq}
            onMoveTaskToTimeline={onMoveTaskToTimeline}
            onDeleteTask={onDeleteTask}
          />
        ) : activeTimeline ? (
          <TimelineInspectorBody
            timeline={activeTimeline}
            tasksInTimeline={tasksInTimeline}
            onUpdateTimeline={onUpdateTimeline}
            onDeleteTimeline={onDeleteTimeline}
            onPublishTimeline={onPublishTimeline}
            onReopenTimeline={onReopenTimeline}
          />
        ) : (
          <div className="py-8 text-center text-neutral-400">
            Select a timeline or task to view details.
          </div>
        )}
      </div>
    </aside>
  );
}

interface TaskInspectorBodyProps {
  task: Task;
  timeline: Timeline | null;
  timelinesInWorkspace: Timeline[];
  tasksInTimeline: Task[];
  onUpdateTask: (taskId: string, updates: Partial<Task>) => void;
  onMoveTaskSeq: (taskId: string, direction: 'up' | 'down') => void;
  onMoveTaskToTimeline: (taskId: string, targetTimelineId: string | null) => void;
  onDeleteTask: (taskId: string) => void;
}

function TaskInspectorBody({
  task,
  timeline,
  timelinesInWorkspace,
  tasksInTimeline,
  onUpdateTask,
  onMoveTaskSeq,
  onMoveTaskToTimeline,
  onDeleteTask,
}: TaskInspectorBodyProps) {
  const isLocked = timeline?.status === 'published';
  const currentIndex = tasksInTimeline.findIndex(t => t.id === task.id);
  const canMoveUp = currentIndex > 0;
  const canMoveDown = currentIndex >= 0 && currentIndex < tasksInTimeline.length - 1;

  const durationPresets = [15, 30, 45, 60, 90];

  return (
    <div className="space-y-4">
      {/* Title Field */}
      <div>
        <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider mb-1">
          Task Title
        </label>
        <input
          id="inspector-task-title-input"
          type="text"
          disabled={isLocked}
          value={task.title}
          onChange={(e) => onUpdateTask(task.id, { title: e.target.value })}
          className="w-full px-2.5 py-1.5 text-xs font-medium text-neutral-900 border border-neutral-300 rounded focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100 disabled:text-neutral-500"
        />
      </div>

      {/* Sequence Reordering (Only for scheduled tasks) */}
      {task.timelineId && (
        <div className="bg-neutral-50 p-2.5 rounded-lg border border-neutral-200 flex items-center justify-between">
          <div>
            <div className="text-[11px] font-medium text-neutral-600">Sequence Position</div>
            <div className="font-mono text-xs font-bold text-neutral-900">
              Step {task.seq} of {tasksInTimeline.length}
            </div>
          </div>
          {!isLocked && (
            <div className="flex items-center gap-1">
              <button
                id="inspector-move-up-btn"
                disabled={!canMoveUp}
                onClick={() => onMoveTaskSeq(task.id, 'up')}
                className="p-1 rounded border border-neutral-300 bg-white hover:bg-neutral-100 disabled:opacity-40 text-neutral-700 transition-colors"
                title="Move step earlier"
              >
                <ArrowUp className="w-3.5 h-3.5" />
              </button>
              <button
                id="inspector-move-down-btn"
                disabled={!canMoveDown}
                onClick={() => onMoveTaskSeq(task.id, 'down')}
                className="p-1 rounded border border-neutral-300 bg-white hover:bg-neutral-100 disabled:opacity-40 text-neutral-700 transition-colors"
                title="Move step later"
              >
                <ArrowDown className="w-3.5 h-3.5" />
              </button>
            </div>
          )}
        </div>
      )}

      {/* Time & Duration Fields */}
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider mb-1">
            Planned Start
          </label>
          <div className="relative">
            <input
              id="inspector-task-start-input"
              type="time"
              disabled={isLocked}
              value={task.planned_start}
              onChange={(e) => onUpdateTask(task.id, { planned_start: e.target.value })}
              className="w-full px-2.5 py-1.5 text-xs font-mono text-neutral-900 border border-neutral-300 rounded focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100"
            />
          </div>
        </div>

        <div>
          <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider mb-1">
            Duration (min)
          </label>
          <input
            id="inspector-task-duration-input"
            type="number"
            min="5"
            step="5"
            disabled={isLocked}
            value={task.duration}
            onChange={(e) => onUpdateTask(task.id, { duration: Math.max(5, Number(e.target.value)) })}
            className="w-full px-2.5 py-1.5 text-xs font-mono text-neutral-900 border border-neutral-300 rounded focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100"
          />
        </div>
      </div>

      {/* Duration Quick Presets */}
      {!isLocked && (
        <div className="flex items-center gap-1.5">
          <span className="text-[10px] text-neutral-400">Presets:</span>
          {durationPresets.map(preset => (
            <button
              key={preset}
              type="button"
              onClick={() => onUpdateTask(task.id, { duration: preset })}
              className={`px-1.5 py-0.5 rounded text-[10px] font-mono transition-colors ${
                task.duration === preset
                  ? 'bg-neutral-900 text-white font-medium'
                  : 'bg-neutral-100 hover:bg-neutral-200 text-neutral-700'
              }`}
            >
              {preset}m
            </button>
          ))}
        </div>
      )}

      {/* Assignee Field with Inheritance */}
      <div>
        <div className="flex items-center justify-between mb-1">
          <label className="text-[11px] font-semibold text-neutral-500 uppercase tracking-wider">
            Assignee
          </label>
          {timeline && !task.assignee && (
            <span className="text-[10px] text-neutral-400 italic">
              Inheriting: {timeline.assignee}
            </span>
          )}
        </div>
        <div className="space-y-1.5">
          <input
            id="inspector-task-assignee-input"
            type="text"
            disabled={isLocked}
            placeholder={timeline ? `Inherited (${timeline.assignee})` : 'e.g. Marcus Vance'}
            value={task.assignee || ''}
            onChange={(e) => onUpdateTask(task.id, { assignee: e.target.value })}
            className="w-full px-2.5 py-1.5 text-xs text-neutral-900 border border-neutral-300 rounded focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100"
          />
          {task.assignee && !isLocked && (
            <button
              type="button"
              onClick={() => onUpdateTask(task.id, { assignee: '' })}
              className="text-[10px] text-neutral-500 hover:text-neutral-900 underline"
            >
              Clear to inherit timeline assignee ({timeline?.assignee || 'Unassigned'})
            </button>
          )}
        </div>
      </div>

      {/* Planning Readiness: Planned vs Needs Info */}
      <div className="border-t border-neutral-200 pt-3">
        <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider mb-2">
          Planning Readiness
        </label>
        <div className="grid grid-cols-2 gap-2">
          <button
            type="button"
            disabled={isLocked}
            onClick={() => onUpdateTask(task.id, { status: 'planned', needsInfoReason: '' })}
            className={`px-3 py-2 rounded-md border text-xs font-medium flex items-center justify-center gap-1.5 transition-all ${
              task.status === 'planned'
                ? 'bg-neutral-900 text-white border-neutral-900 shadow-xs'
                : 'bg-white text-neutral-700 border-neutral-300 hover:bg-neutral-50'
            }`}
          >
            <CheckCircle2 className="w-3.5 h-3.5" />
            Planned
          </button>

          <button
            type="button"
            disabled={isLocked}
            onClick={() => onUpdateTask(task.id, { status: 'needs_info', needsInfoReason: task.needsInfoReason || 'Missing required information' })}
            className={`px-3 py-2 rounded-md border text-xs font-medium flex items-center justify-center gap-1.5 transition-all ${
              task.status === 'needs_info'
                ? 'bg-amber-600 text-white border-amber-600 shadow-xs'
                : 'bg-white text-neutral-700 border-neutral-300 hover:bg-amber-50/50 hover:border-amber-300'
            }`}
          >
            <AlertCircle className="w-3.5 h-3.5" />
            Needs info
          </button>
        </div>

        {/* Reason for Needs Info */}
        {task.status === 'needs_info' && (
          <div className="mt-2.5 p-2 bg-amber-50 border border-amber-200 rounded text-amber-900 text-xs animate-in fade-in duration-100">
            <div className="font-medium text-[11px] mb-1 flex items-center gap-1 text-amber-800">
              <AlertCircle className="w-3 h-3 text-amber-600" />
              Missing Information (Blocks Publish):
            </div>
            <textarea
              disabled={isLocked}
              rows={2}
              value={task.needsInfoReason || ''}
              onChange={(e) => onUpdateTask(task.id, { needsInfoReason: e.target.value })}
              placeholder="e.g. Awaiting client spec, or verify storage quota..."
              className="w-full p-1.5 text-xs bg-white border border-amber-300 rounded text-neutral-900 focus:outline-none focus:border-amber-600"
            />
          </div>
        )}
      </div>

      {/* Free Text Notes */}
      <div>
        <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider mb-1">
          Planning Notes
        </label>
        <textarea
          id="inspector-task-notes-input"
          disabled={isLocked}
          rows={3}
          value={task.notes || ''}
          onChange={(e) => onUpdateTask(task.id, { notes: e.target.value })}
          placeholder="Any operational notes, prerequisites, or caveats for this step..."
          className="w-full px-2.5 py-2 text-xs text-neutral-900 border border-neutral-300 rounded focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100"
        />
      </div>

      {/* Move Task to Another Timeline or Backlog */}
      {!isLocked && (
        <div className="border-t border-neutral-200 pt-3 space-y-2">
          <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider">
            Timeline Destination
          </label>

          <div className="space-y-1.5">
            {task.timelineId && (
              <button
                type="button"
                onClick={() => onMoveTaskToTimeline(task.id, null)}
                className="w-full py-1.5 px-2 bg-neutral-100 hover:bg-neutral-200 text-neutral-700 rounded text-xs flex items-center justify-center gap-1.5 font-medium transition-colors"
              >
                <ArrowDownToLine className="w-3.5 h-3.5 text-neutral-500" />
                Move to Unplanned Backlog
              </button>
            )}

            {timelinesInWorkspace
              .filter(tl => tl.id !== task.timelineId)
              .map(tl => (
                <button
                  key={tl.id}
                  type="button"
                  onClick={() => onMoveTaskToTimeline(task.id, tl.id)}
                  className="w-full py-1.5 px-2 bg-white hover:bg-neutral-100 border border-neutral-300 text-neutral-700 rounded text-xs flex items-center justify-between transition-colors truncate"
                >
                  <span className="truncate">Move to: {tl.name}</span>
                  <ArrowRight className="w-3 h-3 text-neutral-400 shrink-0 ml-1" />
                </button>
              ))}
          </div>
        </div>
      )}

      {/* Delete Task */}
      {!isLocked && (
        <div className="border-t border-neutral-200 pt-3">
          <button
            id="inspector-delete-task-btn"
            type="button"
            onClick={() => {
              if (confirm(`Permanently remove task "${task.title}"?`)) {
                onDeleteTask(task.id);
              }
            }}
            className="w-full py-1.5 px-3 border border-red-200 text-red-600 hover:bg-red-50 hover:border-red-300 rounded text-xs font-medium flex items-center justify-center gap-1.5 transition-colors"
          >
            <Trash2 className="w-3.5 h-3.5" />
            Delete Task
          </button>
        </div>
      )}
    </div>
  );
}

interface TimelineInspectorBodyProps {
  timeline: Timeline;
  tasksInTimeline: Task[];
  onUpdateTimeline: (timelineId: string, updates: Partial<Timeline>) => void;
  onDeleteTimeline: (timelineId: string) => void;
  onPublishTimeline: (timelineId: string) => void;
  onReopenTimeline: (timelineId: string) => void;
}

function TimelineInspectorBody({
  timeline,
  tasksInTimeline,
  onUpdateTimeline,
  onDeleteTimeline,
  onPublishTimeline,
  onReopenTimeline,
}: TimelineInspectorBodyProps) {
  const isPublished = timeline.status === 'published';
  const needsInfoTasks = tasksInTimeline.filter(t => t.status === 'needs_info');
  const isPublishBlocked = needsInfoTasks.length > 0;

  const totalMinutes = tasksInTimeline.reduce((acc, t) => acc + (t.duration || 0), 0);
  const hours = Math.floor(totalMinutes / 60);
  const mins = totalMinutes % 60;

  return (
    <div className="space-y-4">
      {/* Timeline Name */}
      <div>
        <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider mb-1">
          Timeline Name
        </label>
        <input
          id="inspector-timeline-name-input"
          type="text"
          disabled={isPublished}
          value={timeline.name}
          onChange={(e) => onUpdateTimeline(timeline.id, { name: e.target.value })}
          className="w-full px-2.5 py-1.5 text-xs font-semibold text-neutral-900 border border-neutral-300 rounded focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100"
        />
      </div>

      {/* Planned Date */}
      <div>
        <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider mb-1">
          Planned Date
        </label>
        <input
          id="inspector-timeline-date-input"
          type="date"
          disabled={isPublished}
          value={timeline.plannedDate}
          onChange={(e) => onUpdateTimeline(timeline.id, { plannedDate: e.target.value })}
          className="w-full px-2.5 py-1.5 text-xs font-mono text-neutral-900 border border-neutral-300 rounded focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100"
        />
      </div>

      {/* Default Assignee */}
      <div>
        <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider mb-1">
          Default Assignee
        </label>
        <input
          id="inspector-timeline-assignee-input"
          type="text"
          disabled={isPublished}
          placeholder="e.g. Sarah Jenkins"
          value={timeline.assignee}
          onChange={(e) => onUpdateTimeline(timeline.id, { assignee: e.target.value })}
          className="w-full px-2.5 py-1.5 text-xs text-neutral-900 border border-neutral-300 rounded focus:outline-none focus:border-neutral-900 disabled:bg-neutral-100"
        />
        <p className="text-[10px] text-neutral-400 mt-1">
          Tasks created in this timeline inherit this assignee unless customized.
        </p>
      </div>

      {/* Summary Box */}
      <div className="bg-neutral-50 p-3 rounded-lg border border-neutral-200 space-y-2">
        <div className="text-[11px] font-semibold text-neutral-700">Timeline Run Overview</div>
        <div className="grid grid-cols-2 gap-2 text-xs">
          <div>
            <div className="text-neutral-500 text-[10px]">Total Steps</div>
            <div className="font-mono font-semibold text-neutral-900">{tasksInTimeline.length}</div>
          </div>
          <div>
            <div className="text-neutral-500 text-[10px]">Total Run Time</div>
            <div className="font-mono font-semibold text-neutral-900">
              {hours > 0 ? `${hours}h ${mins}m` : `${mins}m`}
            </div>
          </div>
        </div>

        {/* Readiness Status */}
        <div className="pt-2 border-t border-neutral-200/70">
          <div className="text-neutral-500 text-[10px] mb-1">Publishing Readiness:</div>
          {isPublishBlocked ? (
            <div className="text-amber-800 text-[11px] flex items-start gap-1 font-medium bg-amber-50 p-1.5 rounded border border-amber-200">
              <AlertCircle className="w-3.5 h-3.5 text-amber-600 shrink-0 mt-0.5" />
              <span>{needsInfoTasks.length} task(s) marked 'Needs info'. Must resolve before publishing.</span>
            </div>
          ) : (
            <div className="text-emerald-800 text-[11px] flex items-center gap-1 font-medium bg-emerald-50 p-1.5 rounded border border-emerald-200">
              <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600 shrink-0" />
              <span>All tasks ready for publishing.</span>
            </div>
          )}
        </div>
      </div>

      {/* Publish / Reopen Action in Inspector */}
      <div className="border-t border-neutral-200 pt-3 space-y-2">
        <label className="block text-[11px] font-semibold text-neutral-500 uppercase tracking-wider">
          Lifecycle Status
        </label>

        {isPublished ? (
          <div className="space-y-2">
            <div className="p-2 bg-emerald-50 border border-emerald-200 rounded text-emerald-900 text-xs flex items-center gap-1.5">
              <Lock className="w-3.5 h-3.5 text-emerald-600 shrink-0" />
              <span>Published & locked for execution.</span>
            </div>
            <button
              id="inspector-reopen-btn"
              onClick={() => onReopenTimeline(timeline.id)}
              className="w-full py-2 px-3 bg-white border border-neutral-300 hover:bg-neutral-50 text-neutral-800 rounded-md text-xs font-medium flex items-center justify-center gap-1.5 transition-colors shadow-xs"
            >
              <RotateCcw className="w-3.5 h-3.5" />
              Reopen to edit
            </button>
          </div>
        ) : (
          <div className="space-y-2">
            <button
              id="inspector-publish-btn"
              disabled={isPublishBlocked}
              onClick={() => onPublishTimeline(timeline.id)}
              className={`w-full py-2 px-3 rounded-md text-xs font-medium flex items-center justify-center gap-1.5 transition-all shadow-xs ${
                isPublishBlocked
                  ? 'bg-neutral-100 text-neutral-400 border border-neutral-200 cursor-not-allowed'
                  : 'bg-neutral-900 text-white hover:bg-neutral-800 border border-neutral-900'
              }`}
            >
              <Lock className="w-3.5 h-3.5" />
              Publish Timeline
            </button>
            {isPublishBlocked && (
              <p className="text-[10px] text-amber-700 leading-tight">
                Resolve all {needsInfoTasks.length} task(s) marked 'Needs info' to enable publishing.
              </p>
            )}
          </div>
        )}
      </div>

      {/* Delete Timeline */}
      <div className="border-t border-neutral-200 pt-3">
        <button
          id="inspector-delete-timeline-btn"
          onClick={() => {
            if (confirm(`Delete timeline "${timeline.name}" and all associated scheduled steps?`)) {
              onDeleteTimeline(timeline.id);
            }
          }}
          className="w-full py-1.5 px-3 border border-red-200 text-red-600 hover:bg-red-50 hover:border-red-300 rounded text-xs font-medium flex items-center justify-center gap-1.5 transition-colors"
        >
          <Trash2 className="w-3.5 h-3.5" />
          Delete Timeline
        </button>
      </div>
    </div>
  );
}
