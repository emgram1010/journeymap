import { useState } from 'react';
import { 
  Plus, 
  Search, 
  Eye, 
  EyeOff, 
  AlertCircle, 
  AlertTriangle,
  User, 
  Sparkles,
  Bot,
  Layers,
  Check,
  Calendar,
  Lock,
  Focus,
  Pencil
} from 'lucide-react';
import { Agent, Timeline, Task } from '../types';
import { calculateAgentDayLoad } from '../utils/agentUtils';

interface AgentRosterRailProps {
  agents: Agent[];
  timelines: Timeline[];
  tasks: Task[];
  activeDate: string;
  activeAgentId: string | null;
  focusedAgentId: string | null;
  onSelectAgent: (agentId: string) => void;
  onFocusAgent: (agentId: string) => void;
  onToggleAgentVisibility: (agentId: string) => void;
  onEditAgent: (agentId: string) => void;
  onShowAllAgents: () => void;
  onHideAllAgents: () => void;
  onOpenAddAgentModal: () => void;
  onDropTaskOnAgent?: (taskId: string, agentId: string) => void;
}

export function AgentRosterRail({
  agents,
  timelines,
  tasks,
  activeDate,
  activeAgentId,
  focusedAgentId,
  onSelectAgent,
  onFocusAgent,
  onToggleAgentVisibility,
  onEditAgent,
  onShowAllAgents,
  onHideAllAgents,
  onOpenAddAgentModal,
  onDropTaskOnAgent,
}: AgentRosterRailProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [dragOverAgentId, setDragOverAgentId] = useState<string | null>(null);

  // Filter agents by search query
  const filteredAgents = agents.filter(agent =>
    agent.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    agent.kind.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const totalVisibleCount = agents.filter(a => a.isVisible).length;

  const handleDragOverAgent = (e: React.DragEvent, agentId: string) => {
    e.preventDefault();
    e.stopPropagation();
    if (dragOverAgentId !== agentId) {
      setDragOverAgentId(agentId);
    }
  };

  const handleDragLeaveAgent = (agentId: string) => {
    if (dragOverAgentId === agentId) {
      setDragOverAgentId(null);
    }
  };

  const handleDropOnAgent = (e: React.DragEvent, agentId: string) => {
    e.preventDefault();
    e.stopPropagation();
    setDragOverAgentId(null);

    try {
      const dataStr = e.dataTransfer.getData('application/json') || e.dataTransfer.getData('text/plain');
      if (!dataStr) return;
      const data = JSON.parse(dataStr);
      if (data.type === 'backlog-task' && data.taskId) {
        onDropTaskOnAgent?.(data.taskId, agentId);
      }
    } catch (err) {
      console.error('Failed to parse drag payload onto agent:', err);
    }
  };

  return (
    <aside 
      id="agent-roster-rail" 
      className="w-72 border-r border-neutral-200 bg-white flex flex-col h-full shrink-0 select-none"
    >
      {/* Rail Header */}
      <div className="p-3 border-b border-neutral-200 flex flex-col gap-2.5 bg-white">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-xs font-semibold text-neutral-900 tracking-tight">
              Agents ({agents.length})
            </span>
            <span className="text-[11px] font-normal text-neutral-400">
              {totalVisibleCount} visible
            </span>
          </div>

          <button
            id="add-agent-btn"
            type="button"
            onClick={onOpenAddAgentModal}
            className="flex items-center gap-1 px-2 py-1 bg-neutral-900 hover:bg-neutral-800 text-white rounded text-xs font-medium transition-colors shadow-2xs"
            title="Add agent to roster"
          >
            <Plus className="w-3.5 h-3.5" />
            <span>Add agent</span>
          </button>
        </div>

        {/* Quick Search & Toggle Bar */}
        <div className="flex items-center gap-1.5">
          <div className="relative flex-1">
            <Search className="w-3 h-3 absolute left-2 top-2 text-neutral-400" />
            <input
              id="roster-search-input"
              type="text"
              placeholder="Search roster..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-6 pr-2 py-1 text-xs bg-neutral-50 border border-neutral-200 rounded focus:bg-white focus:border-neutral-400 focus:outline-none placeholder:text-neutral-400"
            />
          </div>

          <div className="flex items-center gap-0.5 border border-neutral-200 rounded p-0.5 bg-neutral-50">
            <button
              id="show-all-agents-btn"
              type="button"
              onClick={onShowAllAgents}
              className="px-1.5 py-0.5 text-[10px] font-medium text-neutral-600 hover:text-neutral-900 hover:bg-white rounded transition-colors"
              title="Show all agents on canvas"
            >
              All
            </button>
            <span className="text-neutral-300 text-[10px]">|</span>
            <button
              id="hide-all-agents-btn"
              type="button"
              onClick={onHideAllAgents}
              className="px-1.5 py-0.5 text-[10px] font-medium text-neutral-600 hover:text-neutral-900 hover:bg-white rounded transition-colors"
              title="Hide all agents from canvas"
            >
              None
            </button>
          </div>
        </div>
      </div>

      {/* Agents Roster List */}
      <div id="roster-agent-list" className="flex-1 overflow-y-auto divide-y divide-neutral-100 p-2 space-y-1">
        {filteredAgents.length === 0 ? (
          <div className="py-8 text-center text-xs text-neutral-400">
            {searchQuery ? 'No agents match filter' : 'No agents in roster'}
          </div>
        ) : (
          filteredAgents.map(agent => {
            // Blocked/Over badges reflect the day currently on screen, not
            // the whole visible window (Story C2) — a badge here always
            // describes the agent's activeDate, never a different day.
            const dayLoad = calculateAgentDayLoad(agent, activeDate, timelines, tasks);
            const isFocused = focusedAgentId === agent.id;
            const isDragOver = dragOverAgentId === agent.id;

            return (
              <div
                key={agent.id}
                id={`roster-agent-${agent.id}`}
                onDragOver={(e) => handleDragOverAgent(e, agent.id)}
                onDragLeave={() => handleDragLeaveAgent(agent.id)}
                onDrop={(e) => handleDropOnAgent(e, agent.id)}
                className={`group relative rounded-md p-2 transition-all border ${
                  isDragOver
                    ? 'border-neutral-900 bg-neutral-100 ring-2 ring-neutral-900/10'
                    : isFocused
                    ? 'border-neutral-900 bg-neutral-50 shadow-2xs'
                    : agent.isVisible
                    ? 'border-neutral-200/70 bg-white hover:border-neutral-300 hover:bg-neutral-50/50'
                    : 'border-neutral-100 bg-neutral-50/40 opacity-60 hover:opacity-100'
                }`}
              >
                <div className="flex items-center justify-between gap-2">
                  {/* Left: Swatch + Name + Marker */}
                  <div 
                    className="flex items-center gap-2 min-w-0 cursor-pointer flex-1"
                    onClick={() => onFocusAgent(agent.id)}
                    title={`Click to focus on ${agent.name} (full detailed table)`}
                  >
                    {/* Identity Swatch */}
                    <div 
                      className="w-3 h-3 rounded-xs shrink-0 shadow-2xs"
                      style={{ backgroundColor: agent.color }}
                      title={`Identity color: ${agent.color}`}
                    />

                    {/* Agent Name */}
                    <span className={`text-xs truncate font-medium ${
                      isFocused ? 'text-neutral-950 font-semibold' : 'text-neutral-800'
                    }`}>
                      {agent.name}
                    </span>

                    {/* Person / AI Marker Shape (§8) */}
                    {agent.kind === 'ai' ? (
                      <span 
                        className="inline-flex items-center gap-0.5 px-1 py-0.2 text-[10px] font-medium text-purple-700 bg-purple-50 border border-purple-200 rounded shrink-0"
                        title="Automated AI Agent (Diamond marker)"
                      >
                        <span className="text-[9px]">◆</span>
                        <span>AI</span>
                      </span>
                    ) : (
                      <span 
                        className="inline-flex items-center gap-0.5 px-1 py-0.2 text-[10px] font-medium text-neutral-600 bg-neutral-100 border border-neutral-200 rounded shrink-0"
                        title="Person (User marker)"
                      >
                        <User className="w-2.5 h-2.5 text-neutral-500" />
                        <span>P</span>
                      </span>
                    )}
                  </div>

                  {/* Right: Edit + Show/Hide Toggle */}
                  <div className="flex items-center gap-1 shrink-0">
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onEditAgent(agent.id);
                      }}
                      className="p-1 rounded text-neutral-400 hover:text-neutral-800 hover:bg-neutral-200/60 transition-colors opacity-0 group-hover:opacity-100"
                      title="Edit agent (capacity, model, colour)"
                    >
                      <Pencil className="w-3.5 h-3.5" />
                    </button>
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onToggleAgentVisibility(agent.id);
                      }}
                      className={`p-1 rounded hover:bg-neutral-200/60 transition-colors ${
                        agent.isVisible ? 'text-neutral-600' : 'text-neutral-400'
                      }`}
                      title={agent.isVisible ? 'Hide agent from canvas' : 'Show agent on canvas'}
                    >
                      {agent.isVisible ? (
                        <Eye className="w-3.5 h-3.5" />
                      ) : (
                        <EyeOff className="w-3.5 h-3.5 text-neutral-400" />
                      )}
                    </button>
                  </div>
                </div>

                {/* Sub-row: Attention markers (§3, §5) — capacity totals live on the Schedule Grid, not here */}
                <div className="mt-1.5 flex items-center justify-between text-[11px] text-neutral-500 pt-1 border-t border-neutral-100">
                  <div className="flex items-center gap-1.5">
                    <span className="text-neutral-400">
                      {agent.dailyCapacityHours}h/day
                    </span>
                  </div>

                  {/* Attention Markers — describe activeDate specifically */}
                  <div className="flex items-center gap-1">
                    {/* Blocked marker (needs info) */}
                    {dayLoad.isBlocked && (
                      <span
                        className="inline-flex items-center gap-0.5 px-1 py-0.2 text-[10px] font-medium text-red-700 bg-red-50 border border-red-200 rounded"
                        title={`Attention: ${dayLoad.blockedReason || 'This day has a blocked step (needs info)'}`}
                      >
                        <AlertCircle className="w-2.5 h-2.5 text-red-600" />
                        <span>Blocked</span>
                      </span>
                    )}

                    {/* Over capacity warning (signal, not blocking) */}
                    {dayLoad.isOverCapacity && (
                      <span
                        className="inline-flex items-center gap-0.5 px-1 py-0.2 text-[10px] font-medium text-amber-700 bg-amber-50 border border-amber-200 rounded"
                        title={dayLoad.overCapacityReason || 'Notice: Planned load exceeds capacity on this day'}
                      >
                        <AlertTriangle className="w-2.5 h-2.5 text-amber-600" />
                        <span>Over</span>
                      </span>
                    )}

                    {isFocused && (
                      <span className="text-[10px] font-semibold text-neutral-900 bg-neutral-200/80 px-1 rounded">
                        Focused
                      </span>
                    )}
                  </div>
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* Rail Footer Information */}
      <div className="p-2.5 border-t border-neutral-200 bg-neutral-50/70 text-[11px] text-neutral-500 flex items-center justify-between">
        <span className="truncate">One timeline per agent/day</span>
        <span className="font-mono text-neutral-400 text-[10px]">v3 Roster</span>
      </div>
    </aside>
  );
}
