// BOARD-1 (US-BOARD-1-01/02) built this as the waiting-work column. QUE-1
// (2026-10-30) reshapes it: this is now the registry of EVERY job in the
// plan, not just the ones with cards still waiting for a day.
//
// QUE-1 (US-QUE-1-03/04) — what changed:
//   - Reads `listWorkItems` (every job), not `listBacklogWork` (waiting
//     cards only). A finished, sent, or fully-placed job stays visible.
//   - VIEW-ONLY. No drag, no Place…, no steps disclosure here (Q-1,
//     resolved 2026-10-30: a role line with no day already shows
//     automatically in Unscheduled — see BacklogDrawer.tsx — so there is
//     nothing to place from this list). Clicking a row opens the Jobs
//     modal, which now shows the job's steps too (US-QUE-1-04).
//   - This is also where US-QUE-1-07's filter bar lives: a search box,
//     wired; a disabled "Filters" control reserving the space for the
//     requirements/task-type work that comes after this epic.
//
// Rows carry the job's words — title, status, progress — never a code
// (BOARD-1's D-2, still the rule). The exception chips ("from #N", "N
// sent on") are unchanged from BOARD-1/EXC-2 and still open the shared
// read-only job view (JobPeekSheet, D-2 of EXC-2).
import {useEffect, useMemo, useState} from 'react';
import {Briefcase, Plus, Search, SlidersHorizontal} from 'lucide-react';
import {listWorkItems, type WorkItemListEntry} from '../plannerApi';
import {jobStatusLabel, unitRowLabel} from '../../jobModel';
import JobPeekSheet from '../../exceptions/JobPeekSheet';

interface JobsColumnProps {
  workspaceId: string | null;
  /** Bumped by PlannerApp after any board mutation; the list refetches. */
  reloadNonce: number;
  /** Open the Jobs modal — on one job's detail, or on nothing (new job). */
  onOpenJobs: (focusJobId?: number) => void;
}

export function JobsColumn({workspaceId, reloadNonce, onOpenJobs}: JobsColumnProps) {
  const [jobs, setJobs] = useState<WorkItemListEntry[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  // EXC chips open the shared read-only job view (D-2 of EXC-2), never a rebuild of it.
  const [peekId, setPeekId] = useState<number | null>(null);

  useEffect(() => {
    if (!workspaceId) {
      setJobs([]);
      return;
    }
    let current = true;
    setIsLoading(true);
    setError(null);
    listWorkItems(Number(workspaceId))
      .then((data) => {
        if (current) setJobs(data.work_items);
      })
      .catch((err) => {
        if (current) setError(err instanceof Error ? err.message : "Couldn't load this plan's jobs.");
      })
      .finally(() => {
        if (current) setIsLoading(false);
      });
    return () => {
      current = false;
    };
  }, [workspaceId, reloadNonce]);

  // US-QUE-1-07 — the only filter wired is search-by-title. Newest job
  // first, same ordering convention `groupCardsByJob` uses elsewhere.
  const visibleJobs = useMemo(() => {
    const sorted = [...jobs].sort((a, b) => b.work_item.id - a.work_item.id);
    const q = query.trim().toLowerCase();
    if (!q) return sorted;
    return sorted.filter((j) => j.work_item.title.toLowerCase().includes(q));
  }, [jobs, query]);

  return (
    <aside
      id="jobs-column"
      aria-label="Every job in this plan"
      className="w-72 shrink-0 h-full flex flex-col border-r border-neutral-200 bg-neutral-50/40"
    >
      <div className="px-3 py-2 border-b border-neutral-200 flex flex-col gap-1.5 shrink-0 bg-neutral-50/60">
        <div className="flex items-center justify-between">
          <p className="flex items-center gap-1.5 text-xs font-semibold text-neutral-900" data-testid="jobs-column-count">
            <Briefcase className="w-3.5 h-3.5 text-neutral-500" />
            Jobs ({jobs.length})
          </p>
          <button
            type="button"
            data-testid="jobs-column-new-job"
            onClick={() => onOpenJobs()}
            className="flex items-center gap-1 px-2 py-1 text-[11px] font-medium text-neutral-700 border border-neutral-200 rounded bg-white hover:bg-neutral-100"
          >
            <Plus className="w-3 h-3" />
            New job
          </button>
        </div>

        {/* US-QUE-1-07 — search wired; "Filters" reserves the space for
            requirements/task-type filtering, deliberately NOT built here
            (see EPIC-QUE-1 §4 — that work is designed but deferred). */}
        <div className="flex items-center gap-1">
          <div className="relative flex-1">
            <Search className="w-3 h-3 absolute left-2 top-1.5 text-neutral-400" />
            <input
              type="text"
              data-testid="jobs-column-search"
              placeholder="Find a job…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="w-full pl-6 pr-2 py-1 text-[11px] bg-white border border-neutral-200 rounded focus:outline-none focus:border-neutral-400 placeholder:text-neutral-400"
            />
          </div>
          <button
            type="button"
            disabled
            title="Filter by status, role or task type — coming soon"
            className="shrink-0 flex items-center gap-1 px-1.5 py-1 text-[10px] font-medium text-neutral-400 border border-neutral-200 rounded bg-neutral-50 cursor-not-allowed"
          >
            <SlidersHorizontal className="w-3 h-3" />
            Filters
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-2 space-y-1.5">
        {isLoading && jobs.length === 0 && <p className="px-1 py-2 text-[11px] text-neutral-400">Loading…</p>}
        {error && (
          <p role="alert" className="px-2 py-2 text-[11px] text-red-700 bg-red-50 border border-red-200 rounded">
            {error}
          </p>
        )}
        {!isLoading && !error && jobs.length === 0 && (
          <p className="px-2 py-4 text-[11px] text-neutral-500">
            No jobs yet. Start one from a map with “New job”.
          </p>
        )}
        {!isLoading && !error && jobs.length > 0 && visibleJobs.length === 0 && (
          <p className="px-2 py-4 text-[11px] text-neutral-500">No job matches “{query}”.</p>
        )}

        {visibleJobs.map(({work_item: job, task_count, finished_count, has_blocked, child_count, unit_total, units_moved_out}) => (
          <button
            type="button"
            key={job.id}
            data-testid="jobs-column-job"
            onClick={() => onOpenJobs(job.id)}
            title="Opens this job's detail (steps, lines, exceptions, activity)"
            className="w-full rounded-md border border-neutral-200 bg-white px-2.5 py-1.5 text-left hover:bg-neutral-50 hover:border-neutral-300 transition-colors"
          >
            <p className="text-xs font-medium text-neutral-900 truncate">{job.title}</p>
            <p className="text-[10px] text-neutral-500">
              {jobStatusLabel(job.status)}
              {task_count > 0 && (
                <> · {finished_count} of {task_count} step{task_count === 1 ? '' : 's'} done</>
              )}
              {has_blocked && <span className="text-red-600"> · blocked</span>}
            </p>
            {/* QTY-1 (US-QTY-1-03) — how big this job is without opening it,
                and whether some of it went down an exception path. Null when
                there is nothing honest to say, so an older response that has
                no unit fields simply shows no line. */}
            {unitRowLabel({unit_total, units_moved_out}) && (
              <p data-testid="jobs-column-units" className="text-[10px] text-neutral-600">
                {unitRowLabel({unit_total, units_moved_out})}
              </p>
            )}
            {(job.parent_work_item_id > 0 || (child_count ?? 0) > 0) && (
              <p className="flex flex-wrap gap-1 mt-1" onClick={(e) => e.stopPropagation()}>
                {job.parent_work_item_id > 0 && (
                  <span
                    role="button"
                    tabIndex={0}
                    data-testid="jobs-column-parent-chip"
                    onClick={() => setPeekId(job.parent_work_item_id)}
                    className="rounded-full border border-amber-200 bg-amber-50 px-1.5 text-[10px] text-amber-800 hover:bg-amber-100 cursor-pointer"
                  >
                    from #{job.parent_work_item_id}
                  </span>
                )}
                {(child_count ?? 0) > 0 && (
                  <span
                    role="button"
                    tabIndex={0}
                    data-testid="jobs-column-children-chip"
                    onClick={() => setPeekId(job.id)}
                    className="rounded-full border border-amber-200 bg-amber-50 px-1.5 text-[10px] text-amber-800 hover:bg-amber-100 cursor-pointer"
                  >
                    {child_count} sent on
                  </span>
                )}
              </p>
            )}
          </button>
        ))}
      </div>

      <JobPeekSheet workItemId={peekId ?? 0} open={peekId != null} onClose={() => setPeekId(null)} onOpenJob={setPeekId} />
    </aside>
  );
}
