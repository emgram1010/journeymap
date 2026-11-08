// PUX-1 (US-PUX-1-01/02) — ONE panel for ONE job, opened from every place a
// job appears (Jobs column, a board card, an Unscheduled row, the Jobs list).
//
// A SIDE PANEL, NOT A MODAL: no scrim, so the board the planner is arranging
// stays visible beside it. Sections follow the order of a planner's questions:
// what is it → when may it happen → where did I put it → what's in it → what
// went wrong → what happened.
//
// The per-job blocks were MOVED here from JobsModal, not copied — that modal is
// now only the list of jobs (US-PUX-1-05). PERF-1's rules carry over: `lines`
// is fetched once and shared by JobLinesEditor and ExceptionSendPanel, and every
// in-flight request is aborted when the panel closes or switches job.
//
// "Where it's scheduled" is derived from the board payload already in memory
// (jobScheduleModel), never a new request.
import {useCallback, useEffect, useRef, useState} from 'react';
import {X, Ban, CalendarDays, ChevronRight} from 'lucide-react';
import {
  getWorkItem,
  getWorkItemActivity,
  getWorkItemLines,
  cancelWorkItem,
  type ActivityEvent,
  type RawWorkItem,
  type WorkItemTask,
  type WorkItemLinesResult,
  type JobParentLink,
  type JobChildLink,
  type RawTimeWindow,
} from '../plannerApi';
import {reasonLabel, eventLabel, formatMinutes} from '../varianceDisplay';
import {groupTasksByRole} from '../../jobModel';
import {jobPlanStatus, type Placement} from '../jobScheduleModel';
import {formatDayShort} from '../timeWindowModel';
import {TimeWindowEditor} from './TimeWindowEditor';
import {JobPlanBadge} from './JobPlanBadge';
import {JobLinesEditor} from './JobLinesEditor';
import ExceptionSendPanel from '../../exceptions/ExceptionSendPanel';

interface JobPanelProps {
  workItemId: number | null;
  /** This job's slots on the board, from `jobPlacements` (PlannerApp owns the board). */
  placements: Placement[];
  timeWindow: RawTimeWindow | null;
  planWindow: {start: string | null; end: string | null};
  onClose: () => void;
  /** Open another job in this same panel (exception links). */
  onOpenJob: (workItemId: number) => void;
  /** Jump the board to a day and highlight that timeline. */
  onJumpTo: (placement: Placement) => void;
  onWindowChanged: (workItemId: number, window: RawTimeWindow | null, needsRepublish: boolean) => void;
  /** Anything that can move work on/off a day or change the job list. */
  onChanged: () => void;
}


export function JobPanel({
  workItemId,
  placements,
  timeWindow,
  planWindow,
  onClose,
  onOpenJob,
  onJumpTo,
  onWindowChanged,
  onChanged,
}: JobPanelProps) {
  const [job, setJob] = useState<RawWorkItem | null>(null);
  const [parent, setParent] = useState<JobParentLink | null>(null);
  const [children, setChildren] = useState<JobChildLink[]>([]);
  const [steps, setSteps] = useState<WorkItemTask[]>([]);
  const [activity, setActivity] = useState<ActivityEvent[]>([]);
  const [lines, setLines] = useState<WorkItemLinesResult | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isLoadingLines, setIsLoadingLines] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [linesError, setLinesError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [expandedStepId, setExpandedStepId] = useState<number | null>(null);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const abortRef = useRef<AbortController | null>(null);

  const load = useCallback((id: number) => {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const {signal} = controller;
    setIsLoading(true);
    setIsLoadingLines(true);
    setError(null);
    setLinesError(null);

    getWorkItem(id, signal)
      .then((w) => {
        setJob(w.work_item);
        setParent(w.parent);
        setChildren(w.children ?? []);
        setSteps(w.tasks);
      })
      .catch((err: unknown) => {
        if (!signal.aborted) setError(err instanceof Error ? err.message : "Couldn't load this job.");
      })
      .finally(() => {
        if (!signal.aborted) setIsLoading(false);
      });

    getWorkItemActivity(id, signal)
      .then((a) => setActivity(a.events))
      .catch(() => {
        /* History is secondary; the rest of the panel still works. */
      });

    getWorkItemLines(id, signal)
      .then((r) => setLines(r))
      .catch((err: unknown) => {
        if (!signal.aborted) setLinesError(err instanceof Error ? err.message : "Could not load this order's items.");
      })
      .finally(() => {
        if (!signal.aborted) setIsLoadingLines(false);
      });
  }, []);

  const refetchLines = useCallback(async (id: number) => {
    setIsLoadingLines(true);
    try {
      setLines(await getWorkItemLines(id));
    } catch (err) {
      setLinesError(err instanceof Error ? err.message : "Could not load this order's items.");
    } finally {
      setIsLoadingLines(false);
    }
  }, []);

  // Switching job clears first, so one job's details never show under another's title.
  useEffect(() => {
    setJob(null);
    setParent(null);
    setChildren([]);
    setSteps([]);
    setActivity([]);
    setLines(null);
    setNotice(null);
    setConfirmCancel(false);
    setExpandedStepId(null);
    if (workItemId != null) load(workItemId);
    else abortRef.current?.abort();
  }, [workItemId, load]);

  useEffect(() => () => abortRef.current?.abort(), []);

  useEffect(() => {
    if (workItemId == null) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      // Something is open ON TOP (Edit Step, the overload question, the
      // exception sheet): Escape belongs to that, not to the whole panel —
      // closing the panel here would throw away what was typed in it.
      if (document.querySelector('[aria-modal="true"], [role="alertdialog"], [data-testid="exception-sheet"]')) return;
      onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [workItemId, onClose]);

  if (workItemId == null) return null;

  const isCancelled = job?.status === 'cancelled';
  const isFinished = job?.status === 'completed';
  const doneCount = steps.filter((s) => s.status === 'done' || s.status === 'skipped').length;
  const plan = job ? jobPlanStatus({status: job.status, totalSteps: steps.length}, placements) : null;

  const handleCancel = async () => {
    try {
      const result = await cancelWorkItem(workItemId);
      setConfirmCancel(false);
      setNotice(result.message || 'Job cancelled.');
      load(workItemId);
      onChanged();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't cancel that job.");
    }
  };

  const roleGroups = groupTasksByRole(steps);

  return (
    <aside
      id="job-panel"
      data-testid="job-panel"
      aria-label="Job details"
      className="fixed top-0 right-0 z-40 h-full w-full sm:w-[440px] bg-white border-l border-neutral-200 shadow-xl flex flex-col"
    >
      {/* ── What is it ─────────────────────────────────────────────── */}
      <div className="px-5 py-4 border-b border-neutral-200 bg-neutral-50 shrink-0">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-neutral-500">Job</p>
            <h2 data-testid="job-panel-title" className="text-sm font-bold text-neutral-900 break-words">
              {job?.title ?? (isLoading ? 'Loading…' : '')}
            </h2>
            {job && plan && (
              <p className="mt-1 flex flex-wrap items-center gap-1.5 text-[11px] text-neutral-600">
                <JobPlanBadge status={plan} testId="job-panel-status" />
                <span>
                  {doneCount} of {steps.length} step{steps.length === 1 ? '' : 's'} done
                </span>
              </p>
            )}
            {(parent || children.length > 0) && (
              <p className="mt-1.5 flex flex-wrap gap-1">
                {parent && (
                  <button
                    type="button"
                    data-testid="job-panel-parent"
                    onClick={() => onOpenJob(parent.work_item_id)}
                    className="rounded-full border border-amber-200 bg-amber-50 px-2 py-0.5 text-[10px] text-amber-800 hover:bg-amber-100"
                  >
                    from {parent.title}
                  </button>
                )}
                {children.map((c) => (
                  <button
                    key={c.work_item_id}
                    type="button"
                    data-testid="job-panel-child"
                    onClick={() => onOpenJob(c.work_item_id)}
                    className="rounded-full border border-amber-200 bg-amber-50 px-2 py-0.5 text-[10px] text-amber-800 hover:bg-amber-100"
                  >
                    sent on: {c.title}
                  </button>
                ))}
              </p>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close job"
            className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50 shrink-0"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-5 py-4 flex flex-col gap-5">
        {error && (
          <div data-testid="job-panel-error" className="flex items-center justify-between gap-2 text-xs text-red-600 bg-red-50 border border-red-200 rounded-md px-3 py-2">
            <span>{error}</span>
            <button type="button" data-testid="job-panel-retry" onClick={() => load(workItemId)} className="shrink-0 font-semibold underline">
              Try again
            </button>
          </div>
        )}
        {notice && <p className="text-xs text-emerald-800 bg-emerald-50 border border-emerald-200 rounded-md px-3 py-2">{notice}</p>}
        {isCancelled && (
          <p data-testid="job-panel-readonly" className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-md px-3 py-2">
            Cancelled — this job is read-only. Its history stays.
          </p>
        )}

        {/* ── When may it happen ───────────────────────────────────── */}
        <section>
          {isCancelled ? (
            <p className="text-[11px] text-neutral-600">{timeWindow ? 'Time window kept as history.' : 'No time window.'}</p>
          ) : (
            <TimeWindowEditor
              workItemId={workItemId}
              window={timeWindow}
              planWindow={planWindow}
              onChanged={(w, needsRepublish) => {
                onWindowChanged(workItemId, w, needsRepublish);
                setNotice(
                  needsRepublish
                    ? 'Time window saved. This day has already gone live — Publish to live again so the performer sees it.'
                    : 'Time window saved.',
                );
              }}
            />
          )}
        </section>

        {/* ── Where did I put it ───────────────────────────────────── */}
        <section data-testid="job-panel-where">
          <h3 className="text-[11px] font-semibold text-neutral-800 mb-1.5 flex items-center gap-1.5">
            <CalendarDays className="w-3.5 h-3.5 text-neutral-500" />
            Where it's scheduled
          </h3>
          {placements.length === 0 ? (
            <p className="text-[11px] text-neutral-500">Not on any day in this plan yet.</p>
          ) : (
            <ul className="flex flex-col gap-1">
              {placements.map((p) => (
                <li key={p.timelineId}>
                  <button
                    type="button"
                    data-testid="job-panel-placement"
                    onClick={() => onJumpTo(p)}
                    className="w-full flex items-center justify-between gap-2 rounded border border-neutral-200 bg-white px-2.5 py-1.5 text-left text-[11px] hover:bg-neutral-50"
                    title="Show this day on the board"
                  >
                    <span className="min-w-0 truncate">
                      <span className="font-medium text-neutral-900">{p.agentName}</span>
                      <span className="text-neutral-500"> · {formatDayShort(p.date)} · {p.start || '--:--'} · </span>
                      <span className="text-neutral-700">
                        {p.steps} step{p.steps === 1 ? '' : 's'}
                      </span>
                      {p.published && <span className="ml-1 text-emerald-700">· live</span>}
                    </span>
                    <ChevronRight className="w-3.5 h-3.5 text-neutral-400 shrink-0" />
                  </button>
                </li>
              ))}
            </ul>
          )}
          {plan && plan.left > 0 && !isCancelled && !isFinished && (
            <p data-testid="job-panel-unscheduled" className="mt-1.5 text-[11px] text-amber-800">
              {plan.left} step{plan.left === 1 ? '' : 's'} not scheduled — waiting in Unscheduled below the board (use Place… there).
            </p>
          )}
        </section>

        {/* ── What's in it: steps ──────────────────────────────────── */}
        <section>
          <h3 className="text-[11px] font-semibold text-neutral-800 mb-1.5">Steps</h3>
          {isLoading && steps.length === 0 ? (
            <p className="text-[11px] text-neutral-400">Loading…</p>
          ) : steps.length === 0 ? (
            <p className="text-[11px] text-neutral-500">This job has no steps yet.</p>
          ) : (
            (() => {
              const stepRow = (t: WorkItemTask) => {
                const isOpen = expandedStepId === t.id;
                return (
                  <li key={t.id} className="rounded border border-neutral-200 bg-white">
                    <button
                      type="button"
                      onClick={() => setExpandedStepId(isOpen ? null : t.id)}
                      aria-expanded={isOpen}
                      className="w-full px-2 py-1.5 flex items-center justify-between gap-2 text-left hover:bg-neutral-50"
                    >
                      <span className="min-w-0">
                        <span className="block text-[11px] text-neutral-800 truncate">{t.stage_label || t.stage_key}</span>
                        {!roleGroups && t.owner_lens_label && <span className="block text-[10px] text-neutral-500">{t.owner_lens_label}</span>}
                      </span>
                      <span className="shrink-0 flex items-center gap-1.5">
                        {t.expected_minutes != null && <span className="text-[10px] text-neutral-500 font-mono">{formatMinutes(t.expected_minutes)}</span>}
                        <span className="text-[10px] font-medium text-neutral-600">{t.status.replace('_', ' ')}</span>
                      </span>
                    </button>
                    {isOpen && (t.task || t.done_when) && (
                      <div className="border-t border-neutral-100 px-2 py-1.5 text-[10px] text-neutral-600 space-y-0.5">
                        {t.task && <p>{t.task}</p>}
                        {t.done_when && <p className="text-neutral-500">Done when: {t.done_when}</p>}
                      </div>
                    )}
                  </li>
                );
              };
              return roleGroups ? (
                <div className="flex flex-col gap-2">
                  {roleGroups.map((g) => (
                    <div key={g.lensKey}>
                      <p className="text-[10px] font-semibold text-neutral-500 uppercase tracking-wide mb-1">
                        {g.lensLabel} · {g.tasks.length} step{g.tasks.length === 1 ? '' : 's'}
                      </p>
                      <ul className="flex flex-col gap-1">{g.tasks.map(stepRow)}</ul>
                    </div>
                  ))}
                </div>
              ) : (
                <ul className="flex flex-col gap-1">{steps.map(stepRow)}</ul>
              );
            })()
          )}
        </section>

        {/* ── What's in it: items ──────────────────────────────────── */}
        <section>
          <JobLinesEditor
            workItemId={workItemId}
            lines={lines}
            isLoading={isLoadingLines}
            loadError={linesError}
            onSaved={(result) => {
              setLines(result);
              onChanged();
            }}
          />
        </section>

        {/* ── What went wrong ──────────────────────────────────────── */}
        {!isCancelled && !isFinished && job && (
          <section>
            <h3 className="text-[11px] font-semibold text-neutral-800 mb-1">Exceptions</h3>
            <ExceptionSendPanel
              workItemId={workItemId}
              variant="planner"
              lines={lines}
              onLinesStale={() => void refetchLines(workItemId)}
              onOpenJob={onOpenJob}
              onSent={() => {
                load(workItemId);
                onChanged();
              }}
            />
          </section>
        )}

        {/* ── What happened ────────────────────────────────────────── */}
        <section>
          <h3 className="text-[11px] font-semibold text-neutral-800">What the performer reported</h3>
          {activity.length === 0 ? (
            <p className="text-[10px] text-neutral-500 mt-1">Nothing recorded yet — this job hasn't been worked on.</p>
          ) : (
            <ul className="mt-1 flex flex-col gap-1">
              {activity.map((e) => (
                <li key={e.id} className="text-[10px] bg-white border border-neutral-200 rounded px-2 py-1">
                  <span className="font-medium text-neutral-800">{eventLabel(e.event_type)}</span>
                  {e.step_title && <span className="text-neutral-500"> · {e.step_title}</span>}
                  {e.performer_name && <span className="text-neutral-400"> · {e.performer_name}</span>}
                  {e.event_type === 'blocked' && reasonLabel(e.reason_code) && <span className="text-red-700"> · {reasonLabel(e.reason_code)}</span>}
                  {e.note && <span className="block text-neutral-700 mt-0.5">“{e.note}”</span>}
                </li>
              ))}
            </ul>
          )}
          <p className="mt-2 text-[10px] text-neutral-400">Planned vs actual lives in Reports → Plan vs Action.</p>
        </section>
      </div>

      {/* ── Cancel lives at the bottom, away from everyday actions ───── */}
      {job && !isCancelled && (
        <div className="px-5 py-3 border-t border-neutral-200 bg-neutral-50 shrink-0 flex items-center justify-end gap-2">
          {confirmCancel ? (
            <>
              <span className="text-[10px] text-red-700">Unscheduled steps are dropped.</span>
              <button
                type="button"
                data-testid="job-panel-cancel-confirm"
                onClick={() => void handleCancel()}
                className="px-2 py-1 text-[11px] font-semibold text-white bg-red-600 hover:bg-red-700 rounded"
              >
                Cancel job
              </button>
              <button type="button" onClick={() => setConfirmCancel(false)} className="px-2 py-1 text-[11px] text-neutral-600 hover:text-neutral-900">
                Keep
              </button>
            </>
          ) : (
            <button
              type="button"
              data-testid="job-panel-cancel"
              onClick={() => setConfirmCancel(true)}
              className="flex items-center gap-1 px-2 py-1 text-[11px] text-neutral-500 hover:text-red-700 hover:bg-red-50 rounded"
            >
              <Ban className="w-3 h-3" />
              Cancel job
            </button>
          )}
        </div>
      )}
    </aside>
  );
}
