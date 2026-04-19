import React, {useEffect, useRef, useState} from 'react';
import {useNavigate, useParams} from 'react-router-dom';
import ArchitectureGraph from './ArchitectureGraph';
import {Plus, RotateCcw, MoreHorizontal, Pencil, Archive, Trash2, Check, X, ArrowLeft, LayoutGrid, ArrowRight, Network} from 'lucide-react';
import {
  loadJourneyArchitectureBundle,
  updateJourneyArchitecture,
  deleteJourneyArchitecture,
  createDraftJourneyMap,
  updateJourneyMapMeta,
  deleteJourneyMap,
  deleteJourneyLink,
  type XanoJourneyArchitecture,
  type XanoJourneyMap,
  type XanoJourneyLink,
  type JourneyArchitectureStatus,
  type JourneyMapStatus,
  type JourneyLinkType,
} from './xano';

function relativeTime(value: string | number | null | undefined): string {
  if (!value) return '';
  const ms = typeof value === 'number' ? value : Date.parse(String(value));
  if (isNaN(ms)) return '';
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

const MAP_STATUS_STYLES: Record<JourneyMapStatus, string> = {
  draft: 'bg-zinc-100 text-zinc-600',
  active: 'bg-emerald-50 text-emerald-700',
  archived: 'bg-amber-50 text-amber-700',
};

// ── Link type helpers ─────────────────────────────────────────────────────────
const LINK_TYPE_LABELS: Record<JourneyLinkType, string> = {
  exception: 'Exception',
  anti_journey: 'Anti-Journey',
  sub_journey: 'Sub-Journey',
};

const LINK_TYPE_ICONS: Record<JourneyLinkType, string> = {
  exception: '⚠',
  anti_journey: '↩',
  sub_journey: '⤵',
};

// ── Map tile (reused pattern from Dashboard) ─────────────────────────────────
interface MapTileProps {
  map: XanoJourneyMap;
  links: XanoJourneyLink[];
  allMaps: XanoJourneyMap[];
  onOpen: () => void;
  onRename: (title: string) => Promise<void>;
  onDelete: () => void;
  onArchive: () => void;
  onRemoveLink: (linkId: number) => Promise<void>;
}

function MapTile({map, links, allMaps, onOpen, onRename, onDelete, onArchive, onRemoveLink}: MapTileProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const [renameValue, setRenameValue] = useState(map.title);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [linkBadgeOpen, setLinkBadgeOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const linkBadgeRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (linkBadgeRef.current && !linkBadgeRef.current.contains(e.target as Node)) {
        setLinkBadgeOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setMenuOpen(false); setConfirmDelete(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const commitRename = async () => {
    const trimmed = renameValue.trim();
    if (!trimmed) {setRenameValue(map.title); setRenaming(false); return;}
    if (trimmed !== map.title) await onRename(trimmed);
    setRenaming(false);
  };

  const isArchived = map.status === 'archived';
  const ts = map.last_interaction_at ?? map.updated_at ?? map.created_at;

  return (
    <div
      onClick={!renaming ? onOpen : undefined}
      className={`group relative bg-white border border-zinc-200 rounded-xl shadow-sm hover:shadow-md hover:border-zinc-300 transition-all cursor-pointer flex flex-col ${isArchived ? 'opacity-60' : ''}`}
    >
      <div className={`h-1 rounded-t-xl ${isArchived ? 'bg-amber-300' : map.status === 'active' ? 'bg-emerald-400' : 'bg-zinc-300'}`} />
      <div className="p-4 flex-1 flex flex-col gap-2">
        {renaming ? (
          <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
            <input autoFocus className="flex-1 text-sm font-semibold text-zinc-900 border-b border-zinc-300 bg-transparent outline-none"
              value={renameValue} onChange={(e) => setRenameValue(e.target.value)}
              onKeyDown={(e) => {if (e.key === 'Enter') void commitRename(); if (e.key === 'Escape') {setRenameValue(map.title); setRenaming(false);}}} />
            <button onClick={() => void commitRename()} className="p-1 text-emerald-600"><Check className="w-3.5 h-3.5" /></button>
            <button onClick={() => {setRenameValue(map.title); setRenaming(false);}} className="p-1 text-zinc-400"><X className="w-3.5 h-3.5" /></button>
          </div>
        ) : (
          <h3 className="text-sm font-semibold text-zinc-900 truncate pr-6">{map.title}</h3>
        )}
        <div className="flex items-center gap-2 mt-auto pt-2">
          <span className={`text-[11px] font-medium px-2 py-0.5 rounded-full ${MAP_STATUS_STYLES[map.status]}`}>{map.status}</span>
          {/* Link badge */}
          {links.length > 0 && (
            <div ref={linkBadgeRef} className="relative" onClick={(e) => e.stopPropagation()}>
              <button onClick={() => setLinkBadgeOpen((v) => !v)}
                className="inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-full bg-indigo-50 text-indigo-600 hover:bg-indigo-100 transition-colors">
                <ArrowRight className="w-2.5 h-2.5" />{links.length}
              </button>
              {linkBadgeOpen && (
                <div className="absolute left-0 bottom-7 w-56 bg-white border border-zinc-200 rounded-xl shadow-lg z-20 py-1.5">
                  <p className="px-3 pb-1.5 text-[11px] font-semibold text-zinc-400 uppercase tracking-wider">Links out</p>
                  {links.map((link) => {
                    const target = allMaps.find((m) => m.id === link.target_map);
                    return (
                      <div key={link.id} className="flex items-center gap-2 px-3 py-1.5 hover:bg-zinc-50 group/link">
                        <span className="text-sm">{LINK_TYPE_ICONS[link.link_type]}</span>
                        <div className="flex-1 min-w-0">
                          <p className="text-xs font-medium text-zinc-700 truncate">{target?.title ?? `Map ${link.target_map}`}</p>
                          <p className="text-[11px] text-zinc-400">{LINK_TYPE_LABELS[link.link_type]}{link.label ? ` · ${link.label}` : ''}</p>
                        </div>
                        <button onClick={() => void onRemoveLink(link.id)}
                          className="opacity-0 group-hover/link:opacity-100 p-1 text-zinc-400 hover:text-rose-500 transition">
                          <X className="w-3 h-3" />
                        </button>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
          <span className="text-[11px] text-zinc-400 ml-auto">{relativeTime(ts)}</span>
        </div>
      </div>
      <div ref={menuRef} className="absolute top-3 right-3" onClick={(e) => e.stopPropagation()}>
        <button onClick={() => setMenuOpen((v) => !v)} className="p-1 rounded hover:bg-zinc-100 opacity-0 group-hover:opacity-100 transition-opacity">
          <MoreHorizontal className="w-4 h-4 text-zinc-500" />
        </button>
        {menuOpen && !confirmDelete && (
          <div className="absolute right-0 top-7 w-40 bg-white border border-zinc-200 rounded-lg shadow-lg z-10 py-1 text-xs">
            <button onClick={() => {setRenaming(true); setMenuOpen(false);}} className="flex items-center gap-2 w-full px-3 py-2 hover:bg-zinc-50 text-zinc-700"><Pencil className="w-3.5 h-3.5" />Rename</button>
            <button onClick={() => {onArchive(); setMenuOpen(false);}} className="flex items-center gap-2 w-full px-3 py-2 hover:bg-zinc-50 text-zinc-700"><Archive className="w-3.5 h-3.5" />{isArchived ? 'Unarchive' : 'Archive'}</button>
            <div className="border-t border-zinc-100 my-1" />
            <button onClick={() => setConfirmDelete(true)} className="flex items-center gap-2 w-full px-3 py-2 hover:bg-rose-50 text-rose-600"><Trash2 className="w-3.5 h-3.5" />Delete</button>
          </div>
        )}
        {menuOpen && confirmDelete && (
          <div className="absolute right-0 top-7 w-48 bg-white border border-zinc-200 rounded-lg shadow-lg z-10 p-3 text-xs">
            <p className="font-semibold text-zinc-800 mb-1">Delete map?</p>
            <p className="text-zinc-500 mb-3">This cannot be undone.</p>
            <div className="flex gap-2">
              <button onClick={() => {onDelete(); setMenuOpen(false);}} className="flex-1 py-1.5 bg-rose-600 text-white rounded-md font-medium hover:bg-rose-700">Delete</button>
              <button onClick={() => setConfirmDelete(false)} className="flex-1 py-1.5 border border-zinc-200 rounded-md text-zinc-600 hover:bg-zinc-50">Cancel</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}


const ARCH_STATUS_STYLES: Record<JourneyArchitectureStatus, string> = {
  draft: 'bg-zinc-100 text-zinc-600',
  active: 'bg-emerald-50 text-emerald-700',
  archived: 'bg-amber-50 text-amber-700',
};

export default function ArchitectureDetail() {
  const {id} = useParams<{id: string}>();
  const navigate = useNavigate();
  const archId = Number(id);

  const [arch, setArch] = useState<XanoJourneyArchitecture | null>(null);
  const [maps, setMaps] = useState<XanoJourneyMap[]>([]);
  const [links, setLinks] = useState<XanoJourneyLink[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isCreatingMap, setIsCreatingMap] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Link drawer state
  // Graph view toggle
  const [viewMode, setViewMode] = useState<'grid' | 'graph'>('grid');

  // Inline edit state for title / description
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleValue, setTitleValue] = useState('');
  const [editingDesc, setEditingDesc] = useState(false);
  const [descValue, setDescValue] = useState('');

  // Architecture kebab menu
  const [archMenuOpen, setArchMenuOpen] = useState(false);
  const [confirmDeleteArch, setConfirmDeleteArch] = useState(false);
  const archMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (archMenuRef.current && !archMenuRef.current.contains(e.target as Node)) {
        setArchMenuOpen(false); setConfirmDeleteArch(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const load = async () => {
    setIsLoading(true); setError(null);
    try {
      const bundle = await loadJourneyArchitectureBundle(archId);
      setArch(bundle.journey_architecture);
      setMaps(bundle.journey_maps);
      setLinks(bundle.journey_links ?? []);
      setTitleValue(bundle.journey_architecture.title ?? '');
      setDescValue(bundle.journey_architecture.description ?? '');
    } catch {
      setError('Unable to load architecture. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => { void load(); }, [archId]);

  const patchArch = async (data: Parameters<typeof updateJourneyArchitecture>[1]) => {
    if (!arch) return;
    const prev = arch;
    setArch((a) => a ? {...a, ...data} : a);
    try { const updated = await updateJourneyArchitecture(archId, data); setArch(updated); }
    catch { setArch(prev); }
  };

  const commitTitle = async () => {
    const trimmed = titleValue.trim();
    if (!trimmed) { setTitleValue(arch?.title ?? ''); setEditingTitle(false); return; }
    setEditingTitle(false);
    if (trimmed !== arch?.title) await patchArch({title: trimmed});
  };

  const commitDesc = async () => {
    setEditingDesc(false);
    const trimmed = descValue.trim();
    if (trimmed !== (arch?.description ?? '')) await patchArch({description: trimmed});
  };

  const handleArchiveArch = () => void patchArch({status: arch?.status === 'archived' ? 'draft' : 'archived'});

  const handleDeleteArch = async () => {
    try { await deleteJourneyArchitecture(archId); navigate('/architectures'); }
    catch { setError('Unable to delete architecture.'); }
  };

  const handleCreateMap = async () => {
    setIsCreatingMap(true);
    try {
      const bundle = await createDraftJourneyMap({
        title: 'Untitled Journey Map',
        status: 'draft',
        journey_architecture_id: archId,
      });
      navigate(`/maps/${bundle.journeyMap.id}?arch=${archId}`);
    } catch {
      setError('Unable to create journey map. Please try again.');
    } finally {
      setIsCreatingMap(false);
    }
  };

  const handleRenameMap = async (mapId: number, title: string) => {
    const prev = maps.find((m) => m.id === mapId);
    setMaps((ms) => ms.map((m) => (m.id === mapId ? {...m, title} : m)));
    try { await updateJourneyMapMeta(mapId, {title}); }
    catch { if (prev) setMaps((ms) => ms.map((m) => (m.id === mapId ? prev : m))); }
  };

  const handleArchiveMap = async (map: XanoJourneyMap) => {
    const next: JourneyMapStatus = map.status === 'archived' ? 'draft' : 'archived';
    setMaps((ms) => ms.map((m) => (m.id === map.id ? {...m, status: next} : m)));
    try { await updateJourneyMapMeta(map.id, {status: next}); }
    catch { setMaps((ms) => ms.map((m) => (m.id === map.id ? map : m))); }
  };

  const handleDeleteMap = async (mapId: number) => {
    const prev = maps.find((m) => m.id === mapId);
    setMaps((ms) => ms.filter((m) => m.id !== mapId));
    // Also remove any links involving this map from local state
    setLinks((ls) => ls.filter((l) => l.source_map !== mapId && l.target_map !== mapId));
    try { await deleteJourneyMap(mapId); }
    catch { if (prev) setMaps((ms) => [prev, ...ms]); }
  };

  const handleRemoveLink = async (linkId: number) => {
    const prev = links.find((l) => l.id === linkId);
    setLinks((ls) => ls.filter((l) => l.id !== linkId));
    try { await deleteJourneyLink(linkId); }
    catch { if (prev) setLinks((ls) => [prev, ...ls]); }
  };

  if (isLoading) {
    return (
      <div className="min-h-screen bg-zinc-50 flex items-center justify-center">
        <RotateCcw className="w-6 h-6 text-zinc-400 animate-spin" />
      </div>
    );
  }

  if (error && !arch) {
    return (
      <div className="min-h-screen bg-zinc-50 flex flex-col items-center justify-center gap-4">
        <p className="text-sm text-rose-600">{error}</p>
        <button onClick={() => void load()} className="text-sm font-semibold text-zinc-700 hover:underline">Retry</button>
        <button onClick={() => navigate('/architectures')} className="text-sm text-zinc-500 hover:underline">← Back to Architectures</button>
      </div>
    );
  }

  const isArchived = arch?.status === 'archived';

  return (
    <div className="min-h-screen bg-zinc-50 font-sans">
      {/* Header */}
      <header className="h-14 bg-white border-b border-zinc-200 flex items-center justify-between px-6 sticky top-0 z-10">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate('/architectures')} className="flex items-center gap-1.5 text-xs text-zinc-500 hover:text-zinc-800 transition-colors">
            <ArrowLeft className="w-3.5 h-3.5" /><span className="font-medium">Architectures</span>
          </button>
          <div className="w-px h-4 bg-zinc-200" />
          <span className="text-sm font-semibold text-zinc-700 truncate max-w-xs">{arch?.title ?? 'Untitled'}</span>
          {arch && <span className={`text-[11px] font-medium px-2 py-0.5 rounded-full ${ARCH_STATUS_STYLES[arch.status]}`}>{arch.status}</span>}
        </div>
        <div className="flex items-center gap-3">
          {/* Grid / Graph toggle */}
          <div className="flex rounded-lg border border-zinc-200 overflow-hidden">
            <button onClick={() => setViewMode('grid')}
              className={`px-3 py-1.5 text-xs font-medium flex items-center gap-1.5 transition-colors ${viewMode === 'grid' ? 'bg-zinc-900 text-white' : 'bg-white text-zinc-500 hover:bg-zinc-50'}`}>
              <LayoutGrid className="w-3.5 h-3.5" />Grid
            </button>
            <button onClick={() => setViewMode('graph')}
              className={`px-3 py-1.5 text-xs font-medium flex items-center gap-1.5 transition-colors ${viewMode === 'graph' ? 'bg-zinc-900 text-white' : 'bg-white text-zinc-500 hover:bg-zinc-50'}`}>
              <Network className="w-3.5 h-3.5" />Graph
            </button>
          </div>
          <button onClick={() => void handleCreateMap()} disabled={isCreatingMap}
            className="inline-flex items-center gap-2 px-4 py-2 bg-zinc-900 text-white text-sm font-semibold rounded-xl hover:bg-zinc-800 disabled:opacity-60 transition-colors shadow-sm">
            {isCreatingMap ? <RotateCcw className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
            New Journey Map
          </button>
          {/* Architecture kebab */}
          <div ref={archMenuRef} className="relative">
            <button onClick={() => setArchMenuOpen((v) => !v)} className="p-2 rounded-lg hover:bg-zinc-100 transition">
              <MoreHorizontal className="w-4 h-4 text-zinc-500" />
            </button>
            {archMenuOpen && !confirmDeleteArch && (
              <div className="absolute right-0 top-10 w-44 bg-white border border-zinc-200 rounded-xl shadow-lg z-20 py-1 text-sm">
                <button onClick={() => {setEditingTitle(true); setArchMenuOpen(false);}} className="flex items-center gap-2 w-full px-4 py-2.5 hover:bg-zinc-50 text-zinc-700"><Pencil className="w-3.5 h-3.5" />Rename</button>
                <button onClick={() => {handleArchiveArch(); setArchMenuOpen(false);}} className="flex items-center gap-2 w-full px-4 py-2.5 hover:bg-zinc-50 text-zinc-700"><Archive className="w-3.5 h-3.5" />{isArchived ? 'Unarchive' : 'Archive'}</button>
                <div className="border-t border-zinc-100 my-1" />
                <button onClick={() => setConfirmDeleteArch(true)} className="flex items-center gap-2 w-full px-4 py-2.5 hover:bg-rose-50 text-rose-600"><Trash2 className="w-3.5 h-3.5" />Delete</button>
              </div>
            )}
            {archMenuOpen && confirmDeleteArch && (
              <div className="absolute right-0 top-10 w-56 bg-white border border-zinc-200 rounded-xl shadow-lg z-20 p-4 text-sm">
                <p className="font-semibold text-zinc-800 mb-1">Delete architecture?</p>
                <p className="text-xs text-zinc-500 mb-4">All journey maps inside will be permanently deleted. This cannot be undone.</p>
                <div className="flex gap-2">
                  <button onClick={() => void handleDeleteArch()} className="flex-1 py-2 bg-rose-600 text-white rounded-lg font-semibold hover:bg-rose-700 text-xs">Delete</button>
                  <button onClick={() => setConfirmDeleteArch(false)} className="flex-1 py-2 border border-zinc-200 rounded-lg text-zinc-600 hover:bg-zinc-50 text-xs">Cancel</button>
                </div>
              </div>
            )}
          </div>
        </div>
      </header>

      {/* Architecture meta — inline editable title + description */}
      <div className="max-w-6xl mx-auto px-6 pt-8 pb-4">
        {editingTitle ? (
          <div className="flex items-center gap-2 mb-1">
            <input autoFocus className="text-2xl font-bold text-zinc-900 bg-transparent border-b-2 border-indigo-400 outline-none w-full max-w-lg"
              value={titleValue} onChange={(e) => setTitleValue(e.target.value)}
              onKeyDown={(e) => {if (e.key === 'Enter') void commitTitle(); if (e.key === 'Escape') {setTitleValue(arch?.title ?? ''); setEditingTitle(false);}}} />
            <button onClick={() => void commitTitle()} className="p-1 text-emerald-600"><Check className="w-4 h-4" /></button>
            <button onClick={() => {setTitleValue(arch?.title ?? ''); setEditingTitle(false);}} className="p-1 text-zinc-400"><X className="w-4 h-4" /></button>
          </div>
        ) : (
          <h1 onClick={() => setEditingTitle(true)} className="text-2xl font-bold text-zinc-900 tracking-tight cursor-text hover:text-indigo-700 transition-colors mb-1">{arch?.title ?? 'Untitled Architecture'}</h1>
        )}
        {editingDesc ? (
          <div className="flex items-center gap-2">
            <input autoFocus className="text-sm text-zinc-500 bg-transparent border-b border-zinc-300 outline-none w-full max-w-lg"
              placeholder="Add a description…" value={descValue} onChange={(e) => setDescValue(e.target.value)}
              onKeyDown={(e) => {if (e.key === 'Enter') void commitDesc(); if (e.key === 'Escape') {setDescValue(arch?.description ?? ''); setEditingDesc(false);}}} />
            <button onClick={() => void commitDesc()} className="p-1 text-emerald-600"><Check className="w-3.5 h-3.5" /></button>
            <button onClick={() => {setDescValue(arch?.description ?? ''); setEditingDesc(false);}} className="p-1 text-zinc-400"><X className="w-3.5 h-3.5" /></button>
          </div>
        ) : (
          <p onClick={() => setEditingDesc(true)} className="text-sm text-zinc-400 cursor-text hover:text-zinc-600 transition-colors">
            {arch?.description ?? <span className="italic">Add a description…</span>}
          </p>
        )}
      </div>

      {/* Map grid */}
      <main className="max-w-6xl mx-auto px-6 pb-12">
        {error && (
          <div className="mb-6 flex items-center justify-between px-4 py-3 bg-rose-50 border border-rose-200 rounded-xl text-sm text-rose-700">
            <span>{error}</span>
            <button onClick={() => setError(null)} className="text-rose-400 hover:text-rose-600 ml-4"><X className="w-4 h-4" /></button>
          </div>
        )}

        {/* Graph view */}
        {viewMode === 'graph' && (
          <ArchitectureGraph
            architectureId={archId}
            maps={maps}
            links={links}
            onLinksChange={setLinks}
          />
        )}

        {/* Grid view */}
        {viewMode === 'grid' && maps.length === 0 ? (
          <div className="flex flex-col items-center justify-center text-center py-20 px-6">
            <div className="w-14 h-14 rounded-2xl bg-zinc-100 flex items-center justify-center mb-4">
              <LayoutGrid className="w-7 h-7 text-zinc-300" />
            </div>
            <h2 className="text-base font-semibold text-zinc-700 mb-2">No journey maps yet</h2>
            <p className="text-sm text-zinc-400 max-w-xs mb-6">Create your first journey map inside this architecture.</p>
            <button onClick={() => void handleCreateMap()} disabled={isCreatingMap}
              className="inline-flex items-center gap-2 px-5 py-2.5 bg-zinc-900 text-white text-sm font-semibold rounded-xl hover:bg-zinc-800 disabled:opacity-60 transition-colors shadow-sm">
              {isCreatingMap ? <RotateCcw className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
              New Journey Map
            </button>
          </div>
        ) : viewMode === 'grid' ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {maps.map((map) => (
              <MapTile
                key={map.id}
                map={map}
                links={links.filter((l) => l.source_map === map.id)}
                allMaps={maps}
                onOpen={() => navigate(`/maps/${map.id}?arch=${archId}`)}
                onRename={(title) => handleRenameMap(map.id, title)}
                onArchive={() => void handleArchiveMap(map)}
                onDelete={() => void handleDeleteMap(map.id)}
                onRemoveLink={handleRemoveLink}
              />
            ))}
          </div>
        ) : null}
      </main>

    </div>
  );
}