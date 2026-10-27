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
import {getWorkItem, type WorkItemTask} from '../planner/plannerApi';
import {PerformRequestError} from '../perform/performApi';
import {getCatalogEntry} from '../ops/errorCatalog';
import {logEvent} from '../ops/logEvent';
import {progressLabel} from './jobProgress';
import {REASON_LABELS} from './exceptionSheet';

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

  if (!open) return null;

  const tasksInOrder = job?.tasks ?? [];

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
              <ProgressBar finishedCount={countFinished(tasksInOrder)} taskCount={tasksInOrder.length} />
              <p className="mt-1 text-xs text-zinc-500">{progressLabelForTasks(tasksInOrder)}</p>
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
                  {job.parent.note && <p className="mt-0.5 text-xs text-zinc-600">"{job.parent.note}"</p>}
                </div>
                <ChevronRight className="h-4 w-4 flex-shrink-0 text-zinc-400" />
              </button>
            )}

            <section>
              <p className="mb-2 text-sm font-medium text-zinc-700">Steps</p>
              <ul className="space-y-1.5" data-testid="job-peek-steps">
                {tasksInOrder.map((t) => {
                  const isCurrent = isCurrentStep(t, tasksInOrder);
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
                            {t.stage_label ?? t.stage_key}
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

function countFinished(tasks: readonly WorkItemTask[]): number {
  return tasks.filter((t) => t.status === 'done' || t.status === 'skipped').length;
}

function progressLabelForTasks(tasks: readonly WorkItemTask[]): string {
  // Stage order/labels for THIS job are implicit in the tasks' own order
  // (555 returns them in the pinned version's stage order already), so
  // the sheet derives the label straight from the loaded tasks rather
  // than re-deriving stage positions the server already resolved.
  const total = tasks.length;
  const finished = countFinished(tasks);
  if (total === 0) return 'No steps';
  if (finished === total) return 'Done';
  const current = tasks.find((t) => isCurrentStep(t, tasks));
  const blocked = tasks.some((t) => t.status === 'blocked');
  const stageLabel = current?.stage_label ?? current?.stage_key ?? '';
  const base = `${finished} of ${total} done`;
  return blocked ? `${base} · blocked at ${stageLabel}` : `${base} · at ${stageLabel}`;
}

/** The first unfinished task, in the order 555 already returns (pinned stage order). */
function isCurrentStep(t: WorkItemTask, all: readonly WorkItemTask[]): boolean {
  const firstUnfinished = all.find((x) => x.status !== 'done' && x.status !== 'skipped');
  return firstUnfinished?.id === t.id;
}

function ProgressBar({finishedCount, taskCount}: {finishedCount: number; taskCount: number}) {
  const pct = taskCount === 0 ? 0 : Math.round((finishedCount / taskCount) * 100);
  return (
    <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-zinc-100" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
      <div className="h-full bg-emerald-500" style={{width: `${pct}%`}} />
    </div>
  );
}
