import { useState, useRef, useEffect } from 'react';
import { 
  ChevronDown, 
  Check, 
  Plus, 
  Edit2,
  Trash2,
  CalendarRange,
  SlidersHorizontal
} from 'lucide-react';
import { Workspace } from '../types';
import { formatShortDate, getDaysDifference } from '../utils/dateUtils';

interface HeaderProps {
  workspaces: Workspace[];
  activeWorkspace: Workspace | null;
  onSelectWorkspace: (id: string) => void;
  onCreateWorkspace: (name: string) => void;
  onRenameWorkspace: (id: string, newName: string) => void;
  onDeleteWorkspace: (id: string) => void;
  onOpenWorkspaceSettings: () => void;
}

export function Header({
  workspaces,
  activeWorkspace,
  onSelectWorkspace,
  onCreateWorkspace,
  onRenameWorkspace,
  onDeleteWorkspace,
  onOpenWorkspaceSettings,
}: HeaderProps) {
  // Workspace dropdown state
  const [isWsDropdownOpen, setIsWsDropdownOpen] = useState(false);
  const [isCreatingWs, setIsCreatingWs] = useState(false);
  const [newWsName, setNewWsName] = useState('');
  const [editingWsId, setEditingWsId] = useState<string | null>(null);
  const [editWsName, setEditWsName] = useState('');

  // Planning window popover state (Section 1)
  const [windowStart, setWindowStart] = useState(activeWorkspace?.planningWindowStart || '2026-10-12');
  const [windowEnd, setWindowEnd] = useState(activeWorkspace?.planningWindowEnd || '2026-10-25');


  const dropdownRef = useRef<HTMLDivElement>(null);

  // Sync window dates when workspace changes
  useEffect(() => {
    if (activeWorkspace) {
      setWindowStart(activeWorkspace.planningWindowStart || '2026-10-12');
      setWindowEnd(activeWorkspace.planningWindowEnd || '2026-10-25');
    }
  }, [activeWorkspace?.id, activeWorkspace?.planningWindowStart, activeWorkspace?.planningWindowEnd]);

  // Close dropdown on outside click
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsWsDropdownOpen(false);
        setIsCreatingWs(false);
        setEditingWsId(null);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const windowDays = getDaysDifference(windowStart, windowEnd);

  const handleStartCreateWs = () => {
    setIsCreatingWs(true);
    setNewWsName('');
  };

  const handleConfirmCreateWs = () => {
    if (newWsName.trim()) {
      onCreateWorkspace(newWsName.trim());
      setIsCreatingWs(false);
      setNewWsName('');
      setIsWsDropdownOpen(false);
    }
  };

  const handleStartRenameWs = (ws: Workspace, e: React.MouseEvent) => {
    e.stopPropagation();
    setEditingWsId(ws.id);
    setEditWsName(ws.name);
  };

  const handleConfirmRenameWs = (id: string, e?: React.MouseEvent | React.FormEvent) => {
    if (e) e.stopPropagation();
    if (editWsName.trim()) {
      onRenameWorkspace(id, editWsName.trim());
      setEditingWsId(null);
    }
  };

  const handleDeleteWs = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (confirm('Delete this workspace and all associated timelines?')) {
      onDeleteWorkspace(id);
    }
  };

  return (
    <header 
      id="app-header" 
      className="h-14 border-b border-neutral-200 bg-white px-4 flex items-center justify-between z-20 shrink-0 select-none"
    >
      {/* Left zone — identity. flex-1 with a matching flex-1 right zone is
          what lets the centre element sit at true centre, instead of
          drifting with the width of whatever sits either side of it. */}
      <div className="flex-1 flex items-center gap-3 min-w-0">
        {/* Workspace Switcher */}
        <div className="relative" ref={dropdownRef}>
          <button
            id="workspace-switcher-btn"
            onClick={() => setIsWsDropdownOpen(!isWsDropdownOpen)}
            className="flex items-center gap-2 px-2.5 py-1.5 rounded-md hover:bg-neutral-100 text-neutral-900 font-semibold text-sm transition-colors border border-transparent hover:border-neutral-200"
            aria-expanded={isWsDropdownOpen}
            aria-haspopup="true"
          >
            <span className="truncate max-w-[200px] text-left">
              {activeWorkspace ? activeWorkspace.name : 'Select Workspace'}
            </span>
            <ChevronDown className="w-3.5 h-3.5 text-neutral-500 shrink-0" />
          </button>

          {/* Workspace Dropdown */}
          {isWsDropdownOpen && (
            <div 
              id="workspace-dropdown-menu"
              className="absolute left-0 top-full mt-1.5 w-72 bg-white rounded-lg shadow-xl border border-neutral-200 py-1.5 z-50 text-xs"
            >
              <div className="px-3 py-1 font-semibold text-[11px] text-neutral-400 uppercase tracking-wider">
                Workspaces
              </div>

              <div className="max-h-60 overflow-y-auto py-1">
                {workspaces.map((ws) => (
                  <div
                    key={ws.id}
                    id={`workspace-item-${ws.id}`}
                    onClick={() => {
                      onSelectWorkspace(ws.id);
                      setIsWsDropdownOpen(false);
                    }}
                    className={`px-3 py-2 flex items-center justify-between hover:bg-neutral-50 cursor-pointer group ${
                      ws.id === activeWorkspace?.id ? 'bg-neutral-50 font-medium text-neutral-900' : 'text-neutral-700'
                    }`}
                  >
                    {editingWsId === ws.id ? (
                      <div className="flex items-center gap-1.5 w-full" onClick={(e) => e.stopPropagation()}>
                        <input
                          type="text"
                          value={editWsName}
                          onChange={(e) => setEditWsName(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') handleConfirmRenameWs(ws.id, e);
                            if (e.key === 'Escape') setEditingWsId(null);
                          }}
                          className="w-full px-2 py-0.5 text-xs border border-neutral-300 rounded focus:outline-none focus:border-neutral-900"
                          autoFocus
                        />
                        <button
                          onClick={(e) => handleConfirmRenameWs(ws.id, e)}
                          className="p-1 text-neutral-700 hover:text-black rounded"
                          title="Save"
                        >
                          <Check className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    ) : (
                      <>
                        <div className="flex items-center gap-2 truncate">
                          {ws.id === activeWorkspace?.id && (
                            <Check className="w-3.5 h-3.5 text-neutral-900 shrink-0" />
                          )}
                          <span className={`truncate ${ws.id === activeWorkspace?.id ? 'ml-0' : 'ml-5.5'}`}>
                            {ws.name}
                          </span>
                        </div>
                        <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            onClick={(e) => handleStartRenameWs(ws, e)}
                            className="p-1 text-neutral-400 hover:text-neutral-700 rounded"
                            title="Rename"
                          >
                            <Edit2 className="w-3.5 h-3.5" />
                          </button>
                          {workspaces.length > 1 && (
                            <button
                              onClick={(e) => handleDeleteWs(ws.id, e)}
                              className="p-1 text-neutral-400 hover:text-red-600 rounded"
                              title="Delete"
                            >
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          )}
                        </div>
                      </>
                    )}
                  </div>
                ))}
              </div>

              {/* Create Workspace Row */}
              <div className="border-t border-neutral-100 pt-1.5 px-2">
                {isCreatingWs ? (
                  <div className="flex items-center gap-1.5 py-1">
                    <input
                      type="text"
                      placeholder="Workspace name..."
                      value={newWsName}
                      onChange={(e) => setNewWsName(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') handleConfirmCreateWs();
                        if (e.key === 'Escape') setIsCreatingWs(false);
                      }}
                      className="flex-1 px-2.5 py-1 text-xs border border-neutral-300 rounded focus:outline-none focus:border-neutral-900"
                      autoFocus
                    />
                    <button
                      onClick={handleConfirmCreateWs}
                      disabled={!newWsName.trim()}
                      className="px-2 py-1 bg-neutral-900 text-white rounded text-xs hover:bg-neutral-800 disabled:opacity-50"
                    >
                      Add
                    </button>
                  </div>
                ) : (
                  <button
                    id="create-workspace-dropdown-btn"
                    onClick={handleStartCreateWs}
                    className="w-full text-left px-2 py-1.5 text-xs text-neutral-600 hover:text-neutral-900 hover:bg-neutral-50 rounded flex items-center gap-1.5 font-medium"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    New Workspace
                  </button>
                )}
              </div>
            </div>
          )}
        </div>

      </div>

      {/* Right zone — workspace configuration. Widths are matched to the
          toolbar cluster directly below (window chip spans Build Plan +
          Agents; settings matches the week toggle) so every vertical edge
          in the two rows lines up instead of almost lining up. */}
      <div className="flex items-center justify-end gap-2 shrink-0">
        <button
          id="planning-window-btn"
          onClick={onOpenWorkspaceSettings}
          className="w-[229px] flex items-center justify-center gap-1.5 px-2 py-1.5 rounded-md text-xs font-mono text-neutral-700 bg-neutral-100 hover:bg-neutral-200/70 border border-neutral-200 transition-colors shrink-0"
          title="Planning window — click to edit in Workspace Settings"
        >
          <CalendarRange className="w-3.5 h-3.5 text-neutral-500 shrink-0" />
          <span className="truncate">
            {formatShortDate(windowStart)} – {formatShortDate(windowEnd)} · {windowDays} days
          </span>
        </button>

        <button
          id="workspace-settings-btn"
          onClick={onOpenWorkspaceSettings}
          className="w-[161px] flex items-center justify-center gap-1.5 px-2 py-1.5 rounded-md text-xs font-medium text-neutral-700 bg-white hover:bg-neutral-100 hover:text-neutral-900 border border-neutral-300 hover:border-neutral-400 transition-colors shadow-2xs shrink-0"
          title="Workspace settings — planning window & AI throughput"
        >
          <SlidersHorizontal className="w-3.5 h-3.5 text-neutral-500 shrink-0" />
          <span className="truncate">Workspace Settings</span>
        </button>
      </div>

    </header>
  );
}
