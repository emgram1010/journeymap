// GAP-FIX W1 (2026-10-17) — The missing middle of the loop.
//
// THE DEAD STOP THIS FIXES. You publish a map, make a plan, attach the
// map — and then "Add task" gives you a plain text task that looks like
// every other task, because it is one. There was no screen anywhere
// that turned a map into real work. Two separate things existed:
//
//   planner_task  a scheduling slot: a title, a duration, a position on
//                 someone's day. Knows nothing about maps. ← "Add task"
//   work_item     a JOB: a real instance of the work ("Quote for the
//   + work_task   Garcia party"), whose steps are generated from the
//                 map's frozen version and carry the real instructions,
//                 done-when and durations. ← no screen created one
//
// The backend for the second was complete and tested (JOB-1's 554–558,
// SCHED-1's 559–560). The end-to-end proof earlier in this project
// worked precisely because those jobs were created by direct API call.
// Only the screen was missing. This is the screen.
//
// THREE THINGS IN ONE PLACE, because they are one task in the planner's
// head: start a job from a map, see the jobs in this plan, and put
// their steps on someone's day.
//
// BOARD-1 (2026-10-28) — SCHEDULING LEFT THIS MODAL. "Work waiting for
// a day", "Already on a day" and the pick-who/pick-day form moved to
// the planner's main screen (the Jobs column + drag onto a day, see
// JobsColumn.tsx), the same way RPT-1 moved Planned-vs-actual out. What
// remains here is PER-JOB: create a job from a map, its lines, its
// exceptions, its activity. `focusJobId` opens it straight onto one job
// when a Jobs-column title is clicked.
//
// BLK-1 (US-BLK-1-07, 2026-10-21) — A ROW IS A CARD, NOT A STEP.
// Stories 01-03 made the backlog return one row per (job, actor row)
// and gave the server a card-level schedule and release, and this
// screen was left pointing at the old per-step shape. It was not
// merely behind: 559's response no longer had `work_task_id`, `task`
// or `stage_key` in it, so every row rendered `undefined`, every row's
// key was `undefined`, and `schedulingFor === row.work_task_id` was
// therefore true for ALL of them at once — one click opened every
// scheduler on the list. A card is keyed by `card_key`
// (`work_item_id::lens_key`) precisely because `work_task_id` is no
// longer one row's identity.
import {useCallback, useEffect, useRef, useState} from 'react';
import {X, Briefcase, Plus, Ban, ChevronRight, ChevronDown} from 'lucide-react';
import {
  listWorkspaceMaps,
  listWorkItems,
  createWorkItem,
  cancelWorkItem,
  getWorkItemActivity,
  type ActivityEvent,
  type RawWorkspaceMap,
  type WorkItemListEntry,
} from '../plannerApi';
import {reasonLabel, eventLabel} from '../varianceDisplay';
import {jobStatusLabel} from '../../jobModel';
import {JobLinesEditor} from './JobLinesEditor';
import ExceptionSendPanel from '../../exceptions/ExceptionSendPanel';
import JobPeekSheet from '../../exceptions/JobPeekSheet';

interface JobsModalProps {
  isOpen: boolean;
  workspaceId: string | null;
  workspaceName: string;
  /** BOARD-1 — open straight onto this job's detail (a Jobs-column title click). */
  focusJobId?: number | null;
  onClose: () => void;
  /** Refetch the board after anything here changes it. */
  onChanged: () => void;
}

export function JobsModal({
  isOpen,
  workspaceId,
  workspaceName,
  focusJobId,
  onClose,
  onChanged,
}: JobsModalProps) {
  const [maps, setMaps] = useState<RawWorkspaceMap[]>([]);
  const [jobs, setJobs] = useState<WorkItemListEntry[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // New-job form
  const [newTitle, setNewTitle] = useState('');
  const [newMapId, setNewMapId] = useState<number | null>(null);
  const [isCreating, setIsCreating] = useState(false);
  // W3 — what came back from Execution, fetched per job only when the
  // planner opens it: the activity log (577).
  //
  // RPT-1 (2026-10-27) — the variance report (568) used to be fetched
  // here too, for the "Planned vs actual" block. That block is now its
  // own page (Reports → Plan vs Action), so opening a job no longer
  // pulls a report nobody asked to read.
  const [openJobId, setOpenJobId] = useState<number | null>(null);
  const [reportFor, setReportFor] = useState<number | null>(null);
  const [activity, setActivity] = useState<ActivityEvent[]>([]);
  const [isLoadingReport, setIsLoadingReport] = useState(false);
  const [reportError, setReportError] = useState<string | null>(null);
  const [confirmCancelId, setConfirmCancelId] = useState<number | null>(null);
  // EXC-2 (US-EXC-2-04) — sent work that is not in this plan opens in the read-only view.
  const [peekId, setPeekId] = useState<number | null>(null);

  const load =useCallback(async (wsId: string, isPlanChange = false) => {
    setIsLoading(true);
    setError(null);
    // Switching plans must CLEAR first. Leaving the previous plan's jobs
    // and maps on screen while the new ones load shows one plan's work
    // under another plan's name — briefly, but long enough to act on
    // (an E2E run picked exactly that stale list and believed it).
    if (isPlanChange) {
      setMaps([]);
      setJobs([]);
      setNewMapId(null);
    }
    try {
      const [mapData, jobData] = await Promise.all([
        listWorkspaceMaps(Number(wsId)),
        listWorkItems(Number(wsId)),
      ]);
      setMaps(mapData.maps);
      setJobs(jobData.work_items);
      setNewMapId((prev) => (prev !== null && mapData.maps.some((m) => m.map_id === prev) ? prev : mapData.maps[0]?.map_id ?? null));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't load this plan's jobs.");
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Reset the form only when the modal OPENS — the same rule the
  // "New plan" modal had to be fixed to follow (gap-fix Part 1 #7):
  // resetting whenever loaded data arrives erases what was typed.
  useEffect(() => {
    if (!isOpen) return;
    setNewTitle('');
    setError(null);
    setNotice(null);
    setConfirmCancelId(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen]);

  useEffect(() => {
    if (isOpen && workspaceId) void load(workspaceId, true);
  }, [isOpen, workspaceId, load]);

  // BOARD-1 — opened from a Jobs-column title: expand that job's detail
  // once its row exists. One shot per open (the ref), so the planner can
  // still collapse it or open another without this effect fighting back.
  const focusedOnceRef = useRef<number | null>(null);
  useEffect(() => {
    if (!isOpen) {
      focusedOnceRef.current = null;
      return;
    }
    if (focusJobId == null || focusedOnceRef.current === focusJobId) return;
    if (!jobs.some((j) => j.work_item.id === focusJobId)) return;
    focusedOnceRef.current = focusJobId;
    showJob(focusJobId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, focusJobId, jobs]);

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
        `"${title}" created with ${result.task_count} step${result.task_count === 1 ? '' : 's'}, pinned to version ${result.pinned_version.version_no}. Schedule them below.`,
      );
      await load(workspaceId);
      onChanged();
    } catch (err) {
      // The server's messages here already name the map and say what to
      // do (E-JOB-002 "add it to the plan's maps first", E-JOB-003
      // "hasn't been published yet"), so they are shown as-is.
      setError(err instanceof Error ? err.message : "Couldn't create that job.");
    } finally {
      setIsCreating(false);
    }
  };

  // W3 — loaded on demand, not with the list: a plan with twenty jobs
  // should not fetch twenty reports nobody asked for.
  const openReport = async (workItemId: number) => {
    if (openJobId === workItemId) {
      setOpenJobId(null);
      return;
    }
    setOpenJobId(workItemId);
    setIsLoadingReport(true);
    setReportError(null);
    setActivity([]);
    try {
      const a = await getWorkItemActivity(workItemId);
      setReportFor(workItemId);
      setActivity(a.events);
    } catch (err) {
      setReportError(err instanceof Error ? err.message : "Couldn't load what came back for this job.");
    } finally {
      setIsLoadingReport(false);
    }
  };

  // EXC-1 — the "from #…" / "sent on" chips are links, not toggles: they
  // open the other job (never close it) and bring it on screen.
  const showJob = (workItemId: number) => {
    if (openJobId !== workItemId) void openReport(workItemId);
    requestAnimationFrame(() => document.getElementById(`job-row-${workItemId}`)?.scrollIntoView({block: 'center'}));
  };

  // EXC-2 (US-EXC-2-04) — a chip for sent work: in this plan's list →
  // expand and scroll to its row; otherwise the read-only job view.
  const openSentJob = (childId: number) => {
    if (jobs.some((j) => j.work_item.id === childId)) showJob(childId);
    else setPeekId(childId);
  };

  // "N sent on": one child in this plan → that child. Otherwise (several,
  // or the one child lives elsewhere) → open the parent and bring its
  // Exceptions block into view, where each child has its own chip.
  const openSentWork = (parentId: number) => {
    const kids = jobs.filter((j) => j.work_item.parent_work_item_id === parentId);
    const entry = jobs.find((j) => j.work_item.id === parentId);
    if (kids.length === 1 && (entry?.child_count ?? 0) === 1) {
      showJob(kids[0].work_item.id);
      return;
    }
    // The Exceptions block lists them all — but it only renders on a job that
    // can still send, so on a finished or cancelled parent there is nothing
    // to scroll to and the chip would do nothing at all. Its read-only view
    // lists the same sent work (D-2), so that is the fallback.
    const status = entry?.work_item.status;
    if (status === 'completed' || status === 'cancelled') {
      setPeekId(parentId);
      return;
    }
    if (openJobId !== parentId) void openReport(parentId);
    const scrollToExceptions = (triesLeft: number) =>
      requestAnimationFrame(() => {
        const el = document.getElementById(`job-exceptions-${parentId}`);
        if (el) el.scrollIntoView({block: 'center'});
        else if (triesLeft > 0) setTimeout(() => scrollToExceptions(triesLeft - 1), 150);
      });
    scrollToExceptions(10);
  };

  const handleCancel = async (workItemId: number) => {
    setError(null);
    setNotice(null);
    try {
      const result = await cancelWorkItem(workItemId);
      setConfirmCancelId(null);
      setNotice(result.message || 'Job cancelled.');
      if (workspaceId) await load(workspaceId);
      onChanged();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't cancel that job.");
    }
  };

  return (
    <div
      id="jobs-modal-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4"
      // With the job view open, a click beside it closes just that view — the
      // sheet renders inside this overlay, so the old `onClose` threw away the
      // whole Jobs modal (and the expanded job) instead of the sheet.
      onClick={() => (peekId != null ? setPeekId(null) : onClose())}
    >
      <div
        id="jobs-modal"
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-2xl flex flex-col max-h-[88vh] overflow-hidden"
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
          <p className="text-[11px] text-neutral-500">
            A job is one real run of a map's work — "Quote for the Garcia party", not "Quoting". Its steps come from the
            map's published version and carry the real instructions, so the person doing it sees what to do and how they
            know it's done. A plain task (the "Add task" button on the board) carries none of that.
          </p>

          {error && <p className="text-xs text-red-600 bg-red-50 border border-red-200 rounded-md px-3 py-2">{error}</p>}
          {notice && <p className="text-xs text-emerald-800 bg-emerald-50 border border-emerald-200 rounded-md px-3 py-2">{notice}</p>}

          {/* ── New job ─────────────────────────────────────────────── */}
          <section>
            <h3 className="text-xs font-semibold text-neutral-900 mb-2">New job</h3>
            {maps.length === 0 ? (
              <p className="text-[11px] text-neutral-500">
                This plan doesn't use any maps yet. Add one in <span className="font-medium">Workspace Settings → Maps in
                this plan</span> first — a job has to follow a published map.
              </p>
            ) : (
              <div className="flex flex-col gap-2">
                <input
                  id="new-job-title-input"
                  type="text"
                  value={newTitle}
                  onChange={(e) => { setNewTitle(e.target.value); setError(null); }}
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
                      <option key={m.map_id} value={m.map_id}>{m.title ?? `Map #${m.map_id}`}</option>
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

          {/* ── Jobs in this plan ───────────────────────────────────── */}
          <section>
            <h3 className="text-xs font-semibold text-neutral-900 mb-2">Jobs in this plan</h3>
            {isLoading && jobs.length === 0 ? (
              <p className="text-[11px] text-neutral-400">Loading…</p>
            ) : jobs.length === 0 ? (
              <p className="text-[11px] text-neutral-500">No jobs yet.</p>
            ) : (
              <ul className="divide-y divide-neutral-100 border border-neutral-200 rounded-md">
                {jobs.map(({work_item: job, task_count, finished_count, has_blocked, child_count}) => (
                  <li key={job.id} id={`job-row-${job.id}`} className="px-3 py-2 flex flex-col gap-2">
                  <div className="flex items-center justify-between gap-3">
                    {/* W3 — the whole row opens the report. Everything the
                        performer reported was already in the database and
                        had no screen; this is the screen. */}
                    <button
                      type="button"
                      onClick={() => void openReport(job.id)}
                      className="min-w-0 flex items-start gap-1.5 text-left flex-1"
                      aria-expanded={openJobId === job.id}
                    >
                      {openJobId === job.id ? (
                        <ChevronDown className="w-3.5 h-3.5 mt-0.5 shrink-0 text-neutral-400" />
                      ) : (
                        <ChevronRight className="w-3.5 h-3.5 mt-0.5 shrink-0 text-neutral-400" />
                      )}
                      <span className="min-w-0">
                        <span className="block text-xs font-medium text-neutral-900 truncate">{job.title}</span>
                        <span className="block text-[10px] text-neutral-500">
                          {jobStatusLabel(job.status)} · {finished_count} of {task_count} step
                          {task_count === 1 ? '' : 's'} done
                          {has_blocked && <span className="text-red-600"> · blocked</span>}
                        </span>
                      </span>
                    </button>
                    {/* EXC-1 (US-EXC-1-05) — the link both ways. Clicking opens the other job. */}
                    {job.parent_work_item_id > 0 && (
                      <button
                        type="button"
                        data-testid="job-parent-chip"
                        onClick={() => showJob(job.parent_work_item_id)}
                        className="shrink-0 rounded-full border border-amber-200 bg-amber-50 px-2 py-0.5 text-[10px] text-amber-800 hover:bg-amber-100"
                        title="Opens the job this one came from"
                      >
                        from #{job.parent_work_item_id}
                      </button>
                    )}
                    {(child_count ?? 0) > 0 && (
                      <button
                        type="button"
                        data-testid="job-children-chip"
                        onClick={() => openSentWork(job.id)}
                        className="shrink-0 rounded-full border border-amber-200 bg-amber-50 px-2 py-0.5 text-[10px] text-amber-800 hover:bg-amber-100"
                        title="Opens the work sent from this job"
                      >
                        {child_count} sent on
                      </button>
                    )}
                    {job.status !== 'cancelled' && (
                      confirmCancelId === job.id ? (
                        <div className="flex items-center gap-1.5 shrink-0">
                          <span className="text-[10px] text-red-700">Unscheduled steps are dropped.</span>
                          <button
                            type="button"
                            onClick={() => void handleCancel(job.id)}
                            className="px-2 py-1 text-[11px] font-semibold text-white bg-red-600 hover:bg-red-700 rounded"
                          >
                            Cancel job
                          </button>
                          <button
                            type="button"
                            onClick={() => setConfirmCancelId(null)}
                            className="px-2 py-1 text-[11px] text-neutral-600 hover:text-neutral-900"
                          >
                            Keep
                          </button>
                        </div>
                      ) : (
                        <button
                          type="button"
                          onClick={() => setConfirmCancelId(job.id)}
                          className="shrink-0 flex items-center gap-1 px-2 py-1 text-[11px] text-neutral-500 hover:text-red-700 hover:bg-red-50 rounded"
                        >
                          <Ban className="w-3 h-3" />
                          Cancel
                        </button>
                      )
                    )}
                  </div>

                  {/* ── W3: what came back ──────────────────────────── */}
                  {openJobId === job.id && (
                    <div className="rounded-md border border-neutral-200 bg-neutral-50/60 p-2.5 flex flex-col gap-3">
                      {isLoadingReport && reportFor !== job.id ? (
                        <p className="text-[11px] text-neutral-400">Loading…</p>
                      ) : reportError ? (
                        <p className="text-[11px] text-red-600">{reportError}</p>
                      ) : (
                        <>
                          {/* EXC-1 (US-EXC-1-05) — what was sent off this job, and the planner's own "Send to…" */}
                          {job.status !== 'cancelled' && job.status !== 'completed' && (
                            <div id={`job-exceptions-${job.id}`}>
                              <p className="text-[11px] font-semibold text-neutral-800 mb-1">Exceptions</p>
                              <ExceptionSendPanel
                                workItemId={job.id}
                                variant="planner"
                                onOpenJob={openSentJob}
                                onSent={() => {
                                  if (workspaceId) void load(workspaceId);
                                  onChanged();
                                }}
                              />
                            </div>
                          )}

                          <div>
                            <JobLinesEditor
                              workItemId={job.id}
                              onEstimateChanged={() => {
                                if (workspaceId) void load(workspaceId);
                              }}
                            />
                          </div>

                          <div>
                            <p className="text-[11px] font-semibold text-neutral-800">What the performer reported</p>
                            {activity.length === 0 ? (
                              <p className="text-[10px] text-neutral-500 mt-1">
                                Nothing recorded yet — this job hasn't been worked on.
                              </p>
                            ) : (
                              <ul className="mt-1 flex flex-col gap-1">
                                {activity.map((e) => (
                                  <li key={e.id} className="text-[10px] bg-white border border-neutral-200 rounded px-2 py-1">
                                    <span className="font-medium text-neutral-800">{eventLabel(e.event_type)}</span>
                                    {e.step_title && <span className="text-neutral-500"> · {e.step_title}</span>}
                                    {e.performer_name && <span className="text-neutral-400"> · {e.performer_name}</span>}
                                    {e.event_type === 'blocked' && reasonLabel(e.reason_code) && (
                                      <span className="text-red-700"> · {reasonLabel(e.reason_code)}</span>
                                    )}
                                    {e.note && <span className="block text-neutral-700 mt-0.5">“{e.note}”</span>}
                                  </li>
                                ))}
                              </ul>
                            )}
                          </div>

                          {/* RPT-1 (2026-10-27) — where Planned vs actual went.
                              A sentence, not a link: this is a modal over the
                              planner, and navigating away would throw away
                              everything the planner has open behind it. */}
                          <p className="text-[10px] text-neutral-400">
                            Planned vs actual now lives in Reports → Plan vs Action.
                          </p>
                        </>
                      )}
                    </div>
                  )}
                  </li>
                ))}
              </ul>
            )}
          </section>

          {/* BOARD-1 (2026-10-28) — where scheduling went. "Work waiting for
              a day" and "Already on a day" are now the planner's main screen:
              the Jobs column lists the waiting cards, dragging one onto a
              day places it, and each day column shows what it carries. */}
          <p className="text-[11px] text-neutral-400 border-t border-neutral-100 pt-3">
            Scheduling moved to the board — drag a card from the Jobs column onto someone's day, or use its Place… button.
          </p>
        </div>

        <div className="h-14 px-6 border-t border-neutral-200 flex items-center justify-end bg-neutral-50 shrink-0">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800"
          >
            Done
          </button>
        </div>
      </div>
      {/* The sheet sits inside the overlay; its clicks must not reach the overlay's close-on-click. */}
      <div onClick={(e) => e.stopPropagation()}>
        <JobPeekSheet workItemId={peekId ?? 0} open={peekId != null} onClose={() => setPeekId(null)} onOpenJob={setPeekId} />
      </div>
    </div>
  );
}
