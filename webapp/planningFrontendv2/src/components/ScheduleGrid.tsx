import { useState, useRef, useEffect } from 'react';
import {
  Calendar as CalendarIcon,
  Lock,
  AlertCircle,
  AlertTriangle,
  Plus,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  Ban,
  GripVertical,
  HelpCircle,
  Users,
  Search,
  Eye,
  EyeOff,
  Pencil
} from 'lucide-react';
import { Agent, Timeline, Task, Workspace } from '../types';
import { formatShortDate, generateDaysList, isDateOutOfWindow } from '../utils/dateUtils';
import { calculateAgentDayLoad } from '../utils/agentUtils';

interface ScheduleGridProps {
  workspace: Workspace | null;
  agents: Agent[];
  timelines: Timeline[];
  tasks: Task[];
  onOpenCellInPlan: (date: string, agentId: string) => void;
  onCreateTimelineForCell: (agentId: string, date: string) => void;
  onMoveTimelineCell: (timelineId: string, targetAgentId: string, targetDate: string) => void;
  onDropTaskOnTimelineCell: (taskId: string, timelineId: string) => void;
  onDropTaskOnEmptyCell: (taskId: string, agentId: string, date: string) => void;
  onToggleAgentVisibility: (agentId: string) => void;
  onShowAllAgents: () => void;
  onHideAllAgents: () => void;
  onOpenAddAgentModal: () => void;
  onEditAgent: (agentId: string) => void;
  viewSwitcher?: React.ReactNode;
  buildPlanButton?: React.ReactNode;
}

export function ScheduleGrid({
  workspace,
  agents,
  timelines,
  tasks,
  onOpenCellInPlan,
  onCreateTimelineForCell,
  onMoveTimelineCell,
  onDropTaskOnTimelineCell,
  onDropTaskOnEmptyCell,
  onToggleAgentVisibility,
  onShowAllAgents,
  onHideAllAgents,
  onOpenAddAgentModal,
  onEditAgent,
  viewSwitcher,
  buildPlanButton,
}: ScheduleGridProps) {
  const [spanWeeks, setSpanWeeks] = useState<1 | 2>(2);
  // Story F1: paging (in days) through the planning window while in
  // 1-week mode. Reset whenever the toggle switches back to 2-week mode,
  // so 2-week always starts at the window start (unchanged behavior).
  const [pageOffsetDays, setPageOffsetDays] = useState(0);
  const [draggedCellInfo, setDraggedCellInfo] = useState<{
    timelineId: string;
    sourceAgentId: string;
    sourceDate: string;
  } | null>(null);

  // Drag over target cell: agentId_date
  const [dragOverCellKey, setDragOverCellKey] = useState<string | null>(null);
  const [isDropRefused, setIsDropRefused] = useState(false);
  const [refusalReason, setRefusalReason] = useState<string | null>(null);

  const addDaysToDateStr = (dateStr: string, days: number): string => {
    const [y, m, d] = dateStr.split('-').map(Number);
    const dt = new Date(y, m - 1, d);
    dt.setDate(dt.getDate() + days);
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
  };

  const windowStart = workspace?.planningWindowStart || '2026-10-12';
  const windowEnd = workspace?.planningWindowEnd || '2026-10-25';
  const startDate = spanWeeks === 1 ? addDaysToDateStr(windowStart, pageOffsetDays) : windowStart;
  const totalDays = spanWeeks * 7;
  const daysList = generateDaysList(startDate, totalDays);
  const currentRangeEnd = addDaysToDateStr(startDate, totalDays - 1);

  // Paging bounds: disabled (not hidden) once paging would move outside
  // the workspace's planning window.
  const canPagePrev = spanWeeks === 1 && startDate > windowStart;
  const canPageNext = spanWeeks === 1 && currentRangeEnd < windowEnd;

  const handleSetSpanWeeks = (weeks: 1 | 2) => {
    setSpanWeeks(weeks);
    if (weeks === 2) setPageOffsetDays(0);
  };

  const handlePagePrevWeek = () => {
    if (!canPagePrev) return;
    setPageOffsetDays(prev => prev - 7);
  };

  const handlePageNextWeek = () => {
    if (!canPageNext) return;
    setPageOffsetDays(prev => prev + 7);
  };

  const visibleAgents = agents.filter(a => a.isVisible);

  // Agents popover: replaces the roster rail in this view — visibility
  // toggle, search, and Add agent, all reachable on demand instead of
  // permanently pinned, since the Grid's own rows already show identity.
  const [isAgentsPopoverOpen, setIsAgentsPopoverOpen] = useState(false);
  const [agentSearchQuery, setAgentSearchQuery] = useState('');
  const agentsPopoverRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!isAgentsPopoverOpen) return;
    const handleClickOutside = (e: MouseEvent) => {
      if (agentsPopoverRef.current && !agentsPopoverRef.current.contains(e.target as Node)) {
        setIsAgentsPopoverOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isAgentsPopoverOpen]);

  const filteredAgentsForPopover = agents.filter(a =>
    a.name.toLowerCase().includes(agentSearchQuery.toLowerCase()) ||
    a.kind.toLowerCase().includes(agentSearchQuery.toLowerCase())
  );

  // Today marker for realistic context (2026-10-13 in this planning cycle)
  const simulatedToday = '2026-10-13';

  // Drag cell start
  const handleCellDragStart = (
    e: React.DragEvent,
    timeline: Timeline,
    agentId: string,
    date: string
  ) => {
    setDraggedCellInfo({
      timelineId: timeline.id,
      sourceAgentId: agentId,
      sourceDate: date,
    });
    const payload = JSON.stringify({
      type: 'timeline-cell',
      timelineId: timeline.id,
      sourceAgentId: agentId,
      sourceDate: date,
    });
    e.dataTransfer.setData('application/json', payload);
    e.dataTransfer.setData('text/plain', payload);
    e.dataTransfer.effectAllowed = 'move';
  };

  const handleCellDragEnd = () => {
    setDraggedCellInfo(null);
    setDragOverCellKey(null);
    setIsDropRefused(false);
    setRefusalReason(null);
  };

  // Drag over cell
  const handleCellDragOver = (
    e: React.DragEvent,
    agentId: string,
    date: string,
    hasExistingTimeline: boolean
  ) => {
    e.preventDefault();
    const cellKey = `${agentId}_${date}`;

    // If dragging a timeline-cell
    if (draggedCellInfo) {
      if (hasExistingTimeline) {
        // Drop refused onto an occupied cell! (One-per-day rule)
        if (draggedCellInfo.sourceAgentId !== agentId || draggedCellInfo.sourceDate !== date) {
          e.dataTransfer.dropEffect = 'none';
          setDragOverCellKey(cellKey);
          setIsDropRefused(true);
          setRefusalReason('Refused: Agent already has a timeline on this day (one-per-day rule)');
          return;
        }
      } else {
        // Valid drop onto empty cell
        e.dataTransfer.dropEffect = 'move';
        setDragOverCellKey(cellKey);
        setIsDropRefused(false);
        setRefusalReason(null);
        return;
      }
    }

    // If dragging a backlog task or external task
    e.dataTransfer.dropEffect = 'move';
    setDragOverCellKey(cellKey);
    setIsDropRefused(false);
    setRefusalReason(null);
  };

  const handleCellDragLeave = (agentId: string, date: string) => {
    const cellKey = `${agentId}_${date}`;
    if (dragOverCellKey === cellKey) {
      setDragOverCellKey(null);
      setIsDropRefused(false);
      setRefusalReason(null);
    }
  };

  // Drop onto cell
  const handleCellDrop = (
    e: React.DragEvent,
    agentId: string,
    date: string,
    existingTimeline?: Timeline
  ) => {
    e.preventDefault();
    e.stopPropagation();
    setDragOverCellKey(null);
    setIsDropRefused(false);
    setRefusalReason(null);
    setDraggedCellInfo(null);

    try {
      const dataStr = e.dataTransfer.getData('application/json') || e.dataTransfer.getData('text/plain');
      if (!dataStr) return;
      const data = JSON.parse(dataStr);

      // Case 1: Dragging a cell to a new day or new agent
      if (data.type === 'timeline-cell') {
        if (existingTimeline) {
          // REFUSED! One agent, one timeline, per day.
          console.warn('Drop refused: Target cell already holds a timeline.');
          return;
        }
        onMoveTimelineCell(data.timelineId, agentId, date);
        return;
      }

      // Case 2: Dragging a task (from backlog or timeline) onto a cell
      if ((data.type === 'backlog-task' || data.type === 'timeline-task') && data.taskId) {
        if (existingTimeline) {
          if (existingTimeline.status === 'published') {
            console.warn('Published timeline refuses drops');
            return;
          }
          onDropTaskOnTimelineCell(data.taskId, existingTimeline.id);
        } else {
          // Dragging bucket task onto an empty cell -> creates the timeline and places task in it! (§4)
          onDropTaskOnEmptyCell(data.taskId, agentId, date);
        }
      }
    } catch (err) {
      console.error('Failed to parse dropped cell data:', err);
    }
  };

  return (
    <div id="schedule-grid-container" className="flex-1 flex flex-col h-full bg-neutral-100/60 overflow-hidden select-none">
      {/* Subheader Toolbar */}
      <div className="h-12 px-4 border-b border-neutral-200 flex items-center justify-between bg-white shrink-0">
        {/* Left zone — flex-1, mirrored by the right zone, so the view
            switcher sits at true centre in both views. */}
        <div className="flex-1 flex items-center gap-3 min-w-0">
          <div className="flex items-center gap-1.5 text-xs font-semibold text-neutral-900">
            <CalendarIcon className="w-3.5 h-3.5 text-neutral-600" />
            <span>Agent × Day Schedule Grid</span>
          </div>

          <span className="text-neutral-300">|</span>

          <span className="text-[11px] text-neutral-500">
            Showing {visibleAgents.length} {visibleAgents.length === 1 ? 'agent' : 'agents'} across {spanWeeks === 1 ? '7 days (1 week)' : '14 days (2 weeks)'}
          </span>

          {/* Story E1: drag-reorder hint preserved as a tooltip instead of a permanent legend strip */}
          <span
            className="text-neutral-300 cursor-help"
            title="Drag cell horizontally to re-date · Vertically to re-assign · Refused on occupied cell"
          >
            <HelpCircle className="w-3.5 h-3.5" />
          </span>
        </div>

        {/* Centre: view switcher */}
        <div className="shrink-0">{viewSwitcher}</div>

        <div className="flex-1 flex items-center justify-end gap-2 min-w-0">
          {buildPlanButton}

          {/* Agents popover: visibility toggle, search, Add agent — the
              roster rail's controls, on demand instead of pinned, since
              this view no longer shows the rail. */}
          <div className="relative" ref={agentsPopoverRef}>
            <button
              id="grid-agents-popover-btn"
              type="button"
              onClick={() => setIsAgentsPopoverOpen(prev => !prev)}
              className="flex items-center gap-1.5 px-2.5 py-1 rounded border border-neutral-200 bg-neutral-100 hover:bg-neutral-200/70 text-xs font-medium text-neutral-700 hover:text-neutral-900 transition-colors"
              aria-expanded={isAgentsPopoverOpen}
              title="Show/hide agents, search the roster, or add an agent"
            >
              <Users className="w-3.5 h-3.5" />
              Agents ({agents.length})
              <ChevronDown className="w-3 h-3 text-neutral-400" />
            </button>

            {isAgentsPopoverOpen && (
              <div
                id="grid-agents-popover"
                className="absolute right-0 top-full mt-1.5 w-72 bg-white rounded-lg shadow-xl border border-neutral-200 z-50 text-xs flex flex-col animate-in fade-in zoom-in-95 duration-75"
              >
                <div className="p-2 border-b border-neutral-100 flex items-center gap-1.5">
                  <div className="relative flex-1">
                    <Search className="w-3 h-3 absolute left-2 top-2 text-neutral-400" />
                    <input
                      type="text"
                      placeholder="Search roster..."
                      value={agentSearchQuery}
                      onChange={(e) => setAgentSearchQuery(e.target.value)}
                      className="w-full pl-6 pr-2 py-1 text-xs bg-neutral-50 border border-neutral-200 rounded focus:bg-white focus:border-neutral-400 focus:outline-none placeholder:text-neutral-400"
                    />
                  </div>
                  <div className="flex items-center gap-0.5 border border-neutral-200 rounded p-0.5 bg-neutral-50 shrink-0">
                    <button
                      type="button"
                      onClick={onShowAllAgents}
                      className="px-1.5 py-0.5 text-[10px] font-medium text-neutral-600 hover:text-neutral-900 hover:bg-white rounded transition-colors"
                      title="Show all agents"
                    >
                      All
                    </button>
                    <span className="text-neutral-300 text-[10px]">|</span>
                    <button
                      type="button"
                      onClick={onHideAllAgents}
                      className="px-1.5 py-0.5 text-[10px] font-medium text-neutral-600 hover:text-neutral-900 hover:bg-white rounded transition-colors"
                      title="Hide all agents"
                    >
                      None
                    </button>
                  </div>
                </div>

                <div className="max-h-72 overflow-y-auto py-1">
                  {filteredAgentsForPopover.length === 0 ? (
                    <div className="py-6 text-center text-neutral-400">No agents match filter</div>
                  ) : (
                    filteredAgentsForPopover.map(agent => (
                      <div
                        key={agent.id}
                        className={`px-2.5 py-1.5 flex items-center justify-between gap-2 hover:bg-neutral-50 ${
                          agent.isVisible ? '' : 'opacity-50'
                        }`}
                      >
                        <div className="flex items-center gap-2 min-w-0">
                          <div className="w-2.5 h-2.5 rounded-xs shrink-0" style={{ backgroundColor: agent.color }} />
                          <span className="truncate text-neutral-800 font-medium">{agent.name}</span>
                          {agent.kind === 'ai' ? (
                            <span className="text-[9px] text-purple-700 font-bold shrink-0">◆</span>
                          ) : (
                            <span className="text-[9px] text-neutral-400 font-bold shrink-0">●</span>
                          )}
                        </div>
                        <div className="flex items-center gap-0.5 shrink-0">
                          <button
                            type="button"
                            onClick={() => { setIsAgentsPopoverOpen(false); onEditAgent(agent.id); }}
                            className="p-1 rounded text-neutral-400 hover:text-neutral-800 hover:bg-neutral-200/60 transition-colors"
                            title="Edit agent (capacity, model, colour)"
                          >
                            <Pencil className="w-3.5 h-3.5" />
                          </button>
                          <button
                            type="button"
                            onClick={() => onToggleAgentVisibility(agent.id)}
                            className={`p-1 rounded hover:bg-neutral-200/60 transition-colors ${
                              agent.isVisible ? 'text-neutral-600' : 'text-neutral-400'
                            }`}
                            title={agent.isVisible ? 'Hide from grid' : 'Show on grid'}
                          >
                            {agent.isVisible ? <Eye className="w-3.5 h-3.5" /> : <EyeOff className="w-3.5 h-3.5" />}
                          </button>
                        </div>
                      </div>
                    ))
                  )}
                </div>

                <div className="border-t border-neutral-100 p-1.5">
                  <button
                    type="button"
                    onClick={() => { setIsAgentsPopoverOpen(false); onOpenAddAgentModal(); }}
                    className="w-full text-left px-2 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50 rounded flex items-center gap-1.5 font-medium"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    Add agent
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Story F1: 1-week paging — 2-week mode is unaffected */}
          {spanWeeks === 1 && (
            <div className="flex items-center gap-1 bg-neutral-100 p-0.5 rounded border border-neutral-200">
              <button
                id="grid-page-prev-week-btn"
                type="button"
                onClick={handlePagePrevWeek}
                disabled={!canPagePrev}
                className={`p-1 rounded transition-colors ${
                  canPagePrev ? 'hover:bg-white text-neutral-700 hover:text-neutral-900' : 'text-neutral-300 cursor-not-allowed'
                }`}
                title={canPagePrev ? 'Previous week' : 'At start of planning window'}
              >
                <ChevronLeft className="w-3.5 h-3.5" />
              </button>
              <span className="px-1.5 text-[11px] font-mono text-neutral-600 min-w-[110px] text-center">
                {formatShortDate(startDate)} – {formatShortDate(currentRangeEnd)}
              </span>
              <button
                id="grid-page-next-week-btn"
                type="button"
                onClick={handlePageNextWeek}
                disabled={!canPageNext}
                className={`p-1 rounded transition-colors ${
                  canPageNext ? 'hover:bg-white text-neutral-700 hover:text-neutral-900' : 'text-neutral-300 cursor-not-allowed'
                }`}
                title={canPageNext ? 'Next week' : 'At end of planning window'}
              >
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          )}

          {/* Span Selector (1w vs 2w) */}
          <div className="w-[161px] flex items-center bg-neutral-100 p-0.5 rounded border border-neutral-200 text-xs shrink-0">
            <button
              id="grid-span-1w-btn"
              type="button"
              onClick={() => handleSetSpanWeeks(1)}
              className={`flex-1 px-2.5 py-1 rounded text-xs font-medium transition-colors ${
                spanWeeks === 1
                  ? 'bg-white text-neutral-900 shadow-2xs font-semibold'
                  : 'text-neutral-600 hover:text-neutral-900'
              }`}
            >
              1 Week
            </button>
            <button
              id="grid-span-2w-btn"
              type="button"
              onClick={() => handleSetSpanWeeks(2)}
              className={`flex-1 px-2.5 py-1 rounded text-xs font-medium transition-colors ${
                spanWeeks === 2
                  ? 'bg-white text-neutral-900 shadow-2xs font-semibold'
                  : 'text-neutral-600 hover:text-neutral-900'
              }`}
            >
              2 Weeks
            </button>
          </div>
        </div>
      </div>

      {/* Grid Canvas Table with Pinned Headers (§4) */}
      <div className="flex-1 overflow-auto bg-neutral-200/50 relative">
        <table className="min-w-full border-separate border-spacing-0">
          {/* Sticky Column Headers (Days) */}
          <thead className="sticky top-0 z-20 bg-neutral-50">
            <tr>
              {/* Sticky Top-Left Corner Header */}
              <th className="sticky left-0 top-0 z-30 bg-neutral-100 border-b border-r border-neutral-200 px-3 py-2 text-left text-[11px] font-semibold text-neutral-600 w-48 min-w-48 shadow-[1px_0_0_0_rgba(0,0,0,0.06)]">
                Agent
              </th>

              {daysList.map(dateStr => {
                const dateObj = new Date(dateStr + 'T00:00:00');
                const dayName = dateObj.toLocaleDateString('en-US', { weekday: 'short' });
                const dayNum = dateObj.getDate();
                const isToday = dateStr === simulatedToday;

                return (
                  <th 
                    key={dateStr}
                    className={`border-b border-r border-neutral-200 px-2 py-1.5 text-center font-medium min-w-[100px] sm:min-w-[115px] ${
                      isToday ? 'bg-neutral-900 text-white' : 'bg-neutral-50 text-neutral-700'
                    }`}
                  >
                    <div className="flex flex-col items-center justify-center">
                      <span className={`text-[10px] uppercase font-semibold ${
                        isToday ? 'text-neutral-300' : 'text-neutral-400'
                      }`}>
                        {dayName}
                      </span>
                      <div className="flex items-center gap-1">
                        <span className="text-xs font-bold font-mono">{dayNum}</span>
                        {isToday && (
                          <span className="text-[9px] bg-neutral-700 text-neutral-200 px-1 rounded-xs font-sans">
                            Today
                          </span>
                        )}
                      </div>
                    </div>
                  </th>
                );
              })}
            </tr>
          </thead>

          {/* Table Body: Rows = Visible Agents, Cells = Days */}
          <tbody className="bg-white divide-y divide-neutral-200">
            {visibleAgents.length === 0 ? (
              <tr>
                <td 
                  colSpan={daysList.length + 1}
                  className="py-16 text-center text-sm text-neutral-400 bg-white"
                >
                  All agents are currently hidden. Use the "All" button in the rail to show agents on canvas.
                </td>
              </tr>
            ) : (
              visibleAgents.map(agent => (
                <tr key={agent.id} className="hover:bg-neutral-50/30 transition-colors">
                  {/* Sticky Row Header (Left): Swatch, Name, Marker */}
                  <th 
                    className="sticky left-0 z-10 bg-white group-hover:bg-neutral-50 border-r border-b border-neutral-200 px-3 py-2 text-left font-medium w-48 min-w-48 shadow-[1px_0_0_0_rgba(0,0,0,0.06)]"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2 min-w-0">
                        {/* Swatch */}
                        <div 
                          className="w-2.5 h-2.5 rounded-xs shrink-0"
                          style={{ backgroundColor: agent.color }}
                        />

                        {/* Name */}
                        <span className="text-xs font-semibold text-neutral-900 truncate">
                          {agent.name}
                        </span>

                        {/* Marker Shape (§8) */}
                        {agent.kind === 'ai' ? (
                          <span 
                            className="text-[10px] text-purple-700 font-bold shrink-0"
                            title="AI Agent"
                          >
                            ◆
                          </span>
                        ) : (
                          <span 
                            className="text-[9px] text-neutral-400 font-bold shrink-0"
                            title="Person"
                          >
                            ●
                          </span>
                        )}
                      </div>

                      <span className="text-[10px] font-mono text-neutral-400 shrink-0">
                        {agent.dailyCapacityHours}h
                      </span>

                      {/* Visibility toggle — replaces the roster rail's per-agent eye icon */}
                      <button
                        type="button"
                        onClick={() => onToggleAgentVisibility(agent.id)}
                        className="p-0.5 rounded text-neutral-400 hover:text-neutral-800 hover:bg-neutral-200/60 transition-colors shrink-0"
                        title="Hide from grid"
                      >
                        <Eye className="w-3 h-3" />
                      </button>
                    </div>
                  </th>

                  {/* Day Cells for this Agent */}
                  {daysList.map(dateStr => {
                    const cellKey = `${agent.id}_${dateStr}`;
                    const dayLoad = calculateAgentDayLoad(agent, dateStr, timelines, tasks);
                    const timeline = dayLoad.timeline;
                    const hasTimeline = Boolean(timeline);
                    const isDragOver = dragOverCellKey === cellKey;
                    const isCellRefused = isDragOver && isDropRefused;
                    // Re-derives on every render from the *current* workspace window,
                    // so narrowing/widening the planning window immediately re-flags
                    // any timeline whose date now falls outside it (§3).
                    const isOutOfWindow = Boolean(
                      hasTimeline && timeline!.status !== 'published' && workspace &&
                      isDateOutOfWindow(dateStr, workspace.planningWindowStart, workspace.planningWindowEnd)
                    );

                    return (
                      <td
                        key={dateStr}
                        id={`grid-cell-${agent.id}-${dateStr}`}
                        onDragOver={(e) => handleCellDragOver(e, agent.id, dateStr, hasTimeline)}
                        onDragLeave={() => handleCellDragLeave(agent.id, dateStr)}
                        onDrop={(e) => handleCellDrop(e, agent.id, dateStr, timeline)}
                        className={`border-b border-r border-neutral-200 p-1.5 h-20 align-top transition-all relative ${
                          isCellRefused
                            ? 'bg-red-50 border-red-400 ring-2 ring-red-500/30'
                            : isDragOver
                            ? 'bg-neutral-100 ring-2 ring-neutral-900/20'
                            : hasTimeline
                            ? 'bg-white'
                            : 'bg-neutral-50/40 hover:bg-neutral-50'
                        }`}
                      >
                        {/* Refusal Overlay Banner (§4) */}
                        {isCellRefused && (
                          <div className="absolute inset-0 bg-red-950/90 text-white z-20 flex flex-col items-center justify-center p-1 text-center pointer-events-none animate-in fade-in duration-75">
                            <Ban className="w-4 h-4 text-red-300 mb-0.5" />
                            <span className="text-[10px] font-semibold text-red-100 leading-tight">
                              Refused: Occupied
                            </span>
                            <span className="text-[8px] text-red-300">
                              One per day
                            </span>
                          </div>
                        )}

                        {/* CASE A: FILLED CELL (Timeline exists for this agent on this day) */}
                        {hasTimeline && timeline ? (
                          <div
                            draggable={timeline.status !== 'published'}
                            onDragStart={(e) => handleCellDragStart(e, timeline, agent.id, dateStr)}
                            onDragEnd={handleCellDragEnd}
                            onClick={() => onOpenCellInPlan(dateStr, agent.id)}
                            className={`w-full h-full rounded p-1.5 flex flex-col justify-between cursor-pointer border transition-all shadow-2xs group ${
                              timeline.status === 'published'
                                ? 'bg-neutral-50/80 border-neutral-200 text-neutral-600'
                                : 'bg-white hover:border-neutral-400 hover:shadow-xs border-neutral-200/90'
                            }`}
                            style={{
                              borderLeftWidth: '3px',
                              borderLeftColor: agent.color,
                            }}
                            title={`Click to open ${formatShortDate(dateStr)} in Plan view`}
                          >
                            {/* Top row: Task count & Status */}
                            <div className="flex items-center justify-between gap-1">
                              <span className="text-[11px] font-semibold text-neutral-800 flex items-center gap-1">
                                {timeline.status !== 'published' && (
                                  <GripVertical className="w-2.5 h-2.5 text-neutral-300 group-hover:text-neutral-600 shrink-0 cursor-grab active:cursor-grabbing" />
                                )}
                                <span>{dayLoad.taskCount}</span>
                                <span className="text-[10px] text-neutral-400 hidden sm:inline">
                                  {dayLoad.taskCount === 1 ? 'task' : 'tasks'}
                                </span>
                              </span>

                              {/* Status Badge */}
                              <div className="flex items-center gap-1">
                                {dayLoad.isBlocked && (
                                  <span
                                    className="p-0.5 rounded bg-red-100 text-red-700"
                                    title={`Blocked Step: ${dayLoad.blockedReason || 'Step needs info'}`}
                                  >
                                    <AlertCircle className="w-2.5 h-2.5" />
                                  </span>
                                )}

                                {isOutOfWindow && (
                                  <span 
                                    className="p-0.5 rounded bg-red-100 text-red-700" 
                                    title="Blocked: planned date is outside the current planning window"
                                  >
                                    <Ban className="w-2.5 h-2.5" />
                                  </span>
                                )}

                                {dayLoad.isOverCapacity && (
                                  <span
                                    className="p-0.5 rounded bg-amber-100 text-amber-800"
                                    title={`Over Capacity (Warning): ${dayLoad.overCapacityReason}`}
                                  >
                                    <AlertTriangle className="w-2.5 h-2.5" />
                                  </span>
                                )}

                                {timeline.status === 'published' ? (
                                  <span
                                    className="inline-flex items-center gap-0.5 text-[9px] font-medium text-neutral-500 bg-neutral-100 px-1 py-0.2 rounded"
                                    title="Published (Locked) — read-only, tasks and sequencing can't be edited"
                                  >
                                    <Lock className="w-2 h-2" />
                                    <span>Pub</span>
                                  </span>
                                ) : (
                                  <span className="text-[9px] font-medium text-neutral-400">
                                    Draft
                                  </span>
                                )}
                              </div>
                            </div>

                            {/* Middle/Bottom: Planned load hours & thin fill line (§4, §5) */}
                            <div className="mt-auto pt-1">
                              <div className="flex items-center justify-between text-[10px] font-mono leading-none mb-1">
                                <span className={dayLoad.isOverCapacity ? 'text-amber-700 font-semibold' : 'text-neutral-600'}>
                                  {dayLoad.hoursFormatted}
                                </span>
                                <span className="text-neutral-400 text-[9px]">
                                  /{dayLoad.capacityHours}h
                                </span>
                              </div>

                              {/* Thin Fill Line (not a progress bar; planned load) */}
                              <div
                                className="w-full h-1 bg-neutral-100 rounded-full overflow-hidden"
                                title={
                                  dayLoad.isOverCapacity
                                    ? `Over Capacity (Warning): ${dayLoad.hoursFormatted} planned of ${dayLoad.capacityHours}h capacity`
                                    : `Planned Load: ${dayLoad.hoursFormatted} of ${dayLoad.capacityHours}h capacity`
                                }
                              >
                                <div
                                  className={`h-full rounded-full transition-all ${
                                    dayLoad.isOverCapacity
                                      ? 'bg-amber-500'
                                      : 'bg-neutral-800'
                                  }`}
                                  style={{
                                    width: `${Math.min(100, Math.round(dayLoad.loadRatio * 100))}%`,
                                  }}
                                />
                              </div>
                            </div>
                          </div>
                        ) : (
                          /* CASE B: EMPTY CELL (§4) */
                          <button
                            type="button"
                            onClick={() => onCreateTimelineForCell(agent.id, dateStr)}
                            className="w-full h-full rounded flex items-center justify-center text-neutral-300 hover:text-neutral-800 hover:bg-neutral-100/70 transition-all group"
                            title={`Click to start draft timeline for ${agent.name} on ${formatShortDate(dateStr)}`}
                          >
                            <span className="opacity-0 group-hover:opacity-100 transition-opacity p-1 bg-white rounded border border-neutral-200 text-xs shadow-2xs">
                              <Plus className="w-3.5 h-3.5 text-neutral-700" />
                            </span>
                          </button>
                        )}
                      </td>
                    );
                  })}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

    </div>
  );
}
