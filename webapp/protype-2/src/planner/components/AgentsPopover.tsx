import { useState, useRef, useEffect } from 'react';
import { ChevronDown, Users, Search, Eye, EyeOff, Pencil, Plus, AlertTriangle } from 'lucide-react';
import { Agent } from '../types';

interface AgentsPopoverProps {
  agents: Agent[];
  onToggleAgentVisibility: (agentId: string) => void;
  onShowAllAgents: () => void;
  onHideAllAgents: () => void;
  onOpenAddAgentModal: () => void;
  onEditAgent: (agentId: string) => void;
  hideLabel?: string;
  showLabel?: string;
}

/**
 * On-demand roster controls (visibility, search, edit, add) shared by the
 * Plan and Schedule views, in place of a permanently pinned roster rail.
 *
 * GAP-FIX W2 — a person with no login linked is flagged here. This is
 * the one place the whole roster is visible at once, so it is where a
 * planner can see at a glance that a day they are about to fill would
 * reach nobody. AI agents are never flagged: they have no login by
 * definition and are not performed through the Execution app.
 */
export function AgentsPopover({
  agents,
  onToggleAgentVisibility,
  onShowAllAgents,
  onHideAllAgents,
  onOpenAddAgentModal,
  onEditAgent,
  hideLabel = 'Hide from grid',
  showLabel = 'Show on grid',
}: AgentsPopoverProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [query, setQuery] = useState('');
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!isOpen) return;
    const handleClickOutside = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setIsOpen(false);
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isOpen]);

  const filtered = agents.filter(a =>
    a.name.toLowerCase().includes(query.toLowerCase()) ||
    a.kind.toLowerCase().includes(query.toLowerCase())
  );

  return (
    <div className="relative" ref={ref}>
      <button
        id="grid-agents-popover-btn"
        type="button"
        onClick={() => setIsOpen(prev => !prev)}
        className="flex items-center gap-1.5 px-2.5 py-1 rounded border border-neutral-200 bg-neutral-100 hover:bg-neutral-200/70 text-xs font-medium text-neutral-700 hover:text-neutral-900 transition-colors"
        aria-expanded={isOpen}
        title="Show/hide agents, search the roster, or add an agent"
      >
        <Users className="w-3.5 h-3.5" />
        Agents ({agents.length})
        <ChevronDown className="w-3 h-3 text-neutral-400" />
      </button>

      {isOpen && (
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
                value={query}
                onChange={(e) => setQuery(e.target.value)}
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
            {filtered.length === 0 ? (
              <div className="py-6 text-center text-neutral-400">No agents match filter</div>
            ) : (
              filtered.map(agent => (
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
                    {agent.kind === 'person' && !agent.userId && (
                      <span
                        className="shrink-0 text-amber-600"
                        title="No login linked — nobody will see this agent's work in Execution"
                      >
                        <AlertTriangle className="w-3 h-3" />
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-0.5 shrink-0">
                    <button
                      type="button"
                      onClick={() => { setIsOpen(false); onEditAgent(agent.id); }}
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
                      title={agent.isVisible ? hideLabel : showLabel}
                    >
                      {agent.isVisible ? <Eye className="w-3.5 h-3.5" /> : <EyeOff className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>

          {filtered.some(a => a.kind === 'person' && !a.userId) && (
            <div className="border-t border-neutral-100 px-2.5 py-1.5 flex items-start gap-1.5 text-[10px] text-amber-700 bg-amber-50/60">
              <AlertTriangle className="w-3 h-3 mt-0.5 shrink-0" />
              <span>Agents marked ⚠ have no login. Their published days reach nobody — open the agent to link one.</span>
            </div>
          )}

          <div className="border-t border-neutral-100 p-1.5">
            <button
              type="button"
              onClick={() => { setIsOpen(false); onOpenAddAgentModal(); }}
              className="w-full text-left px-2 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50 rounded flex items-center gap-1.5 font-medium"
            >
              <Plus className="w-3.5 h-3.5" />
              Add agent
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
