// APP-2 (US-APP-2-03) — Today: the day's sessions, one card each, ordered
// by the planned start of their first step. A thin render over
// `sessionModel.ts`'s pure `Session[]` — no grouping/ordering logic lives
// here, only display.
import type {Session} from './sessionModel';
import {nextItemToWork} from './sessionModel';

const STATUS_LABELS: Record<Session['status'], string> = {
  not_started: 'Not started',
  in_progress: 'In progress',
  blocked: 'Blocked',
  done: 'Done',
  skipped: 'Skipped',
};

const STATUS_COLORS: Record<Session['status'], string> = {
  not_started: 'bg-zinc-100 text-zinc-600',
  in_progress: 'bg-blue-100 text-blue-800',
  blocked: 'bg-red-100 text-red-800',
  done: 'bg-emerald-100 text-emerald-800',
  skipped: 'bg-zinc-200 text-zinc-500',
};

// Same fallback SessionScreen's own row label uses: `item.title` comes
// from the frozen snapshot and is blank for some job-derived steps
// (same root cause as the Planner's blank-titles bug — see the epic's
// Follow-ups — just hit here too). Falls back to the stage name, then
// the item's own ref, so "Next up" is never an empty label.
function nextUpLabel(session: Session): string | null {
  const item = nextItemToWork(session);
  if (!item) return null;
  return item.title || item.subSteps[0]?.stageLabel || item.itemRef;
}

function formatMinutes(total: number): string {
  if (total < 60) return `${total} min`;
  const hours = Math.floor(total / 60);
  const minutes = total % 60;
  return minutes === 0 ? `${hours} hr` : `${hours} hr ${minutes} min`;
}

export default function TodayScreen({
  date,
  sessions,
  onOpenSession,
}: {
  date: string | undefined;
  sessions: Session[];
  onOpenSession: (workItemId: number) => void;
}) {
  const sessionsDone = sessions.filter((s) => s.status === 'done').length;
  const nextSession = sessions.find((s) => s.status !== 'done' && s.status !== 'skipped');

  return (
    <div className="min-h-screen bg-zinc-50">
      <header className="sticky top-0 bg-white border-b border-zinc-200 px-4 py-3">
        <h1 className="text-base font-semibold text-zinc-900">Today</h1>
        <p className="text-xs text-zinc-400">{date}</p>
        {sessions.length > 0 && (
          <p className="mt-1 text-xs text-zinc-500">
            {sessions.length} session{sessions.length === 1 ? '' : 's'} · {sessionsDone} done · {sessions.length - sessionsDone} remaining
          </p>
        )}
      </header>

      <main className="px-4 py-4 pb-24">
        {sessions.length === 0 ? (
          <p className="text-sm text-zinc-500 text-center mt-16">Nothing is scheduled for you today.</p>
        ) : (
          <ul className="space-y-3">
            {sessions.map((session) => {
              const isNext = nextSession?.workItemId === session.workItemId;
              return (
                <li key={session.workItemId}>
                  <button
                    type="button"
                    onClick={() => onOpenSession(session.workItemId)}
                    className={`w-full text-left rounded-xl border bg-white p-4 min-h-[44px] ${
                      isNext ? 'border-zinc-900 ring-1 ring-zinc-900' : 'border-zinc-200'
                    }`}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-xs text-zinc-400">{session.plannedStartLabel}</p>
                        <p className="text-sm font-medium text-zinc-900">{session.title}</p>
                        {session.flowTitle && <p className="text-xs text-zinc-500">{session.flowTitle}</p>}
                      </div>
                      <span className={`shrink-0 rounded-full px-2 py-1 text-[11px] font-medium ${STATUS_COLORS[session.status]}`}>
                        {STATUS_LABELS[session.status]}
                      </span>
                    </div>
                    <p className="mt-2 text-xs text-zinc-500">
                      {session.totalCount} step{session.totalCount === 1 ? '' : 's'} · {formatMinutes(session.totalScheduledMinutes)} ·{' '}
                      {session.doneCount} of {session.totalCount} done
                    </p>
                    {isNext && nextUpLabel(session) && (
                      <p className="mt-1 text-xs font-medium text-zinc-700">Next up: {nextUpLabel(session)}</p>
                    )}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </main>
    </div>
  );
}
