import React, {useEffect, useRef, useState} from 'react';
import {Plus, Trash2, MoreHorizontal, Pencil, X, Check, RotateCcw, Search, Copy} from 'lucide-react';
import {
  listScenarios,
  cloneScenario,
  updateJourneyMapMeta,
  deleteJourneyMap,
  type XanoScenario,
} from './xano';

function relativeTime(value: string | number | null | undefined): string {
  if (!value) return '—';
  const ms = typeof value === 'number' ? value : Date.parse(String(value));
  if (isNaN(ms)) return '—';
  const diff = Date.now() - ms;
  const secs = Math.floor(diff / 1000);
  if (secs < 60) return 'Just now';
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 30) return `${days}d ago`;
  return new Date(ms).toLocaleDateString();
}

interface RenameDialogProps {
  title: string;
  onSave: (newTitle: string) => void;
  onCancel: () => void;
}

function RenameDialog({title, onSave, onCancel}: RenameDialogProps) {
  const [value, setValue] = useState(title);
  return (
    <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50" onClick={onCancel}>
      <div className="bg-white rounded-2xl shadow-xl p-6 w-80" onClick={(e) => e.stopPropagation()}>
        <h3 className="text-sm font-semibold text-zinc-900 mb-4">Rename Scenario</h3>
        <input autoFocus
          className="w-full text-sm border border-zinc-300 rounded-lg px-3 py-2 outline-none focus:border-indigo-400"
          value={value} onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {if (e.key === 'Enter') onSave(value.trim()); if (e.key === 'Escape') onCancel();}} />
        <div className="flex gap-2 mt-4">
          <button onClick={() => onSave(value.trim())}
            className="flex-1 py-2 bg-zinc-900 text-white text-xs font-semibold rounded-lg hover:bg-zinc-800">Save</button>
          <button onClick={onCancel}
            className="flex-1 py-2 border border-zinc-200 text-xs text-zinc-600 rounded-lg hover:bg-zinc-50">Cancel</button>
        </div>
      </div>
    </div>
  );
}

interface KebabMenuProps {
  onRename: () => void;
  onDuplicate: () => void;
  onDelete: () => void;
}

function KebabMenu({onRename, onDuplicate, onDelete}: KebabMenuProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  return (
    <div ref={ref} className="relative" onClick={(e) => e.stopPropagation()}>
      <button onClick={() => setOpen((v) => !v)}
        className="p-1 rounded hover:bg-zinc-100 opacity-0 group-hover/row:opacity-100 transition-opacity">
        <MoreHorizontal className="w-4 h-4 text-zinc-400" />
      </button>
      {open && (
        <div className="absolute right-0 top-7 w-40 bg-white border border-zinc-200 rounded-lg shadow-lg z-20 py-1 text-xs">
          <button onClick={() => {onRename(); setOpen(false);}}
            className="flex items-center gap-2 w-full px-3 py-2 hover:bg-zinc-50 text-zinc-700">
            <Pencil className="w-3.5 h-3.5" />Rename
          </button>
          <button onClick={() => {onDuplicate(); setOpen(false);}}
            className="flex items-center gap-2 w-full px-3 py-2 hover:bg-zinc-50 text-zinc-700">
            <Copy className="w-3.5 h-3.5" />Duplicate
          </button>
          <div className="border-t border-zinc-100 my-1" />
          <button onClick={() => {onDelete(); setOpen(false);}}
            className="flex items-center gap-2 w-full px-3 py-2 hover:bg-rose-50 text-rose-600">
            <Trash2 className="w-3.5 h-3.5" />Delete
          </button>
        </div>
      )}
    </div>
  );
}

interface ScenariosTabProps {
  archId: number;
  onOpenScenario: (scenarioId: number) => void;
  onCreateBlank: () => Promise<void>;
  onCloneScenario: (sourceId: number, sourceTitle?: string) => Promise<void>;
  onCountChange?: (count: number) => void;
  onCompare: (mapAId: number, mapBId: number) => void;
}

export default function ScenariosTab({archId, onOpenScenario, onCreateBlank, onCloneScenario, onCountChange, onCompare}: ScenariosTabProps) {
  const [scenarios, setScenarios] = useState<XanoScenario[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isCreating, setIsCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [renamingScenario, setRenamingScenario] = useState<XanoScenario | null>(null);
  const [confirmDeleteId, setConfirmDeleteId] = useState<number | null>(null);

  const [showCreateModal, setShowCreateModal] = useState(false);

  const load = async () => {
    setIsLoading(true); setError(null);
    try {
      const data = await listScenarios(archId);
      setScenarios(data);
      onCountChange?.(data.length);
    }
    catch { setError('Unable to load scenarios. Please try again.'); }
    finally { setIsLoading(false); }
  };

  useEffect(() => { void load(); }, [archId]);

  const filtered = scenarios.filter((s) =>
    s.title.toLowerCase().includes(search.toLowerCase()),
  );

  const allChecked = filtered.length > 0 && filtered.every((s) => selected.has(s.id));
  const toggleAll = () => {
    if (allChecked) setSelected(new Set());
    else setSelected(new Set(filtered.map((s) => s.id)));
  };
  const toggleOne = (id: number) => {
    setSelected((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const handleRename = async (scenario: XanoScenario, newTitle: string) => {
    if (!newTitle || newTitle === scenario.title) {setRenamingScenario(null); return;}
    setScenarios((prev) => prev.map((s) => s.id === scenario.id ? {...s, title: newTitle} : s));
    setRenamingScenario(null);
    try { await updateJourneyMapMeta(scenario.id, {title: newTitle}); }
    catch { setScenarios((prev) => prev.map((s) => s.id === scenario.id ? scenario : s)); }
  };

  const handleDelete = async (id: number) => {
    setConfirmDeleteId(null);
    setScenarios((prev) => {
      const next = prev.filter((s) => s.id !== id);
      onCountChange?.(next.length);
      return next;
    });
    setSelected((prev) => { const next = new Set(prev); next.delete(id); return next; });
    try { await deleteJourneyMap(id); }
    catch { void load(); }
  };

  const handleDeleteSelected = async () => {
    const ids = Array.from(selected);
    setScenarios((prev) => {
      const next = prev.filter((s) => !ids.includes(s.id));
      onCountChange?.(next.length);
      return next;
    });
    setSelected(new Set());
    try { await Promise.all(ids.map((id) => deleteJourneyMap(id))); }
    catch { void load(); }
  };

  const handleDuplicate = async (scenario: XanoScenario) => {
    try {
      await onCloneScenario(scenario.id, scenario.title);
      await load();
    } catch {
      setError('Unable to duplicate scenario. Please try again.');
    }
  };

  const handleCreate = async () => {
    setIsCreating(true);
    setShowCreateModal(false);
    try { await onCreateBlank(); }
    finally { setIsCreating(false); }
  };

  if (isLoading) return (
    <div className="flex items-center justify-center py-24">
      <RotateCcw className="w-5 h-5 text-zinc-300 animate-spin" />
    </div>
  );

  return (
    <div className="pb-12">
      {/* Create Scenario modal */}
      {showCreateModal && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50" onClick={() => setShowCreateModal(false)}>
          <div className="bg-white rounded-2xl shadow-xl p-6 w-[420px]" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-sm font-semibold text-zinc-900 mb-1">How would you like to create a scenario?</h3>
            <p className="text-xs text-zinc-500 mb-5">Clone preserves all stages, lenses, and cell content from an existing scenario.</p>
            <div className="grid grid-cols-2 gap-3">
              {/* Clone path */}
              <div className="flex flex-col gap-3 p-4 border border-zinc-200 rounded-xl hover:border-zinc-300 transition-colors">
                <div className="w-8 h-8 rounded-lg bg-indigo-50 flex items-center justify-center">
                  <Copy className="w-4 h-4 text-indigo-600" />
                </div>
                <div>
                  <p className="text-xs font-semibold text-zinc-800">Clone from existing</p>
                  <p className="text-[11px] text-zinc-400 mt-0.5">Start from a copy of a scenario</p>
                </div>
                {scenarios.length > 0 ? (
                  <>
                    <select className="text-xs border border-zinc-200 rounded-lg px-2 py-1.5 outline-none focus:border-indigo-400 bg-white"
                      defaultValue={scenarios[0]?.id}>
                      {scenarios.map((s) => (
                        <option key={s.id} value={s.id}>{s.title}</option>
                      ))}
                    </select>
                    <button
                      onClick={(e) => {
                        const sel = (e.currentTarget.closest('.grid')?.querySelector('select') as HTMLSelectElement);
                        const sourceId = sel ? Number(sel.value) : scenarios[0]?.id;
                        const sourceScenario = scenarios.find((s) => s.id === sourceId);
                        setShowCreateModal(false);
                        void (async () => { await onCloneScenario(sourceId, sourceScenario?.title ?? 'Scenario'); await load(); })();
                      }}
                      className="mt-auto py-2 bg-indigo-600 text-white text-xs font-semibold rounded-lg hover:bg-indigo-700">
                      Clone Scenario
                    </button>
                  </>
                ) : (
                  <p className="text-[11px] text-zinc-400 italic">No existing scenarios to clone from.</p>
                )}
              </div>
              {/* Blank path */}
              <div className="flex flex-col gap-3 p-4 border border-zinc-200 rounded-xl hover:border-zinc-300 transition-colors">
                <div className="w-8 h-8 rounded-lg bg-zinc-100 flex items-center justify-center">
                  <Plus className="w-4 h-4 text-zinc-600" />
                </div>
                <div>
                  <p className="text-xs font-semibold text-zinc-800">Create blank</p>
                  <p className="text-[11px] text-zinc-400 mt-0.5">Start from scratch</p>
                </div>
                <button onClick={() => void handleCreate()}
                  className="mt-auto py-2 border border-zinc-200 text-zinc-700 text-xs font-semibold rounded-lg hover:bg-zinc-50">
                  Create Blank
                </button>
              </div>
            </div>
            <button onClick={() => setShowCreateModal(false)} className="mt-4 w-full py-1.5 text-xs text-zinc-400 hover:text-zinc-600">Cancel</button>
          </div>
        </div>
      )}

      {renamingScenario && (
        <RenameDialog
          title={renamingScenario.title}
          onSave={(t) => void handleRename(renamingScenario, t)}
          onCancel={() => setRenamingScenario(null)}
        />
      )}

      {confirmDeleteId !== null && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50"
          onClick={() => setConfirmDeleteId(null)}>
          <div className="bg-white rounded-2xl shadow-xl p-6 w-72" onClick={(e) => e.stopPropagation()}>
            <p className="text-sm font-semibold text-zinc-900 mb-1">Delete scenario?</p>
            <p className="text-xs text-zinc-500 mb-4">This cannot be undone.</p>
            <div className="flex gap-2">
              <button onClick={() => void handleDelete(confirmDeleteId)}
                className="flex-1 py-2 bg-rose-600 text-white text-xs font-semibold rounded-lg hover:bg-rose-700">Delete</button>
              <button onClick={() => setConfirmDeleteId(null)}
                className="flex-1 py-2 border border-zinc-200 text-xs text-zinc-600 rounded-lg hover:bg-zinc-50">Cancel</button>
            </div>
          </div>
        </div>
      )}

      {/* Toolbar — context-sensitive */}
      <div className="flex items-center gap-2 mb-4">
        {selected.size === 0 ? (
          /* No selection — show Create only */
          <button onClick={() => setShowCreateModal(true)} disabled={isCreating}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-zinc-900 text-white text-xs font-semibold rounded-lg hover:bg-zinc-800 disabled:opacity-60 transition-colors">
            {isCreating ? <RotateCcw className="w-3.5 h-3.5 animate-spin" /> : <Plus className="w-3.5 h-3.5" />}
            Create Scenario
          </button>
        ) : (
          /* 1+ selected — show Compare (only at exactly 2) + Delete */
          <>
            {selected.size === 2 && (
              <button
                onClick={() => {
                  const [a, b] = Array.from(selected);
                  onCompare(a, b);
                }}
                className="px-3 py-1.5 text-xs font-semibold border border-indigo-300 bg-indigo-50 text-indigo-700 rounded-lg hover:bg-indigo-100 transition-colors">
                Compare
              </button>
            )}
            <button onClick={() => void handleDeleteSelected()}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold border border-rose-200 text-rose-600 rounded-lg hover:bg-rose-50 transition-colors">
              <Trash2 className="w-3.5 h-3.5" />
              Delete ({selected.size})
            </button>
          </>
        )}
        <div className="ml-auto flex items-center gap-1.5 border border-zinc-200 rounded-lg px-2.5 py-1.5">
          <Search className="w-3.5 h-3.5 text-zinc-400 shrink-0" />
          <input
            className="text-xs outline-none bg-transparent placeholder:text-zinc-400 w-40"
            placeholder="Search scenarios…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          {search && (
            <button onClick={() => setSearch('')} className="text-zinc-400 hover:text-zinc-600">
              <X className="w-3 h-3" />
            </button>
          )}
        </div>
      </div>

      {error && (
        <div className="mb-4 flex items-center justify-between px-4 py-3 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-700">
          <span>{error}</span>
          <button onClick={() => void load()} className="font-semibold hover:underline ml-4">Retry</button>
        </div>
      )}

      {/* Empty state */}
      {scenarios.length === 0 && !error ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <p className="text-sm font-semibold text-zinc-600 mb-2">No scenarios yet</p>
          <p className="text-xs text-zinc-400 mb-6">Create your first scenario to start exploring what-if changes.</p>
          <button onClick={() => setShowCreateModal(true)} disabled={isCreating}
            className="inline-flex items-center gap-1.5 px-4 py-2 bg-zinc-900 text-white text-xs font-semibold rounded-xl hover:bg-zinc-800 disabled:opacity-60">
            {isCreating ? <RotateCcw className="w-3.5 h-3.5 animate-spin" /> : <Plus className="w-3.5 h-3.5" />}
            Create your first scenario
          </button>
        </div>
      ) : filtered.length === 0 && search ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <p className="text-sm text-zinc-500 mb-3">No scenarios match &ldquo;{search}&rdquo;</p>
          <button onClick={() => setSearch('')} className="text-xs font-semibold text-indigo-600 hover:underline">Clear search</button>
        </div>
      ) : (
        /* Table */
        <div className="border border-zinc-200 rounded-xl overflow-hidden bg-white">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-zinc-200 bg-zinc-50">
                <th className="w-10 px-4 py-3">
                  <input type="checkbox" checked={allChecked} onChange={toggleAll}
                    className="accent-zinc-800 w-3.5 h-3.5" />
                </th>
                <th className="text-left px-4 py-3 font-semibold text-zinc-500 uppercase tracking-wider">Name</th>
                <th className="text-left px-4 py-3 font-semibold text-zinc-500 uppercase tracking-wider">Owner</th>
                <th className="text-left px-4 py-3 font-semibold text-zinc-500 uppercase tracking-wider">Created</th>
                <th className="text-left px-4 py-3 font-semibold text-zinc-500 uppercase tracking-wider">Last Modified</th>
                <th className="w-10 px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {filtered.map((scenario, i) => (
                <tr key={scenario.id}
                  className={`group/row border-b border-zinc-100 last:border-0 hover:bg-zinc-50 transition-colors ${i % 2 === 0 ? '' : 'bg-zinc-50/40'}`}>
                  <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                    <input type="checkbox" checked={selected.has(scenario.id)}
                      onChange={() => toggleOne(scenario.id)}
                      className="accent-zinc-800 w-3.5 h-3.5" />
                  </td>
                  <td className="px-4 py-3">
                    <button onClick={() => onOpenScenario(scenario.id)}
                      className="font-semibold text-zinc-800 hover:text-indigo-700 transition-colors text-left">
                      {scenario.title}
                    </button>
                    {!!scenario.cloned_from_map_id && (
                      <span className="ml-2 text-[10px] text-zinc-400 italic">clone</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-zinc-500">{scenario.owner_name}</td>
                  <td className="px-4 py-3 text-zinc-400">{relativeTime(scenario.created_at)}</td>
                  <td className="px-4 py-3 text-zinc-400">{relativeTime(scenario.updated_at)}</td>
                  <td className="px-4 py-3">
                    <KebabMenu
                      onRename={() => setRenamingScenario(scenario)}
                      onDuplicate={() => void handleDuplicate(scenario)}
                      onDelete={() => setConfirmDeleteId(scenario.id)}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
