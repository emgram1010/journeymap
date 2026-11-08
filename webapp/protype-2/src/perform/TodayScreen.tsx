// APP-2 (US-APP-2-03) — Today: the day's sessions, one card each, ordered
// by the planned start of their first step. A thin render over
// `sessionModel.ts`'s pure `Session[]` — no grouping/ordering logic lives
// here, only display.
//
// GAP-FIX W4 (2026-10-17) — the screen is no longer locked to today.
// `perform/today` has always accepted a date; nothing ever passed one,
// so a performer could not look at yesterday's day or check tomorrow's,
// and work published for another day read as "nothing scheduled".
//
// GAP-FIX W5 — and when a day IS empty, it now says which of the four
// possible reasons applies. The decision itself is `diagnoseEmptyDay`
// in `dayNavigation.ts`, tested on its own; this file only renders it.
import {Clock, ChevronLeft, ChevronRight} from 'lucide-react';
import type {Session} from './sessionModel';
import {nextItemToWork, todaySummary} from './sessionModel';
import {formatDayLabel, type EmptyDayDiagnosis} from './dayNavigation';
import {formatWindow} from '../planner/timeWindowModel';
import StatusPill from './ui/StatusPill';

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
  isToday,
  sessions,
  diagnosis,
  onOpenSession,
  onPrevDay,
  onNextDay,
  onGoToToday,
  onJumpTo,
}: {
  date: string | undefined;
  isToday: boolean;
  sessions: Session[];
  diagnosis: EmptyDayDiagnosis;
  onOpenSession: (workItemId: number) => void;
  onPrevDay: () => void;
  onNextDay: () => void;
  onGoToToday: () => void;
  onJumpTo: (date: string) => void;
}) {
  const nextSession = sessions.find((s) => s.status !== 'done' && s.status !== 'skipped');
  const summary = todaySummary(sessions);

  return (
    <div className="min-h-screen bg-zinc-50">
      <header className="sticky top-0 bg-white border-b border-zinc-200 px-4 py-3">
        <div className="flex items-center justify-between gap-2">
          <div className="min-w-0">
            <h1 className="text-base font-semibold text-zinc-900">{isToday ? 'Today' : formatDayLabel(date ?? '')}</h1>
            <p className="text-xs text-zinc-400">{date}</p>
          </div>
          {/* 44px tap targets: this is a phone-first screen (US-APP-2-05). */}
          <div className="flex items-center gap-1 shrink-0">
            <button
              type="button"
              aria-label="Previous day"
              onClick={onPrevDay}
              className="w-11 h-11 flex items-center justify-center rounded-lg border border-zinc-200 text-zinc-600 active:bg-zinc-100"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            {!isToday && (
              <button
                type="button"
                onClick={onGoToToday}
                className="h-11 px-3 rounded-lg border border-zinc-200 text-xs font-medium text-zinc-700 active:bg-zinc-100"
              >
                Today
              </button>
            )}
            <button
              type="button"
              aria-label="Next day"
              onClick={onNextDay}
              className="w-11 h-11 flex items-center justify-center rounded-lg border border-zinc-200 text-zinc-600 active:bg-zinc-100"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
        {sessions.length > 0 && (
          <p className="mt-1 text-xs text-zinc-500">
            {summary.jobCount} job{summary.jobCount === 1 ? '' : 's'} {isToday ? 'today' : 'scheduled'}
            {summary.inProgressCount > 0 && (
              <>
                {' '}
                · <span className="font-medium text-blue-700">{summary.inProgressCount} in progress</span>
              </>
            )}
          </p>
        )}
      </header>

      <main className="px-4 py-4 pb-36">
        {sessions.length === 0 ? (
          <div id="perform-empty-state" className="mt-12 mx-auto max-w-xs text-center">
            <p className="text-sm font-medium text-zinc-800">{diagnosis.headline}</p>
            <p className="mt-2 text-xs text-zinc-500">{diagnosis.detail}</p>
            {diagnosis.jumpTo && (
              <button
                type="button"
                id="perform-jump-to-work-btn"
                onClick={() => onJumpTo(diagnosis.jumpTo!)}
                className="mt-4 min-h-[44px] w-full rounded-lg bg-zinc-900 px-4 text-sm font-medium text-white"
              >
                Go to {formatDayLabel(diagnosis.jumpTo)}
              </button>
            )}
          </div>
        ) : (
          <ul className="space-y-3">
            {sessions.map((session) => {
              const isNext = nextSession?.workItemId === session.workItemId;
              const isInProgress = session.status === 'in_progress';
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
                      {/* Time first: the planned start is the biggest thing on the card. */}
                      <div className="flex shrink-0 flex-col min-w-[52px]">
                        <span className="text-lg font-bold tabular-nums text-zinc-900">{session.plannedStartLabel}</span>
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-medium text-zinc-900 truncate">{session.title}</p>
                        {session.flowTitle && <p className="text-xs text-zinc-500 truncate">{session.flowTitle}</p>}
                        <p className="mt-1 text-xs text-zinc-500">
                          {session.totalCount} step{session.totalCount === 1 ? '' : 's'} · {formatMinutes(session.totalScheduledMinutes)} ·{' '}
                          {session.doneCount} of {session.totalCount} done
                        </p>
                        {/* Thin progress bar: doneCount already counts skipped as finished, same as canFinishSession. */}
                        <div className="mt-1.5 h-1 w-full overflow-hidden rounded-full bg-zinc-100">
                          <div
                            className="h-full rounded-full bg-zinc-900"
                            style={{width: `${session.totalCount === 0 ? 0 : Math.round((session.doneCount / session.totalCount) * 100)}%`}}
                          />
                        </div>
                        {isInProgress && nextUpLabel(session) && (
                          <p className="mt-1.5 flex items-center gap-1.5 text-xs font-medium text-blue-700">
                            <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-blue-600" aria-hidden="true" />
                            <span className="truncate">Next up: {nextUpLabel(session)}</span>
                          </p>
                        )}
                        {/* TW-1 (US-TW-1-05) — read-only; no window, no clutter. */}
                        {session.timeWindow && (
                          <p className="mt-1.5 flex items-center gap-1 text-xs text-zinc-500">
                            <Clock className="h-3 w-3 shrink-0" aria-hidden="true" />
                            Time window {formatWindow(session.timeWindow)}
                          </p>
                        )}
                      </div>
                      <div className="shrink-0 pt-0.5">
                        <StatusPill status={session.status} size="sm" />
                      </div>
                    </div>
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
