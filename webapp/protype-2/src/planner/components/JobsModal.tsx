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
import {useCallback, useEffect, useState} from 'react';
import {X, Briefcase, Plus, CalendarPlus, Ban, AlertTriangle} from 'lucide-react';
import type {Agent, Timeline} from '../types';
import {
  listWorkspaceMaps,
  listWorkItems,
  listBacklogWork,
  createWorkItem,
  cancelWorkItem,
  scheduleWorkTask,
  type RawWorkspaceMap,
  type WorkItemListEntry,
  type BacklogWorkRow,
} from '../plannerApi';

interface JobsModalProps {
  isOpen: boolean;
  workspaceId: string | null;
  workspaceName: string;
  agents: Agent[];
  timelines: Timeline[];
  planningWindowStart: string;
  onClose: () => void;
  /**
   * Returns the timeline id for (agent, date), creating the day if it
   * doesn't exist yet. Lives in PlannerApp because `createTimeline` is
   * idempotent there and the board has to be refetched either way —
   * this modal should not own a second copy of that rule.
   */
  onEnsureTimeline: (agentId: string, date: string) => Promise<string | null>;
  /** Refetch the board after anything here changes it. */
  onChanged: () => void;
}

const JOB_STATUS_LABELS: Record<string, string> = {
  open: 'Not started',
  in_progress: 'In progress',
  blocked: 'Blocked',
  completed: 'Done',
  cancelled: 'Cancelled',
};

export function JobsModal({
  isOpen,
  workspaceId,
  workspaceName,
  agents,
  timelines,
  planningWindowStart,
  onClose,
  onEnsureTimeline,
  onChanged,
}: JobsModalProps) {
  const [maps, setMaps] = useState<RawWorkspaceMap[]>([]);
  const [jobs, setJobs] = useState<WorkItemListEntry[]>([]);
  const [backlog, setBacklog] = useState<BacklogWorkRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // New-job form
  const [newTitle, setNewTitle] = useState('');
  const [newMapId, setNewMapId] = useState<number | null>(null);
  const [isCreating, setIsCreating] = useState(false);

  // Scheduling: which step is being placed, and where
  const [schedulingFor, setSchedulingFor] = useState<number | null>(null);
  const [scheduleAgentId, setScheduleAgentId] = useState<string>('');
  const [scheduleDate, setScheduleDate] = useState<string>('');
  const [isScheduling, setIsScheduling] = useState(false);
  const [confirmCancelId, setConfirmCancelId] = useState<number | null>(null);

  const load = useCallback(async (wsId: string, isPlanChange = false) => {
    setIsLoading(true);
    setError(null);
    // Switching plans must CLEAR first. Leaving the previous plan's jobs
    // and maps on screen while the new ones load shows one plan's work
    // under another plan's name — briefly, but long enough to act on
    // (an E2E run picked exactly that stale list and believed it).
    if (isPlanChange) {
      setMaps([]);
      setJobs([]);
      setBacklog([]);
      setNewMapId(null);
    }
    try {
      const [mapData, jobData, backlogData] = await Promise.all([
        listWorkspaceMaps(Number(wsId)),
        listWorkItems(Number(wsId)),
        listBacklogWork(Number(wsId)),
      ]);
      setMaps(mapData.maps);
      setJobs(jobData.work_items);
      setBacklog(backlogData.backlog);
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
    setSchedulingFor(null);
    setConfirmCancelId(null);
    setScheduleAgentId(agents[0]?.id ?? '');
    setScheduleDate(planningWindowStart || new Date().toISOString().slice(0, 10));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen]);

  useEffect(() => {
    if (isOpen && workspaceId) void load(workspaceId, true);
  }, [isOpen, workspaceId, load]);

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

  const handleSchedule = async (workTaskId: number) => {
    if (!scheduleAgentId || !scheduleDate) {
      setError('Pick who does it and which day.');
      return;
    }
    setIsScheduling(true);
    setError(null);
    setNotice(null);
    try {
      const timelineId = await onEnsureTimeline(scheduleAgentId, scheduleDate);
      if (!timelineId) {
        setError("Couldn't open that day for scheduling.");
        return;
      }
      const result = await scheduleWorkTask(workTaskId, {timeline_id: Number(timelineId)});
      setNotice(
        `Scheduled for ${scheduleDate} (${result.scheduled_minutes} min). Publish the day to send it to Execution.`,
      );
      setSchedulingFor(null);
      if (workspaceId) await load(workspaceId);
      onChanged();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't schedule that step.");
    } finally {
      setIsScheduling(false);
    }
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

  const agentName = (id: string) => agents.find((a) => a.id === id)?.name ?? '';
  const dayHasTimeline = (agentId: string, date: string) =>
    timelines.some((t) => t.agentId === agentId && t.plannedDate === date);

  return (
    <div
      id="jobs-modal-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4"
      onClick={onClose}
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
                {jobs.map(({work_item: job, task_count, finished_count, has_blocked}) => (
                  <li key={job.id} className="px-3 py-2 flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="text-xs font-medium text-neutral-900 truncate">{job.title}</p>
                      <p className="text-[10px] text-neutral-500">
                        {JOB_STATUS_LABELS[job.status] ?? job.status} · {finished_count} of {task_count} step
                        {task_count === 1 ? '' : 's'} done
                        {has_blocked && <span className="text-red-600"> · blocked</span>}
                      </p>
                    </div>
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
                  </li>
                ))}
              </ul>
            )}
          </section>

          {/* ── Steps waiting to be scheduled ───────────────────────── */}
          <section>
            <h3 className="text-xs font-semibold text-neutral-900 mb-1">Steps waiting for a day</h3>
            <p className="text-[11px] text-neutral-500 mb-2">
              Each one is a real step from its job's published map. Scheduling it keeps the agreed minutes — it just makes
              room for it on someone's day.
            </p>
            {backlog.length === 0 ? (
              <p className="text-[11px] text-neutral-500">
                {jobs.length === 0 ? 'Create a job above and its steps appear here.' : 'Every step is scheduled.'}
              </p>
            ) : (
              <ul className="divide-y divide-neutral-100 border border-neutral-200 rounded-md">
                {backlog.map((row) => (
                  <li key={row.work_task_id} className="px-3 py-2 flex flex-col gap-2">
                    <div className="flex items-center justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-xs text-neutral-900 truncate">{row.task ?? `${row.job_title ?? 'Job'} — ${row.stage_key}`}</p>
                        <p className="text-[10px] text-neutral-500 truncate">
                          {row.job_title}
                          {row.expected_minutes != null && ` · ${row.expected_minutes} min`}
                        </p>
                        {row.done_when && <p className="text-[10px] text-neutral-400 truncate">Done when: {row.done_when}</p>}
                      </div>
                      <button
                        type="button"
                        onClick={() => setSchedulingFor(schedulingFor === row.work_task_id ? null : row.work_task_id)}
                        className="shrink-0 flex items-center gap-1 px-2 py-1 text-[11px] font-medium text-neutral-700 border border-neutral-200 rounded hover:bg-neutral-50"
                      >
                        <CalendarPlus className="w-3 h-3" />
                        Schedule
                      </button>
                    </div>

                    {schedulingFor === row.work_task_id && (
                      <div className="flex flex-wrap items-end gap-2 bg-neutral-50 border border-neutral-200 rounded-md px-2.5 py-2">
                        <label className="flex flex-col gap-1">
                          <span className="text-[10px] text-neutral-600">Who</span>
                          <select
                            value={scheduleAgentId}
                            onChange={(e) => setScheduleAgentId(e.target.value)}
                            className="text-[11px] px-2 py-1 border border-neutral-200 rounded bg-white"
                          >
                            {agents.length === 0 && <option value="">No agents in this plan</option>}
                            {agents.map((a) => (
                              <option key={a.id} value={a.id}>{a.name}</option>
                            ))}
                          </select>
                        </label>
                        <label className="flex flex-col gap-1">
                          <span className="text-[10px] text-neutral-600">Day</span>
                          <input
                            type="date"
                            value={scheduleDate}
                            onChange={(e) => setScheduleDate(e.target.value)}
                            className="text-[11px] px-2 py-1 border border-neutral-200 rounded font-mono bg-white"
                          />
                        </label>
                        <button
                          type="button"
                          onClick={() => void handleSchedule(row.work_task_id)}
                          disabled={isScheduling || agents.length === 0}
                          className="px-3 py-1.5 bg-neutral-900 text-white rounded text-[11px] font-semibold hover:bg-neutral-800 disabled:opacity-60"
                        >
                          {isScheduling ? 'Placing…' : 'Place'}
                        </button>
                        {scheduleAgentId && scheduleDate && !dayHasTimeline(scheduleAgentId, scheduleDate) && (
                          <span className="text-[10px] text-neutral-500 basis-full">
                            {agentName(scheduleAgentId)} has no day on {scheduleDate} yet — it will be created.
                          </span>
                        )}
                        {scheduleAgentId && !agents.find((a) => a.id === scheduleAgentId)?.userId && (
                          <span className="text-[10px] text-amber-700 basis-full flex items-center gap-1">
                            <AlertTriangle className="w-3 h-3 shrink-0" />
                            {agentName(scheduleAgentId)} has no login linked — they won't see this in Execution.
                          </span>
                        )}
                      </div>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </section>
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
    </div>
  );
}
