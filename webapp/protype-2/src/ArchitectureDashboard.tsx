import React, {useEffect, useRef, useState} from 'react';
import {useNavigate} from 'react-router-dom';
import {Plus, LayoutGrid, RotateCcw, MoreHorizontal, Pencil, Archive, Trash2, Check, X, ArrowLeft} from 'lucide-react';
import {
  listJourneyArchitectures,
  createJourneyArchitecture,
  updateJourneyArchitecture,
  deleteJourneyArchitecture,
  type XanoJourneyArchitecture,
  type JourneyArchitectureStatus,
} from './xano';
import {useAuth} from './AuthContext';

export default function ArchitectureDashboard() {
  const {user, logout} = useAuth();
  const navigate = useNavigate();
  const [architectures, setArchitectures] = useState<XanoJourneyArchitecture[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isCreating, setIsCreating] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const userMenuRef = useRef<HTMLDivElement>(null);
  const [userMenuOpen, setUserMenuOpen] = useState(false);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (userMenuRef.current && !userMenuRef.current.contains(e.target as Node)) setUserMenuOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const load = async () => {
    setIsLoading(true);
    setLoadError(null);
    try {
      const data = await listJourneyArchitectures();
      setArchitectures([...data].sort((a, b) => Date.parse(String(b.updated_at ?? 0)) - Date.parse(String(a.updated_at ?? 0))));
    } catch {
      setLoadError('Unable to load your journey architectures. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => { void load(); }, []);

  const handleCreate = async () => {
    setIsCreating(true);
    try {
      const arch = await createJourneyArchitecture();
      setArchitectures((prev) => [arch, ...prev]);
      navigate(`/architectures/${arch.id}`);
    } catch {
      setLoadError('Unable to create architecture. Please try again.');
    } finally {
      setIsCreating(false);
    }
  };

  const handleRename = async (id: number, title: string) => {
    const prev = architectures.find((a) => a.id === id);
    setArchitectures((as) => as.map((a) => (a.id === id ? {...a, title} : a)));
    try { await updateJourneyArchitecture(id, {title}); }
    catch { if (prev) setArchitectures((as) => as.map((a) => (a.id === id ? prev : a))); }
  };

  const handleArchive = async (arch: XanoJourneyArchitecture) => {
    const next: JourneyArchitectureStatus = arch.status === 'archived' ? 'draft' : 'archived';
    setArchitectures((as) => as.map((a) => (a.id === arch.id ? {...a, status: next} : a)));
    try { await updateJourneyArchitecture(arch.id, {status: next}); }
    catch { setArchitectures((as) => as.map((a) => (a.id === arch.id ? arch : a))); }
  };

  const handleDelete = async (id: number) => {
    const prev = architectures.find((a) => a.id === id);
    setArchitectures((as) => as.filter((a) => a.id !== id));
    try { await deleteJourneyArchitecture(id); }
    catch { if (prev) setArchitectures((as) => [prev, ...as]); }
  };

  const initials = user?.name ? user.name.split(' ').map((w) => w[0]).join('').slice(0, 2).toUpperCase() : 'U';
  const activeCount = architectures.filter((a) => a.status !== 'archived').length;

  return (
    <div className="min-h-screen bg-zinc-50 font-sans">
      <header className="h-14 bg-white border-b border-zinc-200 flex items-center justify-between px-6 sticky top-0 z-10">
        <div className="flex items-center gap-4">
          <button onClick={() => navigate('/dashboard')} className="flex items-center gap-1.5 text-xs text-zinc-500 hover:text-zinc-800 transition-colors">
            <ArrowLeft className="w-3.5 h-3.5" /><span className="font-medium">Journey Maps</span>
          </button>
          <div className="w-px h-4 bg-zinc-200" />
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-indigo-600 text-white flex items-center justify-center text-sm font-bold">A</div>
            <span className="text-sm font-bold text-zinc-900 tracking-tight">Architectures</span>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => void handleCreate()}
            disabled={isCreating}
            className="inline-flex items-center gap-2 px-4 py-2 bg-zinc-900 text-white text-sm font-semibold rounded-xl hover:bg-zinc-800 disabled:opacity-60 transition-colors shadow-sm"
          >
            {isCreating ? <RotateCcw className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
            New Architecture
          </button>
          <div ref={userMenuRef} className="relative">
            <button onClick={() => setUserMenuOpen((v) => !v)} className="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-zinc-100 transition text-sm text-zinc-700">
              <div className="w-7 h-7 rounded-full bg-zinc-800 text-white flex items-center justify-center text-[11px] font-bold">{initials}</div>
              <span className="font-medium">{user?.name?.split(' ')[0] ?? 'User'}</span>
            </button>
            {userMenuOpen && (
              <div className="absolute right-0 top-10 w-40 bg-white border border-zinc-200 rounded-xl shadow-lg z-20 py-1 text-sm">
                <button onClick={() => { logout(); navigate('/login'); }} className="flex items-center gap-2 w-full px-4 py-2.5 hover:bg-zinc-50 text-zinc-700">Sign out</button>
              </div>
            )}
          </div>
        </div>
      </header>

      <main className="max-w-6xl mx-auto px-6 py-10">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-bold text-zinc-900 tracking-tight">Your Journey Architectures</h1>
            {!isLoading && architectures.length > 0 && (
              <p className="text-sm text-zinc-500 mt-0.5">{activeCount} architecture{activeCount !== 1 ? 's' : ''}</p>
            )}
          </div>
        </div>

        {loadError && (
          <div className="mb-6 flex items-center justify-between px-4 py-3 bg-rose-50 border border-rose-200 rounded-xl text-sm text-rose-700">
            <span>{loadError}</span>
            <button onClick={() => void load()} className="text-rose-600 font-semibold hover:underline ml-4">Retry</button>
          </div>
        )}

        {isLoading && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-32 bg-white rounded-xl border border-zinc-200 animate-pulse" />
            ))}
          </div>
        )}

        {!isLoading && architectures.length === 0 && !loadError && (
          <div className="flex flex-col items-center justify-center text-center py-24 px-6">
            <div className="w-16 h-16 rounded-2xl bg-indigo-50 flex items-center justify-center mb-5">
              <LayoutGrid className="w-8 h-8 text-indigo-300" />
            </div>
            <h2 className="text-lg font-semibold text-zinc-800 mb-2">No Journey Architectures yet</h2>
            <p className="text-sm text-zinc-500 max-w-xs mb-6">Create an architecture to start organising your journey maps.</p>
            <button onClick={() => void handleCreate()} disabled={isCreating}
              className="inline-flex items-center gap-2 px-5 py-2.5 bg-zinc-900 text-white text-sm font-semibold rounded-xl hover:bg-zinc-800 disabled:opacity-60 transition-colors shadow-sm">
              {isCreating ? <RotateCcw className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
              Create your first architecture
            </button>
          </div>
        )}

        {!isLoading && architectures.length > 0 && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {architectures.map((arch) => (
              <ArchitectureTile
                key={arch.id}
                arch={arch}
                onOpen={() => navigate(`/architectures/${arch.id}`)}
                onRename={(title) => handleRename(arch.id, title)}
                onArchive={() => void handleArchive(arch)}
                onDelete={() => void handleDelete(arch.id)}
              />
            ))}
          </div>
        )}
      </main>
    </div>
  );
}

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

const STATUS_STYLES: Record<JourneyArchitectureStatus, string> = {
  draft: 'bg-zinc-100 text-zinc-600',
  active: 'bg-emerald-50 text-emerald-700',
  archived: 'bg-amber-50 text-amber-700',
};

interface ArchTileProps {
  arch: XanoJourneyArchitecture;
  onOpen: () => void;
  onRename: (title: string) => Promise<void>;
  onArchive: () => void;
  onDelete: () => void;
}

function ArchitectureTile({arch, onOpen, onRename, onArchive, onDelete}: ArchTileProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const [renameValue, setRenameValue] = useState(arch.title ?? '');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

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
    if (!trimmed) {setRenameValue(arch.title ?? ''); setRenaming(false); return;}
    if (trimmed !== arch.title) await onRename(trimmed);
    setRenaming(false);
  };

  const isArchived = arch.status === 'archived';

  return (
    <div
      onClick={!renaming ? onOpen : undefined}
      className={`group relative bg-white border border-zinc-200 rounded-xl shadow-sm hover:shadow-md hover:border-zinc-300 transition-all cursor-pointer flex flex-col ${isArchived ? 'opacity-60' : ''}`}
    >
      <div className={`h-1 rounded-t-xl ${isArchived ? 'bg-amber-300' : arch.status === 'active' ? 'bg-emerald-400' : 'bg-indigo-300'}`} />
      <div className="p-4 flex-1 flex flex-col gap-2">
        {renaming ? (
          <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
            <input
              autoFocus
              className="flex-1 text-sm font-semibold text-zinc-900 border-b border-zinc-300 bg-transparent outline-none"
              value={renameValue}
              onChange={(e) => setRenameValue(e.target.value)}
              onKeyDown={(e) => {if (e.key === 'Enter') void commitRename(); if (e.key === 'Escape') {setRenameValue(arch.title ?? ''); setRenaming(false);}}}
            />
            <button onClick={() => void commitRename()} className="p-1 text-emerald-600 hover:text-emerald-700"><Check className="w-3.5 h-3.5" /></button>
            <button onClick={() => {setRenameValue(arch.title ?? ''); setRenaming(false);}} className="p-1 text-zinc-400 hover:text-zinc-600"><X className="w-3.5 h-3.5" /></button>
          </div>
        ) : (
          <h3 className="text-sm font-semibold text-zinc-900 truncate pr-6">{arch.title ?? 'Untitled Architecture'}</h3>
        )}
        {arch.description && <p className="text-xs text-zinc-500 line-clamp-2">{arch.description}</p>}
        <div className="flex items-center gap-2 mt-auto pt-2">
          <span className={`text-[11px] font-medium px-2 py-0.5 rounded-full ${STATUS_STYLES[arch.status]}`}>{arch.status}</span>
          <span className="text-[11px] text-zinc-400 ml-auto">{relativeTime(arch.updated_at)}</span>
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
          <div className="absolute right-0 top-7 w-52 bg-white border border-zinc-200 rounded-lg shadow-lg z-10 p-3 text-xs">
            <p className="font-semibold text-zinc-800 mb-1">Delete architecture?</p>
            <p className="text-zinc-500 mb-3">All journey maps inside will be permanently deleted.</p>
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
