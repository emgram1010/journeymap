// EXC-2 (US-EXC-2-02) — ONE read-only sheet that shows another job's
// steps and progress, used by BOTH the performer's step screen (via a
// "sent" or "came from" chip) and the planner's job detail (via the
// Exceptions panel's chips). D-2: one component, so the same job looks
// the same from either module.
//
// READ-ONLY (D-1). There is no Start/Done/Block button here — working a
// sent job's steps stays on its own assignee's Today screen. Nothing in
// this file writes anything.
//
// Q-1 (founder, 2026-10-27): a performer may see the other job's stage
// names, statuses, AND each step's task text + done-when (collapsed by
// default) — never another job's notes or activity feed.
//
// THE FOOTER'S CLOSE BUTTON SITS IN A FIXED FOOTER, same reachability
// rule as ExceptionSendPanel's Send sheet (ITEM-1 shipped a button no
// one could press once; every new tappable thing here is hit-tested at
// 375 px, E2E-EXC-2-05).
import {useCallback, useEffect, useState} from 'react';
import {X, ChevronRight} from 'lucide-react';
import {getWorkItem, getWorkItemLines, type WorkItemTask} from '../planner/plannerApi';
import {PerformRequestError} from '../perform/performApi';
import {getCatalogEntry} from '../ops/errorCatalog';
import {logEvent} from '../ops/logEvent';
import {progressFromTasks, progressLabel} from './jobProgress';
import {REASON_LABELS} from './exceptionSheet';
import {movedUnits, summarizeUnits, type UnitSummary} from '../jobModel';

type LoadedJob = Awaited<ReturnType<typeof getWorkItem>>;

type Props = {
  workItemId: number;
  open: boolean;
  onClose: () => void;
  /** Hop to another job's view (a parent or a child chip) without leaving the sheet. */
  onOpenJob?: (workItemId: number) => void;
};

const STATUS_LABEL: Record<WorkItemTask['status'], string> = {
  not_started: 'Not started',
  in_progress: 'In progress',
  blocked: 'Blocked',
  done: 'Done',
  skipped: 'Skipped',
};

const STATUS_PILL: Record<WorkItemTask['status'], string> = {
  not_started: 'bg-zinc-100 text-zinc-600',
  in_progress: 'bg-blue-50 text-blue-700',
  blocked: 'bg-red-50 text-red-700',
  done: 'bg-emerald-50 text-emerald-700',
  skipped: 'bg-zinc-100 text-zinc-500',
};

export default function JobPeekSheet({workItemId, open, onClose, onOpenJob}: Props) {
  const [job, setJob] = useState<LoadedJob | null>(null);
  const [loading, setLoading] = useState(false);
  const [errorCode, setErrorCode] = useState<'E-EXC-014' | 'E-EXC-015' | null>(null);
  const [reference, setReference] = useState<string | null>(null);
  const [expandedStep, setExpandedStep] = useState<number | null>(null);

  const load = useCallback(async () => {
    // Guard against a programming error (a bad id), not user input — this
    // sheet is never given a raw id to type (US-EXC-2-05 validation row).
    if (!Number.isInteger(workItemId) || workItemId <= 0) {
      // eslint-disable-next-line no-console
      console.error(`JobPeekSheet given a non-positive work_item_id: ${workItemId}`);
      return;
    }
    setLoading(true);
    setErrorCode(null);
    try {
      const data = await getWorkItem(workItemId);
      setJob(data);
    } catch (err) {
      const perr = err instanceof PerformRequestError ? err : null;
      const notFound = perr?.status === 404;
      setErrorCode(notFound ? 'E-EXC-015' : 'E-EXC-014');
      setReference(perr?.reference ?? null);
      void logEvent({
        feature: 'EXC-2',
        step: 'job_view_load',
        outcome: notFound ? 'rejected' : 'failure',
        severity: notFound ? 'info' : 'warn',
        errorCode: notFound ? 'E-EXC-015' : 'E-EXC-014',
        entityType: 'work_item',
        entityId: workItemId,
        correlationId: perr?.reference ?? null,
      });
    } finally {
      setLoading(false);
    }
  }, [workItemId]);

  useEffect(() => {
    if (!open) return;
    setJob(null);
    setExpandedStep(null);
    void load();
  }, [open, load]);

  // QTY-1 (US-QTY-1-01) — the job's units, on their own request. Separate
  // from `load` on purpose (D-4): the lines endpoint failing must not blank
  // the steps, the status or the version, so the two have their own states
  // and their own error. Keyed and cleared exactly like `load` above —
  // that symmetry is the only thing stopping one job's units showing under
  // another job's name when the sheet hops via a parent/child chip.
  const [units, setUnits] = useState<UnitSummary | null>(null);
  // An OBJECT, not a nullable reference string: a failure with no reference
  // still has to read as a failure, and `null` already means "no error".
  const [unitsError, setUnitsError] = useState<{reference: string | null} | null>(null);

  useEffect(() => {
    if (!open) return;
    if (!Number.isInteger(workItemId) || workItemId <= 0) return;
    let current = true;
    setUnits(null);
    setUnitsError(null);
    getWorkItemLines(workItemId)
      .then((data) => {
        if (current) setUnits(summarizeUnits(data.lines));
      })
      .catch((err) => {
        if (!current) return;
        const perr = err instanceof PerformRequestError ? err : null;
        setUnitsError({reference: perr?.reference ?? null});
        setUnits(null);
        void logEvent({
          feature: 'QTY-1',
          step: 'job_units_load',
          outcome: 'failure',
          severity: 'warn',
          entityType: 'work_item',
          entityId: workItemId,
          correlationId: perr?.reference ?? null,
        });
      });
    return () => {
      current = false;
    };
  }, [open, workItemId]);

  if (!open) return null;

  // QTY-1 (US-QTY-1-02) — both read `moved_lines`, which the job request
  // already returns on each link. A link that moved nothing is dropped, so
  // an unsplit job renders no lineage at all.
  const parentMoved = movedUnits(job?.parent ? [job.parent] : []);
  const childrenMoved = movedUnits(job?.children ?? []);

  const tasksInOrder = job?.tasks ?? [];
  // One rule, shared with the backend twin and the chips (jobProgress.ts).
  const progress = progressFromTasks(tasksInOrder);
  const currentStepId = tasksInOrder.find(
    (t) => t.stage_key === progress.current_stage_key && t.status !== 'done' && t.status !== 'skipped',
  )?.id;

  return (
    <div
      className="fixed inset-0 z-50 flex flex-col bg-white sm:inset-auto sm:right-4 sm:bottom-4 sm:top-4 sm:w-[420px] sm:rounded-xl sm:border sm:border-zinc-200 sm:shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-label="Job details (read-only)"
      data-testid="job-peek-sheet"
    >
      <header className="flex shrink-0 items-center justify-between border-b border-zinc-200 px-4 py-3">
        <div className="min-w-0">
          <p className="text-base font-semibold text-zinc-900" data-testid="job-peek-title">
            {job ? job.work_item.title : `Job #${workItemId}`}
          </p>
          {job && (
            <p className="text-xs text-zinc-500">
              {job.pinned_version.title} · v{job.pinned_version.version_no}
            </p>
          )}
        </div>
        <button
          type="button"
          aria-label="Close"
          data-testid="job-peek-close"
          onClick={onClose}
          className="w-11 h-11 -mr-2 flex items-center justify-center text-zinc-500"
        >
          <X className="w-5 h-5" />
        </button>
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        {loading && (
          <div className="space-y-2" aria-busy="true" data-testid="job-peek-loading">
            <div className="h-4 w-2/3 animate-pulse rounded bg-zinc-100" />
            <div className="h-4 w-full animate-pulse rounded bg-zinc-100" />
            <div className="h-4 w-full animate-pulse rounded bg-zinc-100" />
          </div>
        )}

        {!loading && errorCode && (
          <div role="alert" data-testid="job-peek-error" className="rounded-lg border border-red-200 bg-red-50 px-3 py-3 text-sm text-red-800">
            <p>{getCatalogEntry(errorCode)?.user_message ?? "We couldn't open that job."}</p>
            {reference && <p className="mt-1 text-xs text-red-600">Reference: {reference}</p>}
            {errorCode === 'E-EXC-014' && (
              <button type="button" data-testid="job-peek-retry" onClick={() => void load()} className="mt-2 min-h-[44px] text-sm font-medium underline">
                Try again
              </button>
            )}
          </div>
        )}

        {!loading && !errorCode && job && (
          <>
            <section data-testid="job-peek-progress">
              <p className="text-sm font-medium text-zinc-800">{job.derived_status}</p>
              <ProgressBar finishedCount={progress.finished_count} taskCount={progress.task_count} />
              <p className="mt-1 text-xs text-zinc-500">{progressLabel(progress)}</p>
            </section>

            {/* QTY-1 (US-QTY-1-01) — how many units this job is for. Sits
                next to the pinned version and the lineage on purpose: a
                parent job is NOT a template its children were stamped from
                (the map version is), and keeping version, units and lineage
                adjacent is what stops that misreading. See the epic's §10. */}
            <section data-testid="job-peek-units">
              <p className="mb-1 text-sm font-medium text-zinc-700">Units</p>
              {unitsError ? (
                <div role="alert" className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
                  <p>We couldn't load this job's units. The rest of the job is still accurate.</p>
                  {unitsError.reference && <p className="mt-0.5 text-amber-700">Reference: {unitsError.reference}</p>}
                </div>
              ) : units === null ? (
                <p className="text-xs text-zinc-400">Loading…</p>
              ) : units.totalQuantity === null ? (
                <p className="text-xs text-zinc-500">No units recorded on this job.</p>
              ) : (
                <>
                  <p className="text-sm text-zinc-800">{units.totalQuantity} total</p>
                  <ul className="mt-1 space-y-0.5">
                    {units.lines.map((l) => (
                      <li key={`${l.item_label}-${l.unit}`} className="text-xs text-zinc-600">
                        {l.quantity} {l.unit} · {l.item_label}
                      </li>
                    ))}
                  </ul>
                </>
              )}
            </section>

            {job.parent && (
              <button
                type="button"
                data-testid="job-peek-parent"
                onClick={() => onOpenJob?.(job.parent!.work_item_id)}
                className="flex min-h-[44px] w-full items-center gap-2 rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2 text-left"
              >
                <div className="min-w-0 flex-1">
                  <p className="text-sm text-zinc-800">
                    Came from <span className="font-medium">#{job.parent.work_item_id} · {job.parent.title}</span>
                  </p>
                  <p className="text-xs text-zinc-500">
                    Sent from {job.parent.stage_label || job.parent.stage_key} · {REASON_LABELS[job.parent.reason_code as keyof typeof REASON_LABELS] ?? job.parent.reason_code}
                  </p>
                  {/* QTY-1 (US-QTY-1-02) — which units came across. Already in
                      `moved_lines` on the link; nothing new is fetched. */}
                  {parentMoved.length > 0 && (
                    <p data-testid="job-peek-parent-moved" className="mt-0.5 text-xs font-medium text-zinc-700">
                      {parentMoved[0].quantity} {parentMoved[0].quantity === 1 ? 'unit' : 'units'} came from this job
                    </p>
                  )}
                  {job.parent.note && <p className="mt-0.5 text-xs text-zinc-600">"{job.parent.note}"</p>}
                </div>
                <ChevronRight className="h-4 w-4 flex-shrink-0 text-zinc-400" />
              </button>
            )}

            <section>
              <p className="mb-2 text-sm font-medium text-zinc-700">Steps</p>
              <ul className="space-y-1.5" data-testid="job-peek-steps">
                {tasksInOrder.map((t) => {
                  const isCurrent = t.id === currentStepId;
                  const isOpen = expandedStep === t.id;
                  return (
                    <li key={t.id} data-testid="job-peek-step" className="rounded-lg border border-zinc-200">
                      <button
                        type="button"
                        onClick={() => setExpandedStep(isOpen ? null : t.id)}
                        className="flex min-h-[44px] w-full items-center gap-2 px-3 py-2 text-left"
                      >
                        <div className="min-w-0 flex-1">
                          <p className="text-sm text-zinc-800">
                            {t.stage_label || t.stage_key}
                            {isCurrent && <span className="ml-1.5 rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-medium text-amber-800">Now</span>}
                          </p>
                          {t.owner_lens_label && <p className="text-xs text-zinc-500">{t.owner_lens_label}</p>}
                        </div>
                        <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${STATUS_PILL[t.status]}`}>{STATUS_LABEL[t.status]}</span>
                      </button>
                      {isOpen && (t.task || t.done_when) && (
                        <div className="border-t border-zinc-100 px-3 py-2 text-xs text-zinc-600 space-y-1">
                          {t.task && <p>{t.task}</p>}
                          {t.done_when && <p className="text-zinc-500">Done when: {t.done_when}</p>}
                        </div>
                      )}
                    </li>
                  );
                })}
              </ul>
            </section>

            {job.children.length > 0 && (
              <section>
                <p className="mb-2 text-sm font-medium text-zinc-700">Sent on</p>
                {/* QTY-1 (US-QTY-1-02) — what left this job and where it went,
                    named rather than only numbered, so the planner can
                    reconcile parent + children against the original order. */}
                {childrenMoved.length > 0 && (
                  <ul className="mb-2 space-y-0.5" data-testid="job-peek-children-moved">
                    {childrenMoved.map((m) => (
                      <li key={m.workItemId} className="text-xs text-zinc-600">
                        {m.quantity} {m.quantity === 1 ? 'unit' : 'units'} moved to{' '}
                        <span className="font-medium text-zinc-800">{m.title}</span> (#{m.workItemId})
                      </li>
                    ))}
                  </ul>
                )}
                <div className="flex flex-wrap gap-1.5" data-testid="job-peek-children">
                  {job.children.map((c) => (
                    <button
                      key={c.work_item_id}
                      type="button"
                      data-testid="job-peek-child-chip"
                      onClick={() => onOpenJob?.(c.work_item_id)}
                      className="min-h-[36px] rounded-full border border-amber-200 bg-amber-50 px-3 text-[12px] text-amber-800"
                    >
                      #{c.work_item_id} · {c.progress ? progressLabel(c.progress) : c.status}
                    </button>
                  ))}
                </div>
              </section>
            )}
          </>
        )}
      </div>

      {/* Fixed footer — never scrolls out of reach (E2E-EXC-2-05). */}
      <footer className="shrink-0 border-t border-zinc-200 bg-white px-4 py-3">
        <button type="button" data-testid="job-peek-footer-close" onClick={onClose} className="min-h-[44px] w-full rounded-lg border border-zinc-300 text-base text-zinc-700">
          Close
        </button>
      </footer>
    </div>
  );
}

function ProgressBar({finishedCount, taskCount}: {finishedCount: number; taskCount: number}) {
  const pct = taskCount === 0 ? 0 : Math.round((finishedCount / taskCount) * 100);
  return (
    <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-zinc-100" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
      <div className="h-full bg-emerald-500" style={{width: `${pct}%`}} />
    </div>
  );
}
