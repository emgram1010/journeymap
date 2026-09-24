import { useState } from 'react';
import { 
  Calendar as CalendarIcon, 
  Clock, 
  User, 
  Lock, 
  AlertCircle, 
  Plus, 
  ArrowRight,
  ChevronLeft,
  ChevronRight,
  Layers,
  Ban
} from 'lucide-react';
import { Timeline, Task, Workspace } from '../types';
import { formatShortDate, getDaysDifference, generateDaysList } from '../utils/dateUtils';

interface ScheduleViewProps {
  workspace: Workspace | null;
  timelines: Timeline[];
  tasks: Task[];
  activeTimelineId: string | null;
  onSelectTimeline: (timelineId: string) => void;
  onSwitchToPlanView: (timelineId: string) => void;
  onDropTaskOnTimeline: (taskId: string, timelineId: string) => void;
  onCreateTimelineForDate: (dateStr: string) => void;
}

export function ScheduleView({
  workspace,
  timelines,
  tasks,
  activeTimelineId,
  onSelectTimeline,
  onSwitchToPlanView,
  onDropTaskOnTimeline,
  onCreateTimelineForDate,
}: ScheduleViewProps) {
  const [spanWeeks, setSpanWeeks] = useState<1 | 2>(2);
  const [dragOverTimelineId, setDragOverTimelineId] = useState<string | null>(null);
  const [dragOverEmptyDate, setDragOverEmptyDate] = useState<string | null>(null);

  const startDate = workspace?.planningWindowStart || '2026-10-12';
  const totalDays = spanWeeks * 7;
  const daysList = generateDaysList(startDate, totalDays);

  const handleDragOverCard = (e: React.DragEvent, timeline: Timeline) => {
    e.preventDefault();
    e.stopPropagation();
    setDragOverEmptyDate(null);
    if (dragOverTimelineId !== timeline.id) {
      setDragOverTimelineId(timeline.id);
    }
  };

  const handleDropOnCard = (e: React.DragEvent, timeline: Timeline) => {
    e.preventDefault();
    e.stopPropagation();
    setDragOverTimelineId(null);
    setDragOverEmptyDate(null);

    if (timeline.status === 'published') {
      return; // Refused
    }

    try {
      const dataStr = e.dataTransfer.getData('text/plain');
      if (!dataStr) return;
      const data = JSON.parse(dataStr);
      if (data.type === 'backlog-task' && data.taskId) {
        onDropTaskOnTimeline(data.taskId, timeline.id);
      }
    } catch (err) {
      console.error('Failed to parse dropped task in Schedule view:', err);
    }
  };

  const handleDragOverEmptyDay = (e: React.DragEvent, dateStr: string) => {
    e.preventDefault();
    setDragOverTimelineId(null);
    if (dragOverEmptyDate !== dateStr) {
      setDragOverEmptyDate(dateStr);
    }
  };

  const handleDropOnEmptyDay = (e: React.DragEvent) => {
    e.preventDefault();
    setDragOverTimelineId(null);
    setDragOverEmptyDate(null);
    // Explicitly refused as per brief section 3.D
  };

  return (
    <div id="schedule-view-canvas" className="flex-1 flex flex-col h-full bg-neutral-50 overflow-hidden select-none">
      {/* Schedule View Sub-header */}
      <div className="h-11 px-6 border-b border-neutral-200 flex items-center justify-between bg-white shrink-0">
        <div className="flex items-center gap-4 text-xs">
          <div className="flex items-center gap-1.5 text-neutral-800 font-semibold">
            <CalendarIcon className="w-3.5 h-3.5 text-neutral-500" />
            <span>Workspace Schedule Matrix</span>
          </div>

          <div className="h-3 w-px bg-neutral-200"></div>

          <div className="text-neutral-500">
            Window: <span className="font-medium text-neutral-800 font-mono">{formatShortDate(startDate)} – {formatShortDate(daysList[daysList.length - 1])}</span>
          </div>
        </div>

        {/* Span Selector (1-week vs 2-week) */}
        <div className="flex items-center gap-2">
          <span className="text-[11px] text-neutral-400 font-medium">Span:</span>
          <div className="inline-flex rounded-md border border-neutral-300 p-0.5 bg-neutral-100 text-xs">
            <button
              id="span-1-week-btn"
              onClick={() => setSpanWeeks(1)}
              className={`px-2.5 py-0.5 rounded text-xs font-medium transition-colors ${
                spanWeeks === 1
                  ? 'bg-white text-neutral-900 shadow-2xs'
                  : 'text-neutral-600 hover:text-neutral-900'
              }`}
            >
              1 Week
            </button>
            <button
              id="span-2-weeks-btn"
              onClick={() => setSpanWeeks(2)}
              className={`px-2.5 py-0.5 rounded text-xs font-medium transition-colors ${
                spanWeeks === 2
                  ? 'bg-white text-neutral-900 shadow-2xs'
                  : 'text-neutral-600 hover:text-neutral-900'
              }`}
            >
              2 Weeks
            </button>
          </div>
        </div>
      </div>

      {/* Days Grid Columns */}
      <div className="flex-1 overflow-x-auto overflow-y-auto p-4">
        <div className={`grid gap-3 min-w-[900px] h-full ${spanWeeks === 1 ? 'grid-cols-7' : 'grid-cols-7'}`}>
          {daysList.map((dateStr, idx) => {
            const dateObj = new Date(`${dateStr}T00:00:00`);
            const dayName = dateObj.toLocaleDateString('en-US', { weekday: 'short' });
            const dayNumber = dateObj.getDate();
            const timelinesForDay = timelines.filter(t => t.plannedDate === dateStr);
            const isToday = false; // deterministic preview
            const isOverEmpty = dragOverEmptyDate === dateStr;

            return (
              <div
                key={dateStr}
                id={`schedule-day-column-${dateStr}`}
                onDragOver={(e) => handleDragOverEmptyDay(e, dateStr)}
                onDrop={handleDropOnEmptyDay}
                className={`flex flex-col rounded-lg border bg-white min-h-[420px] transition-all relative ${
                  isOverEmpty
                    ? 'border-red-400 ring-2 ring-red-100 bg-red-50/30'
                    : 'border-neutral-200/90 shadow-2xs'
                }`}
              >
                {/* Day Header */}
                <div className="p-2.5 border-b border-neutral-100 flex items-center justify-between bg-neutral-50/60 rounded-t-lg">
                  <div>
                    <div className="text-[11px] font-semibold uppercase text-neutral-500 tracking-wider">
                      {dayName}
                    </div>
                    <div className="text-xs font-bold text-neutral-900 font-mono mt-0.5">
                      {formatShortDate(dateStr)}
                    </div>
                  </div>
                  <button
                    onClick={() => onCreateTimelineForDate(dateStr)}
                    className="p-1 rounded text-neutral-400 hover:text-neutral-800 hover:bg-neutral-200/60 transition-colors"
                    title={`Create timeline for ${formatShortDate(dateStr)}`}
                  >
                    <Plus className="w-3.5 h-3.5" />
                  </button>
                </div>

                {/* Day Timelines Container */}
                <div className="flex-1 p-2 space-y-2 overflow-y-auto">
                  {/* Empty Day Drag Refusal Notice */}
                  {isOverEmpty && (
                    <div className="p-2 rounded border border-red-300 bg-red-50 text-red-700 text-[11px] flex items-start gap-1.5 animate-in fade-in duration-75">
                      <Ban className="w-3.5 h-3.5 text-red-500 shrink-0 mt-0.5" />
                      <span>
                        <strong>Drop Refused:</strong> Tasks belong to a timeline. Drop onto an existing timeline card.
                      </span>
                    </div>
                  )}

                  {timelinesForDay.length === 0 ? (
                    <div className="h-full min-h-[140px] flex flex-col items-center justify-center text-center p-3 text-neutral-300">
                      <span className="text-[11px]">No timelines</span>
                    </div>
                  ) : (
                    timelinesForDay.map(tl => {
                      const tlTasks = tasks.filter(t => t.timelineId === tl.id);
                      const isSelected = tl.id === activeTimelineId;
                      const isPublished = tl.status === 'published';
                      const isOver = dragOverTimelineId === tl.id;

                      const totalMinutes = tlTasks.reduce((acc, t) => acc + (t.duration || 0), 0);
                      const hours = Math.floor(totalMinutes / 60);
                      const mins = totalMinutes % 60;
                      const durationStr = hours > 0 ? `${hours}h ${mins > 0 ? `${mins}m` : ''}` : `${mins}m`;

                      return (
                        <div
                          key={tl.id}
                          id={`schedule-timeline-card-${tl.id}`}
                          onClick={() => onSelectTimeline(tl.id)}
                          onDragOver={(e) => handleDragOverCard(e, tl)}
                          onDrop={(e) => handleDropOnCard(e, tl)}
                          className={`p-2.5 rounded-lg border text-left cursor-pointer transition-all ${
                            isOver && !isPublished
                              ? 'border-neutral-900 ring-2 ring-neutral-900/10 bg-neutral-100/80'
                              : isOver && isPublished
                              ? 'border-red-400 ring-2 ring-red-100 bg-red-50'
                              : isSelected
                              ? 'border-neutral-900 bg-neutral-50/50 shadow-xs'
                              : 'border-neutral-200 bg-white hover:border-neutral-300'
                          }`}
                        >
                          {/* Receiving State Indicator */}
                          {isOver && !isPublished && (
                            <div className="mb-1.5 text-[10px] font-bold text-neutral-900 flex items-center gap-1 bg-neutral-200/80 px-1.5 py-0.5 rounded">
                              <span>Drop to append task</span>
                            </div>
                          )}

                          {/* Refusal State for Published */}
                          {isOver && isPublished && (
                            <div className="mb-1.5 text-[10px] font-bold text-red-700 flex items-center gap-1 bg-red-100 px-1.5 py-0.5 rounded">
                              <Ban className="w-3 h-3 text-red-600" />
                              <span>Refusal: Timeline is published and locked</span>
                            </div>
                          )}

                          <div className="flex items-start justify-between gap-1.5">
                            <div className="text-xs font-semibold text-neutral-900 leading-snug line-clamp-2">
                              {tl.name}
                            </div>
                            {isPublished && (
                              <span title="Published">
                                <Lock className="w-3 h-3 text-emerald-600 shrink-0 mt-0.5" />
                              </span>
                            )}
                          </div>

                          <div className="mt-2 flex items-center justify-between text-[11px] text-neutral-500">
                            <span className="font-mono font-medium text-neutral-700">
                              {tlTasks.length} {tlTasks.length === 1 ? 'task' : 'tasks'}
                            </span>
                            <span className="font-mono text-neutral-500 text-[10px]">
                              {durationStr}
                            </span>
                          </div>

                          <div className="mt-2 pt-1.5 border-t border-neutral-100 flex items-center justify-between text-[10px]">
                            <span className="text-neutral-500 truncate max-w-[100px]">
                              {tl.assignee || 'Unassigned'}
                            </span>

                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                onSwitchToPlanView(tl.id);
                              }}
                              className="text-neutral-700 hover:text-black font-medium inline-flex items-center gap-0.5"
                              title="Open in Plan View"
                            >
                              <span>Plan</span>
                              <ArrowRight className="w-2.5 h-2.5" />
                            </button>
                          </div>
                        </div>
                      );
                    })
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
