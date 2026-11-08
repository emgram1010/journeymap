// GAP-FIX W1 (2026-10-17) built this as the screen that turns a map into real
// work: start a job from a map, see the jobs in this plan.
//
// PUX-1 (US-PUX-1-05, 2026-11-07) — A LIST, NOTHING MORE. It used to expand a
// job's row in place (steps, lines, exceptions, activity, time window), and the
// Jobs column opened it with a `focusJobId` that expanded one row inside the
// full list — the founder's "why do I see every job when I clicked mine?". All
// per-job detail moved to `JobPanel.tsx`, opened from every place a job
// appears; this modal keeps search, "New job", and one line per job.
import {useCallback, useEffect, useMemo, useState} from 'react';
import {X, Briefcase, Plus, Search, ChevronRight} from 'lucide-react';
import {
  listWorkspaceMaps,
  listWorkItems,
  createWorkItem,
  type RawWorkspaceMap,
  type WorkItemListEntry,
  type RawTimeWindow,
} from '../plannerApi';
import {jobStatusLabel} from '../../jobModel';
import {compareByWindow} from '../timeWindowModel';
import {TimeWindowChip} from './TimeWindowChip';

interface JobsModalProps {
  isOpen: boolean;
  workspaceId: string | null;
  workspaceName: string;
  /** PUX-2 — every window in the plan, keyed by job (PlannerApp's copy). */
  windowsByJob: Map<number, RawTimeWindow & {work_item_id: number}>;
  onClose: () => void;
  /** PUX-1 — open one job in the side panel. */
  onOpenJob: (workItemId: number) => void;
  /** Refetch the board after a job is created. */
  onChanged: () => void;
}

export function JobsModal({isOpen, workspaceId, workspaceName, windowsByJob, onClose, onOpenJob, onChanged}: JobsModalProps) {
  const [maps, setMaps] = useState<RawWorkspaceMap[]>([]);
  const [jobs, setJobs] = useState<WorkItemListEntry[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [sortByWindow, setSortByWindow] = useState(false);
  const [newTitle, setNewTitle] = useState('');
  const [newMapId, setNewMapId] = useState<number | null>(null);
  const [isCreating, setIsCreating] = useState(false);

  const load = useCallback(async (wsId: string, isPlanChange = false) => {
    setIsLoading(true);
    setError(null);
    // Switching plans must CLEAR first, so one plan's jobs never show under another's name.
    if (isPlanChange) {
      setMaps([]);
      setJobs([]);
      setNewMapId(null);
    }
    try {
      const [mapData, jobData] = await Promise.all([listWorkspaceMaps(Number(wsId)), listWorkItems(Number(wsId))]);
      setMaps(mapData.maps);
      setJobs(jobData.work_items);
      setNewMapId((prev) => (prev !== null && mapData.maps.some((m) => m.map_id === prev) ? prev : mapData.maps[0]?.map_id ?? null));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't load this plan's jobs.");
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Reset the form only when the modal OPENS (gap-fix Part 1 #7).
  useEffect(() => {
    if (!isOpen) return;
    setNewTitle('');
    setError(null);
    setNotice(null);
    setQuery('');
  }, [isOpen]);

  useEffect(() => {
    if (isOpen && workspaceId) void load(workspaceId, true);
  }, [isOpen, workspaceId, load]);

  const visibleJobs = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = q ? jobs.filter((j) => j.work_item.title.toLowerCase().includes(q)) : jobs;
    return [...filtered].sort((a, b) =>
      sortByWindow
        ? compareByWindow(windowsByJob.get(a.work_item.id), windowsByJob.get(b.work_item.id)) || b.work_item.id - a.work_item.id
        : b.work_item.id - a.work_item.id,
    );
  }, [jobs, query, sortByWindow, windowsByJob]);

  if (!isOpen) return null;

  const handleCreate = async () => {
    if (!workspaceId) return;
    const title = newTitle.trim();
    if (!title) {
      setError('Give the job a short name — "Quote for the Garcia party", not "Job 1".');
      return;
    }
    if (!newMapId) {
      setError('Choose which map this job follows.');
      return;
    }
    setIsCreating(true);
    setError(null);
    setNotice(null);
    try {
      const result = await createWorkItem({workspace_id: Number(workspaceId), journey_map_id: newMapId, title});
      setNewTitle('');
      setNotice(
        `"${title}" created with ${result.task_count} step${result.task_count === 1 ? '' : 's'}, pinned to version ${result.pinned_version.version_no}. Its steps are waiting in Unscheduled.`,
      );
      await load(workspaceId);
      onChanged();
    } catch (err) {
      // The server's messages name the map and say what to do (E-JOB-002/003).
      setError(err instanceof Error ? err.message : "Couldn't create that job.");
    } finally {
      setIsCreating(false);
    }
  };

  return (
    <div
      id="jobs-modal-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        id="jobs-modal"
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-xl flex flex-col max-h-[88vh] overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="h-14 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
          <div className="flex items-center gap-2 min-w-0">
            <Briefcase className="w-4 h-4 text-neutral-700 shrink-0" />
            <h2 className="text-sm font-bold text-neutral-900">Jobs</h2>
            <span className="text-[11px] text-neutral-500 truncate">{workspaceName}</span>
          </div>
          <button type="button" onClick={onClose} className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50" aria-label="Close">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-6 overflow-y-auto flex flex-col gap-6">
          {error && <p className="text-xs text-red-600 bg-red-50 border border-red-200 rounded-md px-3 py-2">{error}</p>}
          {notice && <p className="text-xs text-emerald-800 bg-emerald-50 border border-emerald-200 rounded-md px-3 py-2">{notice}</p>}

          {/* ── New job ─────────────────────────────────────────────── */}
          <section>
            <h3 className="text-xs font-semibold text-neutral-900 mb-2">New job</h3>
            {/* PERF-1 (US-PERF-1-03): gated on isLoading, so "no maps" never flashes while loading. */}
            {isLoading && maps.length === 0 ? (
              <p className="text-[11px] text-neutral-400">Loading…</p>
            ) : maps.length === 0 ? (
              <p className="text-[11px] text-neutral-500">
                This plan doesn't use any maps yet. Add one in <span className="font-medium">Workspace Settings → Maps in this plan</span> first —
                a job has to follow a published map.
              </p>
            ) : (
              <div className="flex flex-col gap-2">
                <input
                  id="new-job-title-input"
                  type="text"
                  value={newTitle}
                  onChange={(e) => {
                    setNewTitle(e.target.value);
                    setError(null);
                  }}
                  placeholder="e.g. Quote for the Garcia party"
                  className="text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900"
                />
                <div className="flex items-center gap-2">
                  <select
                    id="new-job-map-select"
                    value={newMapId ?? ''}
                    onChange={(e) => setNewMapId(Number(e.target.value) || null)}
                    className="flex-1 text-xs px-3 py-2 border border-neutral-200 rounded-md bg-white focus:outline-none focus:border-neutral-900"
                  >
                    {maps.map((m) => (
                      <option key={m.map_id} value={m.map_id}>
                        {m.title ?? `Map #${m.map_id}`}
                      </option>
                    ))}
                  </select>
                  <button
                    id="create-job-btn"
                    type="button"
                    onClick={() => void handleCreate()}
                    disabled={isCreating}
                    className="px-3 py-2 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800 disabled:opacity-60 shrink-0 flex items-center gap-1.5"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    {isCreating ? 'Creating…' : 'Create job'}
                  </button>
                </div>
              </div>
            )}
          </section>

          {/* ── Jobs in this plan — one line each; a click opens the job panel ── */}
          <section>
            <div className="flex items-center justify-between gap-2 mb-2">
              <h3 className="text-xs font-semibold text-neutral-900">Jobs in this plan</h3>
              <label className="flex items-center gap-1 text-[10px] text-neutral-600">
                <input type="checkbox" checked={sortByWindow} onChange={(e) => setSortByWindow(e.target.checked)} />
                Soonest window first
              </label>
            </div>
            <div className="relative mb-2">
              <Search className="w-3 h-3 absolute left-2 top-2 text-neutral-400" />
              <input
                type="text"
                data-testid="jobs-modal-search"
                placeholder="Find a job…"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                className="w-full pl-6 pr-2 py-1.5 text-[11px] bg-white border border-neutral-200 rounded focus:outline-none focus:border-neutral-400"
              />
            </div>
            {isLoading && jobs.length === 0 ? (
              <p className="text-[11px] text-neutral-400">Loading…</p>
            ) : jobs.length === 0 ? (
              <p className="text-[11px] text-neutral-500">No jobs yet.</p>
            ) : visibleJobs.length === 0 ? (
              <p className="text-[11px] text-neutral-500">No job matches “{query}”.</p>
            ) : (
              <ul className="divide-y divide-neutral-100 border border-neutral-200 rounded-md">
                {visibleJobs.map(({work_item: job, task_count, finished_count, has_blocked}) => (
                  <li key={job.id}>
                    <button
                      type="button"
                      data-testid="jobs-modal-job"
                      onClick={() => onOpenJob(job.id)}
                      className="w-full px-3 py-2 flex items-center justify-between gap-3 text-left hover:bg-neutral-50"
                    >
                      <span className="min-w-0">
                        <span className="block text-xs font-medium text-neutral-900 truncate">{job.title}</span>
                        <span className="block text-[10px] text-neutral-500">
                          {jobStatusLabel(job.status)} · {finished_count} of {task_count} step{task_count === 1 ? '' : 's'} done
                          {has_blocked && <span className="text-red-600"> · blocked</span>}
                        </span>
                        <TimeWindowChip window={windowsByJob.get(job.id)} className="mt-1" />
                      </span>
                      <ChevronRight className="w-3.5 h-3.5 text-neutral-400 shrink-0" />
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>

        <div className="h-14 px-6 border-t border-neutral-200 flex items-center justify-end bg-neutral-50 shrink-0">
          <button type="button" onClick={onClose} className="px-4 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800">
            Done
          </button>
        </div>
      </div>
    </div>
  );
}
