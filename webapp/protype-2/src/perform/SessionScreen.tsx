// APP-2 (US-APP-2-04) — One session worked as a unit: header shows the
// provenance (job, flow, plan); steps list in planned order with the
// next one highlighted (D-4: order is a guide, not a lock); Start/Finish
// at the bottom. "Finish session" is pure navigation (D-1/D-2 — neither
// is its own server event), gated by `canFinishSession`.
import {ChevronLeft, ChevronRight} from 'lucide-react';
import {useEffect, useState} from 'react';
import type {Session} from './sessionModel';
import {nextSubStepToWork, canFinishSession} from './sessionModel';
import type {TaskStatus} from './performerView';
import {getWorkItemLinks, type JobParentLink} from '../planner/plannerApi';
import JobPeekSheet from '../exceptions/JobPeekSheet';

const STATUS_LABELS: Record<TaskStatus, string> = {
  not_started: 'Not started',
  in_progress: 'In progress',
  blocked: 'Blocked',
  done: 'Done',
  skipped: 'Skipped',
};

const STATUS_COLORS: Record<TaskStatus, string> = {
  not_started: 'bg-zinc-100 text-zinc-600',
  in_progress: 'bg-blue-100 text-blue-800',
  blocked: 'bg-red-100 text-red-800',
  done: 'bg-emerald-100 text-emerald-800',
  skipped: 'bg-zinc-200 text-zinc-500',
};

export default function SessionScreen({
  session,
  pending,
  onBack,
  onOpenStep,
  onStartSession,
  onFinishSession,
}: {
  session: Session;
  pending: boolean;
  onBack: () => void;
  onOpenStep: (workTaskId: number) => void;
  onStartSession: () => void;
  onFinishSession: () => void;
}) {
  const next = nextSubStepToWork(session);
  const canFinish = canFinishSession(session);
  const notStarted = session.status === 'not_started';

  // EXC-2 (US-EXC-2-03) — "Came from", for a job that itself was sent
  // here from another one. This screen makes no other request today,
  // so one getWorkItemLinks call on open is the whole cost (never a
  // second one — this effect re-fires only when the job itself changes).
  const [parentLink, setParentLink] = useState<JobParentLink | null>(null);
  const [peekId, setPeekId] = useState<number | null>(null);
  useEffect(() => {
    setParentLink(null);
    let cancelled = false;
    void getWorkItemLinks(session.workItemId)
      .then((links) => {
        if (!cancelled) setParentLink(links.parent ?? null);
      })
      .catch(() => {
        // Best effort: no "Came from" chip is a quiet degrade, not a
        // blocking failure — the session still works without it.
      });
    return () => {
      cancelled = true;
    };
  }, [session.workItemId]);

  return (
    <div className="min-h-screen bg-zinc-50 pb-28">
      <header className="sticky top-0 bg-white border-b border-zinc-200 px-3 py-3 flex items-start gap-2">
        <button
          type="button"
          onClick={onBack}
          aria-label="Back to today"
          className="w-11 h-11 -ml-1 shrink-0 flex items-center justify-center text-zinc-700"
        >
          <ChevronLeft className="w-5 h-5" />
        </button>
        <div className="min-w-0 pt-1.5">
          <h1 className="text-base font-semibold text-zinc-900 truncate">{session.title}</h1>
          <p className="text-xs text-zinc-500 truncate">
            {[session.flowTitle, session.planName].filter(Boolean).join(' · ')}
          </p>
        </div>
      </header>

      <main className="px-4 py-4">
        {/* EXC-2 (US-EXC-2-03) — this job came from a send; follow it back read-only. */}
        {parentLink && (
          <button
            type="button"
            data-testid="session-came-from-chip"
            aria-label={`See where this job came from: #${parentLink.work_item_id}`}
            onClick={() => setPeekId(parentLink.work_item_id)}
            className="mb-3 flex min-h-[44px] w-full items-center gap-2 rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2 text-left"
          >
            <div className="min-w-0 flex-1 text-sm text-zinc-700">
              Came from <span className="font-medium">#{parentLink.work_item_id} · {parentLink.stage_label || parentLink.stage_key}</span>
            </div>
            <ChevronRight className="h-4 w-4 flex-shrink-0 text-zinc-400" />
          </button>
        )}

        {/*
          BLK-1 (US-BLK-1-04) — a card can hold a whole order's work for
          one actor row, so EVERY stage inside it is listed and tappable.
          This used to render `subSteps[0]` only: on a two-step card the
          second stage was unreachable, with nothing on screen to say it
          existed.

          A single-step card still renders as one plain row, exactly as
          before, so nothing changes for a plan that has not been
          scheduled as cards.
        */}
        <ul className="space-y-2">
          {session.items.map((item) => {
            const isBlock = item.subSteps.length > 1;

            if (!isBlock) {
              const sub = item.subSteps[0];
              const isNext = next?.workTaskId === sub?.workTaskId;
              const label = item.title || sub?.stageLabel || item.itemRef;
              return (
                <li key={item.itemRef}>
                  <button
                    type="button"
                    onClick={() => sub && onOpenStep(sub.workTaskId)}
                    className={`w-full text-left rounded-xl border bg-white p-3 min-h-[44px] ${
                      isNext ? 'border-zinc-900 ring-1 ring-zinc-900' : 'border-zinc-200'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-xs text-zinc-400">{item.plannedStartLabel}</p>
                        <p className="text-sm font-medium text-zinc-900 truncate">{label}</p>
                      </div>
                      <span className={`shrink-0 rounded-full px-2 py-1 text-[11px] font-medium ${STATUS_COLORS[item.status]}`}>
                        {STATUS_LABELS[item.status]}
                      </span>
                    </div>
                  </button>
                </li>
              );
            }

            const rowLabel = item.subSteps[0]?.lensLabel;
            return (
              <li key={item.itemRef} className="rounded-xl border border-zinc-200 bg-white overflow-hidden">
                <div className="flex items-center justify-between gap-3 px-3 pt-3 pb-2">
                  <div className="min-w-0">
                    <p className="text-xs text-zinc-400">{item.plannedStartLabel}</p>
                    <p className="text-sm font-medium text-zinc-900 truncate">
                      {item.title || rowLabel || item.itemRef}
                    </p>
                    <p className="text-xs text-zinc-500">
                      {item.subSteps.length} steps · {item.scheduledMinutes} min
                    </p>
                  </div>
                  <span className={`shrink-0 rounded-full px-2 py-1 text-[11px] font-medium ${STATUS_COLORS[item.status]}`}>
                    {STATUS_LABELS[item.status]}
                  </span>
                </div>
                <ol className="border-t border-zinc-100">
                  {item.subSteps.map((sub, index) => {
                    const isNext = next?.workTaskId === sub.workTaskId;
                    return (
                      <li key={sub.workTaskId} className="border-b border-zinc-100 last:border-b-0">
                        <button
                          type="button"
                          onClick={() => onOpenStep(sub.workTaskId)}
                          className={`w-full text-left px-3 py-2.5 min-h-[44px] flex items-center justify-between gap-3 ${
                            isNext ? 'bg-zinc-50 ring-1 ring-inset ring-zinc-900' : ''
                          }`}
                        >
                          <div className="min-w-0 flex items-start gap-2">
                            <span className="text-xs text-zinc-400 pt-0.5 shrink-0">{index + 1}.</span>
                            <div className="min-w-0">
                              <p className="text-sm text-zinc-900 truncate">{sub.stageLabel || sub.stageKey}</p>
                              {sub.expectedMinutes != null && (
                                <p className="text-xs text-zinc-400">{sub.expectedMinutes} min</p>
                              )}
                            </div>
                          </div>
                          <span
                            className={`shrink-0 rounded-full px-2 py-1 text-[11px] font-medium ${STATUS_COLORS[sub.status]}`}
                          >
                            {isNext ? 'Next' : STATUS_LABELS[sub.status]}
                          </span>
                        </button>
                      </li>
                    );
                  })}
                </ol>
              </li>
            );
          })}
        </ul>
      </main>

      {/* Primary action in the bottom third (US-APP-2-08) */}
      <div className="fixed bottom-0 inset-x-0 bg-white border-t border-zinc-200 p-4">
        {notStarted ? (
          <button
            type="button"
            onClick={onStartSession}
            disabled={pending}
            className="w-full min-h-[44px] rounded-lg bg-zinc-900 px-4 py-3 text-base font-medium text-white disabled:opacity-50"
          >
            Start session
          </button>
        ) : (
          <>
            <button
              type="button"
              onClick={onFinishSession}
              disabled={!canFinish}
              className="w-full min-h-[44px] rounded-lg bg-zinc-900 px-4 py-3 text-base font-medium text-white disabled:opacity-40"
            >
              Finish session
            </button>
            {!canFinish && (
              <p className="mt-2 text-xs text-zinc-500 text-center">Finish or skip the remaining steps first.</p>
            )}
          </>
        )}
      </div>

      <JobPeekSheet workItemId={peekId ?? 0} open={peekId != null} onClose={() => setPeekId(null)} onOpenJob={setPeekId} />
    </div>
  );
}
