import { useState } from 'react';
import { 
  Plus, 
  Calendar as CalendarIcon, 
  Lock, 
  MoreVertical, 
  Edit3, 
  Trash2, 
  User, 
  Clock, 
  Layers,
  AlertCircle,
  Ban,
  Check
} from 'lucide-react';
import { Timeline, Task } from '../types';
import { isDateOutOfWindow, formatShortDate } from '../utils/dateUtils';

interface TimelineRailProps {
  timelines: Timeline[];
  tasks: Task[];
  activeTimelineId: string | null;
  planningWindowStart: string;
  planningWindowEnd: string;
  onSelectTimeline: (id: string) => void;
  onCreateTimeline: (name: string, plannedDate: string, assignee: string) => void;
  onRenameTimeline: (id: string, newName: string) => void;
  onDeleteTimeline: (id: string) => void;
  onDropTaskOnRailTimeline: (taskId: string, timelineId: string) => void;
  onOpenTimelineEditModal: (timelineId: string) => void;
}

export function TimelineRail({
  timelines,
  tasks,
  activeTimelineId,
  planningWindowStart,
  planningWindowEnd,
  onSelectTimeline,
  onCreateTimeline,
  onRenameTimeline,
  onDeleteTimeline,
  onDropTaskOnRailTimeline,
  onOpenTimelineEditModal,
}: TimelineRailProps) {
  const [isCreating, setIsCreating] = useState(false);
  const [newName, setNewName] = useState('');
  const [newDate, setNewDate] = useState('2026-10-15');
  const [newAssignee, setNewAssignee] = useState('Marcus Vance');

  const [activeMenuId, setActiveMenuId] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingName, setEditingName] = useState('');

  // Drag over target tracking
  const [dragOverTimelineId, setDragOverTimelineId] = useState<string | null>(null);
  const [quietConfirmation, setQuietConfirmation] = useState<string | null>(null);

  const handleStartCreate = () => {
    setIsCreating(true);
    setNewName('');
  };

  const handleConfirmCreate = () => {
    if (newName.trim()) {
      onCreateTimeline(newName.trim(), newDate, newAssignee.trim() || 'Unassigned');
      setIsCreating(false);
      setNewName('');
    }
  };

  const handleStartRename = (tl: Timeline, e: React.MouseEvent) => {
    e.stopPropagation();
    setActiveMenuId(null);
    setEditingId(tl.id);
    setEditingName(tl.name);
  };

  const handleConfirmRename = (id: string) => {
    if (editingName.trim()) {
      onRenameTimeline(id, editingName.trim());
      setEditingId(null);
    }
  };

  const handleDelete = (tl: Timeline, e: React.MouseEvent) => {
    e.stopPropagation();
    setActiveMenuId(null);
    if (confirm(`Delete timeline "${tl.name}" and all of its scheduled tasks?`)) {
      onDeleteTimeline(tl.id);
    }
  };

  // Section 3.C: Drag over timeline card
  const handleDragOverCard = (e: React.DragEvent, tl: Timeline) => {
    e.preventDefault();
    e.stopPropagation();
    if (dragOverTimelineId !== tl.id) {
      setDragOverTimelineId(tl.id);
    }
  };

  const handleDragLeaveCard = (tl: Timeline) => {
    if (dragOverTimelineId === tl.id) {
      setDragOverTimelineId(null);
    }
  };

  // Section 3.C & 3.F: Drop on timeline card
  const handleDropOnCard = (e: React.DragEvent, tl: Timeline) => {
    e.preventDefault();
    e.stopPropagation();
    setDragOverTimelineId(null);

    // Section 3.F: Published refusal
    if (tl.status === 'published') {
      return;
    }

    try {
      const dataStr = e.dataTransfer.getData('text/plain');
      if (!dataStr) return;
      const data = JSON.parse(dataStr);

      if (data.type === 'backlog-task' && data.taskId) {
        onDropTaskOnRailTimeline(data.taskId, tl.id);

        // Quiet confirmation notice (Section 3.C)
        setQuietConfirmation(`Appended task to "${tl.name}"`);
        setTimeout(() => setQuietConfirmation(null), 3000);
      }
    } catch (err) {
      console.error('Failed to parse dropped task on rail card:', err);
    }
  };

  return (
    <aside 
      id="timeline-rail"
      className="w-[260px] shrink-0 bg-neutral-50/80 border-r border-neutral-200 flex flex-col h-full select-none relative"
    >
      {/* Rail Header */}
      <div className="h-11 px-4 border-b border-neutral-200/80 flex items-center justify-between bg-neutral-50 shrink-0">
        <div className="flex items-center gap-2">
          <span className="text-[11px] font-bold text-neutral-500 tracking-wider uppercase">
            Timelines
          </span>
          <span className="text-[11px] font-mono text-neutral-400 bg-neutral-200/70 px-1.5 py-0.2 rounded-full">
            {timelines.length}
          </span>
        </div>

        <button
          id="rail-new-timeline-btn"
          onClick={handleStartCreate}
          className="p-1 rounded text-neutral-500 hover:text-neutral-900 hover:bg-neutral-200/60 transition-colors"
          title="Create a new timeline"
          aria-label="Add timeline"
        >
          <Plus className="w-4 h-4" />
        </button>
      </div>

      {/* Quiet Confirmation Toast (Section 3.C) */}
      {quietConfirmation && (
        <div className="mx-2 mt-2 p-2 rounded bg-neutral-900 text-white text-[11px] font-medium flex items-center gap-1.5 shadow-md animate-in fade-in duration-100 z-20">
          <Check className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
          <span className="truncate">{quietConfirmation}</span>
        </div>
      )}

      {/* Creation form if opened */}
      {isCreating && (
        <div 
          id="new-timeline-inline-form"
          className="p-3 bg-white border-b border-neutral-200 shadow-xs flex flex-col gap-2.5 animate-in fade-in duration-100"
        >
          <div className="text-xs font-semibold text-neutral-900">New Timeline</div>
          <input
            type="text"
            placeholder="e.g. Day 1: System Cutover"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleConfirmCreate();
              if (e.key === 'Escape') setIsCreating(false);
            }}
            className="w-full px-2.5 py-1.5 text-xs border border-neutral-300 rounded focus:outline-none focus:border-neutral-900 bg-neutral-50/50"
            autoFocus
          />

          <div className="flex items-center gap-2">
            <input
              type="date"
              value={newDate}
              onChange={(e) => setNewDate(e.target.value)}
              className="flex-1 px-2 py-1 text-xs border border-neutral-300 rounded text-neutral-700 bg-neutral-50/50"
            />
            <input
              type="text"
              placeholder="Assignee"
              value={newAssignee}
              onChange={(e) => setNewAssignee(e.target.value)}
              className="w-28 px-2 py-1 text-xs border border-neutral-300 rounded text-neutral-700 bg-neutral-50/50"
            />
          </div>

          <div className="flex items-center justify-end gap-1.5 pt-1">
            <button
              onClick={() => setIsCreating(false)}
              className="px-2.5 py-1 text-xs text-neutral-600 hover:text-neutral-900 rounded"
            >
              Cancel
            </button>
            <button
              id="confirm-create-timeline-btn"
              onClick={handleConfirmCreate}
              disabled={!newName.trim()}
              className="px-3 py-1 bg-neutral-900 text-white rounded text-xs font-medium hover:bg-neutral-800 disabled:opacity-50"
            >
              Create
            </button>
          </div>
        </div>
      )}

      {/* Timeline List */}
      <div className="flex-1 overflow-y-auto p-2 space-y-1">
        {timelines.length === 0 ? (
          <div className="p-4 text-center text-xs text-neutral-400">
            No timelines in this workspace yet. Click <span className="font-semibold text-neutral-600">+</span> to add one.
          </div>
        ) : (
          timelines.map((tl) => {
            const isSelected = tl.id === activeTimelineId;
            const tlTasks = tasks.filter(t => t.timelineId === tl.id);
            const taskCount = tlTasks.length;
            const hasNeedsInfo = tlTasks.some(t => t.status === 'needs_info');
            const isPublished = tl.status === 'published';
            const isOver = dragOverTimelineId === tl.id;
            const isOutOfWindow = isDateOutOfWindow(tl.plannedDate, planningWindowStart, planningWindowEnd);

            return (
              <div
                key={tl.id}
                id={`timeline-card-${tl.id}`}
                onClick={() => onSelectTimeline(tl.id)}
                onDragOver={(e) => handleDragOverCard(e, tl)}
                onDragLeave={() => handleDragLeaveCard(tl)}
                onDrop={(e) => handleDropOnCard(e, tl)}
                className={`group relative p-3 rounded-lg cursor-pointer transition-all border text-left ${
                  isOver && !isPublished
                    ? 'bg-neutral-100 border-neutral-900 ring-2 ring-neutral-900/15 shadow-sm'
                    : isOver && isPublished
                    ? 'bg-red-50 border-red-400 ring-2 ring-red-100'
                    : isSelected
                    ? 'bg-white border-neutral-300 shadow-xs ring-1 ring-neutral-900/5'
                    : 'bg-transparent border-transparent hover:bg-neutral-100/80 hover:border-neutral-200'
                }`}
              >
                {/* Section 3.C: Receiving State Banner on Drag */}
                {isOver && !isPublished && (
                  <div className="mb-1.5 text-[10px] font-bold text-neutral-900 flex items-center gap-1 bg-neutral-200/90 px-1.5 py-0.5 rounded">
                    <span>Drop to append at end (+1 task)</span>
                  </div>
                )}

                {/* Section 3.F: Refusal State on Drag Over Published */}
                {isOver && isPublished && (
                  <div className="mb-1.5 text-[10px] font-bold text-red-700 flex items-center gap-1 bg-red-100 px-1.5 py-0.5 rounded">
                    <Ban className="w-3 h-3 text-red-600" />
                    <span>Refusal: Timeline is published and locked</span>
                  </div>
                )}

                {editingId === tl.id ? (
                  <div className="flex items-center gap-1.5" onClick={(e) => e.stopPropagation()}>
                    <input
                      type="text"
                      value={editingName}
                      onChange={(e) => setEditingName(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') handleConfirmRename(tl.id);
                        if (e.key === 'Escape') setEditingId(null);
                      }}
                      className="w-full px-2 py-1 text-xs border border-neutral-300 rounded font-medium focus:outline-none focus:border-neutral-900"
                      autoFocus
                    />
                    <button
                      onClick={() => handleConfirmRename(tl.id)}
                      className="px-2 py-1 bg-neutral-900 text-white text-xs rounded"
                    >
                      Save
                    </button>
                  </div>
                ) : (
                  <>
                    <div className="flex items-start justify-between gap-1.5">
                      <h3 className={`text-xs font-semibold leading-snug line-clamp-2 ${
                        isSelected ? 'text-neutral-900' : 'text-neutral-700'
                      }`}>
                        {tl.name}
                      </h3>

                      {/* Kebab action trigger */}
                      <div className="relative shrink-0">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            setActiveMenuId(activeMenuId === tl.id ? null : tl.id);
                          }}
                          className={`p-1 rounded text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50 transition-opacity ${
                            isSelected ? 'opacity-100' : 'opacity-0 group-hover:opacity-100'
                          }`}
                          title="Timeline options"
                        >
                          <MoreVertical className="w-3.5 h-3.5" />
                        </button>

                        {/* Menu Dropdown */}
                        {activeMenuId === tl.id && (
                          <div 
                            className="absolute right-0 top-full mt-1 w-32 bg-white rounded-md shadow-lg border border-neutral-200 py-1 z-30"
                            onClick={(e) => e.stopPropagation()}
                          >
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                setActiveMenuId(null);
                                onOpenTimelineEditModal(tl.id);
                              }}
                              className="w-full px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-100 flex items-center gap-2 text-left font-medium"
                            >
                              <Edit3 className="w-3.5 h-3.5 text-neutral-500" />
                              Edit timeline
                            </button>
                            <button
                              onClick={(e) => handleStartRename(tl, e)}
                              className="w-full px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-100 flex items-center gap-2 text-left"
                            >
                              <span className="w-3.5 text-center font-mono text-[10px] text-neutral-400">Aa</span>
                              Quick rename
                            </button>
                            <button
                              onClick={(e) => handleDelete(tl, e)}
                              className="w-full px-2.5 py-1.5 text-xs text-red-600 hover:bg-red-50 flex items-center gap-2 text-left"
                            >
                              <Trash2 className="w-3.5 h-3.5 text-red-500" />
                              Delete
                            </button>
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Timeline metadata preview */}
                    <div className="mt-2 flex items-center gap-2 text-[11px] text-neutral-500">
                      <span className="flex items-center gap-1 font-mono font-medium text-neutral-600">
                        <CalendarIcon className="w-3 h-3 text-neutral-400" />
                        {tl.plannedDate}
                      </span>

                      <span>•</span>

                      <span className="font-mono text-neutral-600">
                        {taskCount} {taskCount === 1 ? 'task' : 'tasks'}
                      </span>
                    </div>

                    {/* Tags row: Out of window, Needs info, Status */}
                    <div className="mt-2 flex flex-wrap items-center gap-1">
                      {isPublished ? (
                        <span className="inline-flex items-center gap-0.5 px-1.5 py-0.2 rounded text-[10px] font-medium bg-emerald-50 text-emerald-700 border border-emerald-200">
                          <Lock className="w-2.5 h-2.5" />
                          Published
                        </span>
                      ) : (
                        <span className="inline-flex items-center px-1.5 py-0.2 rounded text-[10px] font-medium bg-neutral-100 text-neutral-600 border border-neutral-200">
                          Draft
                        </span>
                      )}

                      {isOutOfWindow && (
                        <span 
                          className="inline-flex items-center gap-0.5 px-1.5 py-0.2 rounded text-[10px] font-semibold bg-red-50 text-red-700 border border-red-200"
                          title="Planned date is outside workspace window"
                        >
                          Out of window
                        </span>
                      )}

                      {hasNeedsInfo && !isPublished && (
                        <span 
                          className="inline-flex items-center gap-0.5 px-1.5 py-0.2 rounded text-[10px] font-semibold bg-amber-50 text-amber-700 border border-amber-200"
                          title="Contains tasks needing info"
                        >
                          Needs info
                        </span>
                      )}
                    </div>
                  </>
                )}
              </div>
            );
          })
        )}
      </div>
    </aside>
  );
}
