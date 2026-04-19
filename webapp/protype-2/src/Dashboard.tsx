import React, { useEffect, useState, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, LayoutGrid, RotateCcw, MoreHorizontal, Pencil, Archive, Trash2, Check, X, LogOut, ChevronDown, Network } from 'lucide-react';
import {
  listJourneyMaps,
  createDraftJourneyMap,
  deleteJourneyMap,
  updateJourneyMapMeta,
  type XanoJourneyMap,
  type JourneyMapStatus,
} from './xano';
import { useAuth } from './AuthContext';

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

const STATUS_STYLES: Record<JourneyMapStatus, string> = {
  draft: 'bg-zinc-100 text-zinc-600',
  active: 'bg-emerald-50 text-emerald-700',
  archived: 'bg-amber-50 text-amber-700',
};

interface MapTileProps {
  map: XanoJourneyMap;
  onOpen: () => void;
  onRename: (title: string) => Promise<void>;
  onDelete: () => void;
  onArchive: () => void;
}

function MapTile({ map, onOpen, onRename, onDelete, onArchive }: MapTileProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const [renameValue, setRenameValue] = useState(map.title);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  // Close menu on outside click
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setMenuOpen(false);
        setConfirmDelete(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const commitRename = async () => {
    const trimmed = renameValue.trim();
    if (!trimmed) { setRenameValue(map.title); setRenaming(false); return; }
    if (trimmed !== map.title) await onRename(trimmed);
    setRenaming(false);
  };

  const ts = map.last_interaction_at ?? map.updated_at ?? map.created_at;
  const isArchived = map.status === 'archived';

  return (
    <div
      onClick={!renaming ? onOpen : undefined}
      className={`group relative bg-white border border-zinc-200 rounded-xl shadow-sm hover:shadow-md hover:border-zinc-300 transition-all cursor-pointer flex flex-col ${isArchived ? 'opacity-60' : ''}`}
    >
      {/* Colour accent bar */}
      <div className={`h-1 rounded-t-xl ${isArchived ? 'bg-amber-300' : map.status === 'active' ? 'bg-emerald-400' : 'bg-zinc-300'}`} />

      <div className="p-5 flex-1 flex flex-col gap-3">
        {/* Title row */}
        <div className="flex items-start justify-between gap-2">
          {renaming ? (
            <input
              autoFocus
              value={renameValue}
              onChange={(e) => setRenameValue(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') void commitRename(); if (e.key === 'Escape') { setRenameValue(map.title); setRenaming(false); } }}
              onBlur={() => void commitRename()}
              onClick={(e) => e.stopPropagation()}
              className="flex-1 text-sm font-semibold text-zinc-900 border-b border-zinc-300 focus:outline-none focus:border-zinc-600 bg-transparent"
            />
          ) : (
            <h3 className="flex-1 text-sm font-semibold text-zinc-900 leading-snug line-clamp-2">{map.title}</h3>
          )}

          {/* Kebab menu */}
          <div ref={menuRef} className="relative shrink-0" onClick={(e) => e.stopPropagation()}>
            <button
              onClick={() => { setMenuOpen((v) => !v); setConfirmDelete(false); }}
              className="p-1 rounded-md text-zinc-400 opacity-0 group-hover:opacity-100 hover:bg-zinc-100 hover:text-zinc-600 transition"
            >
              <MoreHorizontal className="w-4 h-4" />
            </button>

            {menuOpen && !confirmDelete && (
              <div className="absolute right-0 top-7 z-20 w-40 bg-white border border-zinc-200 rounded-lg shadow-lg py-1 text-xs">
                <button className="w-full flex items-center gap-2 px-3 py-2 text-zinc-700 hover:bg-zinc-50 transition" onClick={() => { setRenaming(true); setMenuOpen(false); }}>
                  <Pencil className="w-3.5 h-3.5" /> Rename
                </button>
                <button className="w-full flex items-center gap-2 px-3 py-2 text-zinc-700 hover:bg-zinc-50 transition" onClick={() => { onArchive(); setMenuOpen(false); }}>
                  <Archive className="w-3.5 h-3.5" /> {isArchived ? 'Unarchive' : 'Archive'}
                </button>
                <div className="my-1 border-t border-zinc-100" />
                <button className="w-full flex items-center gap-2 px-3 py-2 text-rose-600 hover:bg-rose-50 transition" onClick={() => setConfirmDelete(true)}>
                  <Trash2 className="w-3.5 h-3.5" /> Delete
                </button>
              </div>
            )}

            {menuOpen && confirmDelete && (
              <div className="absolute right-0 top-7 z-20 w-52 bg-white border border-zinc-200 rounded-lg shadow-lg p-3 text-xs">
                <p className="font-semibold text-zinc-800 mb-1">Delete "{map.title.slice(0, 20)}{map.title.length > 20 ? '…' : ''}"?</p>
                <p className="text-zinc-500 mb-3 leading-snug">This will permanently remove the map and all its data.</p>
                <div className="flex gap-2">
                  <button className="flex-1 flex items-center justify-center gap-1 py-1.5 rounded bg-rose-600 text-white font-semibold hover:bg-rose-700 transition" onClick={() => { onDelete(); setMenuOpen(false); setConfirmDelete(false); }}>
                    <Trash2 className="w-3 h-3" /> Delete
                  </button>
                  <button className="flex-1 flex items-center justify-center gap-1 py-1.5 rounded bg-zinc-100 text-zinc-700 hover:bg-zinc-200 transition" onClick={() => { setMenuOpen(false); setConfirmDelete(false); }}>
                    <X className="w-3 h-3" /> Cancel
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Status & timestamp */}
        <div className="flex items-center justify-between mt-auto">
          <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold uppercase tracking-wide ${STATUS_STYLES[map.status]}`}>
            {map.status}
          </span>
          <span className="text-[11px] text-zinc-400">{relativeTime(ts)}</span>
        </div>
      </div>
    </div>
  );
}


// ── Dashboard page ──────────────────────────────────────────────────────────

export default function Dashboard() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const [maps, setMaps] = useState<XanoJourneyMap[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isCreating, setIsCreating] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const userMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (userMenuRef.current && !userMenuRef.current.contains(e.target as Node)) setUserMenuOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const loadMaps = async () => {
    setIsLoading(true);
    setLoadError(null);
    try {
      const data = await listJourneyMaps();
      // Only show standalone maps — maps belonging to an architecture live in the Architecture Detail.
      const standalone = data.filter((m) => !m.journey_architecture);
      const sorted = [...standalone].sort((a, b) => {
        const ta = Date.parse(String(a.last_interaction_at ?? a.updated_at ?? a.created_at ?? 0)) || 0;
        const tb = Date.parse(String(b.last_interaction_at ?? b.updated_at ?? b.created_at ?? 0)) || 0;
        return tb - ta;
      });
      setMaps(sorted);
    } catch {
      setLoadError('Unable to load your journey maps. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => { void loadMaps(); }, []);

  const handleCreate = async () => {
    setIsCreating(true);
    try {
      const bundle = await createDraftJourneyMap({ title: 'Untitled Journey Map', status: 'draft' });
      setMaps((prev) => [bundle.journeyMap, ...prev]);
      navigate(`/maps/${bundle.journeyMap.id}`);
    } catch {
      setLoadError('Unable to create journey map. Please try again.');
    } finally {
      setIsCreating(false);
    }
  };

  const handleRename = async (id: number, title: string) => {
    const prev = maps.find((m) => m.id === id);
    setMaps((ms) => ms.map((m) => (m.id === id ? { ...m, title } : m)));
    try {
      await updateJourneyMapMeta(id, { title });
    } catch {
      if (prev) setMaps((ms) => ms.map((m) => (m.id === id ? prev : m)));
    }
  };

  const handleDelete = async (id: number) => {
    const prev = maps.find((m) => m.id === id);
    setMaps((ms) => ms.filter((m) => m.id !== id));
    try {
      await deleteJourneyMap(id);
    } catch {
      if (prev) setMaps((ms) => [prev, ...ms]);
    }
  };

  const handleArchive = async (map: XanoJourneyMap) => {
    const next: JourneyMapStatus = map.status === 'archived' ? 'draft' : 'archived';
    setMaps((ms) => ms.map((m) => (m.id === map.id ? { ...m, status: next } : m)));
    try {
      await updateJourneyMapMeta(map.id, { status: next });
    } catch {
      setMaps((ms) => ms.map((m) => (m.id === map.id ? map : m)));
    }
  };

  const initials = user?.name ? user.name.split(' ').map((w) => w[0]).join('').slice(0, 2).toUpperCase() : 'U';
  const activeCount = maps.filter((m) => m.status !== 'archived').length;

  return (
    <div className="min-h-screen bg-zinc-50 font-sans">
      {/* Header */}
      <header className="h-14 bg-white border-b border-zinc-200 flex items-center justify-between px-6 sticky top-0 z-10">
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-zinc-900 text-white flex items-center justify-center text-sm font-bold">E</div>
            <span className="text-sm font-bold text-zinc-900 tracking-tight">Emgram</span>
          </div>
          <div className="w-px h-4 bg-zinc-200" />
          <button
            onClick={() => navigate('/architectures')}
            className="flex items-center gap-1.5 text-xs font-medium text-zinc-500 hover:text-zinc-900 transition-colors"
          >
            <Network className="w-3.5 h-3.5" />
            Architectures
          </button>
        </div>
        <div ref={userMenuRef} className="relative">
          <button onClick={() => setUserMenuOpen((v) => !v)} className="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-zinc-100 transition text-sm text-zinc-700">
            <div className="w-7 h-7 rounded-full bg-zinc-800 text-white flex items-center justify-center text-xs font-bold">{initials}</div>
            <span className="hidden sm:block font-medium">{user?.name ?? 'Account'}</span>
            <ChevronDown className="w-3.5 h-3.5 text-zinc-400" />
          </button>
          {userMenuOpen && (
            <div className="absolute right-0 top-11 z-20 w-48 bg-white border border-zinc-200 rounded-lg shadow-lg py-1 text-xs">
              <div className="px-3 py-2 text-zinc-500 border-b border-zinc-100">{user?.email ?? ''}</div>
              <button className="w-full flex items-center gap-2 px-3 py-2.5 text-rose-600 hover:bg-rose-50 transition" onClick={() => { logout(); navigate('/login'); }}>
                <LogOut className="w-3.5 h-3.5" /> Sign out
              </button>
            </div>
          )}
        </div>
      </header>

      {/* Page content */}
      <main className="max-w-6xl mx-auto px-6 py-10">
        {/* Title row */}
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-bold text-zinc-900 tracking-tight">Your Journey Maps</h1>
            {!isLoading && maps.length > 0 && (
              <p className="text-sm text-zinc-500 mt-0.5">{activeCount} map{activeCount !== 1 ? 's' : ''}</p>
            )}
          </div>
          <button
            onClick={() => void handleCreate()}
            disabled={isCreating}
            className="inline-flex items-center gap-2 px-4 py-2.5 bg-zinc-900 text-white text-sm font-semibold rounded-xl hover:bg-zinc-800 disabled:opacity-60 disabled:cursor-not-allowed transition-colors shadow-sm"
          >
            {isCreating ? <RotateCcw className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
            {isCreating ? 'Creating…' : 'New Journey Map'}
          </button>
        </div>

        {/* Error banner */}
        {loadError && (
          <div className="mb-6 flex items-center justify-between px-4 py-3 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-700">
            <span>{loadError}</span>
            <button onClick={() => void loadMaps()} className="font-semibold hover:underline ml-4">Retry</button>
          </div>
        )}

        {/* Loading skeleton */}
        {isLoading && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {[1, 2, 3].map((i) => (
              <div key={i} className="bg-white border border-zinc-200 rounded-xl h-36 animate-pulse" />
            ))}
          </div>
        )}

        {/* Empty state */}
        {!isLoading && maps.length === 0 && !loadError && (
          <div className="flex flex-col items-center justify-center text-center py-24 px-6">
            <div className="w-16 h-16 rounded-2xl bg-zinc-100 flex items-center justify-center mb-5">
              <LayoutGrid className="w-8 h-8 text-zinc-300" />
            </div>
            <h2 className="text-lg font-semibold text-zinc-800 mb-2">No journey maps yet</h2>
            <p className="text-sm text-zinc-500 max-w-xs mb-6">Create your first map to start capturing expert knowledge.</p>
            <button onClick={() => void handleCreate()} disabled={isCreating}
              className="inline-flex items-center gap-2 px-5 py-2.5 bg-zinc-900 text-white text-sm font-semibold rounded-xl hover:bg-zinc-800 disabled:opacity-60 transition-colors shadow-sm">
              {isCreating ? <RotateCcw className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
              Create your first journey map
            </button>
          </div>
        )}

        {/* Tile grid */}
        {!isLoading && maps.length > 0 && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {maps.map((map) => (
              <MapTile
                key={map.id}
                map={map}
                onOpen={() => navigate(`/maps/${map.id}`)}
                onRename={(title) => handleRename(map.id, title)}
                onDelete={() => void handleDelete(map.id)}
                onArchive={() => void handleArchive(map)}
              />
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
