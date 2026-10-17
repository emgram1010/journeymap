// APP-2 (US-APP-2-04) — One session worked as a unit: header shows the
// provenance (job, flow, plan); steps list in planned order with the
// next one highlighted (D-4: order is a guide, not a lock); Start/Finish
// at the bottom. "Finish session" is pure navigation (D-1/D-2 — neither
// is its own server event), gated by `canFinishSession`.
import {ChevronLeft} from 'lucide-react';
import type {Session} from './sessionModel';
import {nextItemToWork, canFinishSession} from './sessionModel';
import type {TaskStatus} from './performerView';

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
  const next = nextItemToWork(session);
  const canFinish = canFinishSession(session);
  const notStarted = session.status === 'not_started';

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
        <ul className="space-y-2">
          {session.items.map((item) => {
            const sub = item.subSteps[0];
            const isNext = next?.itemRef === item.itemRef;
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
    </div>
  );
}
