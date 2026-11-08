// APP-2 (US-APP-2-04) — One session worked as a unit: header shows the
// provenance (job, flow, plan); steps list in planned order with the
// next one highlighted (D-4: order is a guide, not a lock); Start/Finish
// at the bottom. "Finish job" is pure navigation (D-1/D-2 — neither
// is its own server event), gated by `canFinishSession`.
//
// EXEC-1 (US-EXEC-1-04) — redesigned into tabs (Overview · Steps ·
// Notes · Details), following the design prompt. Overview, Steps and
// Notes (US-EXEC-1-05) are built here; Details (US-EXEC-1-06) is a
// placeholder until its own story lands.
import {ChevronLeft, ChevronRight} from 'lucide-react';
import {useEffect, useState} from 'react';
import type {Session} from './sessionModel';
import {nextSubStepToWork, canFinishSession, jobProgress, jobNotes} from './sessionModel';
import {getWorkItemLinks, getWorkItemLines, type JobParentLink, type WorkItemLine} from '../planner/plannerApi';
import {formatWindow} from '../planner/timeWindowModel';
import JobPeekSheet from '../exceptions/JobPeekSheet';
import StatusPill from './ui/StatusPill';
import ProgressRing from './ui/ProgressRing';

export type JobTab = 'overview' | 'steps' | 'notes' | 'details';

const TAB_LABELS: Record<JobTab, string> = {
  overview: 'Overview',
  steps: 'Steps',
  notes: 'Notes',
  details: 'Details',
};

function nextUpLabel(sub: ReturnType<typeof nextSubStepToWork>): string | null {
  if (!sub) return null;
  return sub.stageLabel || sub.stageKey;
}

function formatCompletedTime(ms: number): string {
  return new Date(ms).toLocaleTimeString(undefined, {hour: 'numeric', minute: '2-digit'});
}

/** "Done 10:42 AM · Jav" (design prompt's checklist line) — null for any step not yet done/skipped, or missing a timestamp. */
function completedLine(sub: {status: string; completedAt: number | null; completedBy: string | null}): string | null {
  if ((sub.status !== 'done' && sub.status !== 'skipped') || !sub.completedAt) return null;
  const verb = sub.status === 'done' ? 'Done' : 'Skipped';
  const time = formatCompletedTime(sub.completedAt);
  return sub.completedBy ? `${verb} ${time} · ${sub.completedBy}` : `${verb} ${time}`;
}

function formatNoteTime(ms: number): string {
  return new Date(ms).toLocaleString(undefined, {month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'});
}

/** "08:00" — 24h, wraps a day that runs past midnight. Same format `plannedStartLabel` already uses, so the window reads consistently with the rest of the screen. */
function formatWindowTime(totalMinutes: number): string {
  const clamped = ((totalMinutes % 1440) + 1440) % 1440;
  const hours = Math.floor(clamped / 60);
  const minutes = clamped % 60;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

export default function SessionScreen({
  session,
  pending,
  offline = false,
  activeTab,
  onChangeTab,
  onBack,
  onOpenStep,
  onStartSession,
  onFinishSession,
  noteDrafts,
  noteErrors,
  savingNoteFor,
  onChangeNoteDraft,
  onSaveNote,
}: {
  session: Session;
  /** EXEC-1 (US-EXEC-1-08) — disables Start/Finish while offline; a tap would only fail (no queue, see the epic's non-goal). Defaults false so existing callers/tests don't need to pass it. */
  offline?: boolean;
  pending: boolean;
  /**
   * EXEC-1 (US-EXEC-1-04) — CONTROLLED, not local state. `PerformToday`
   * swaps this component out for `StepScreen` and back on every step
   * open/close (a different component in the same tree position, so
   * React unmounts and remounts this one) — local `useState` here was
   * tried first and silently lost the tab on every "back" tap. The
   * caller owns it and resets it only when a genuinely different job
   * is opened from Today.
   */
  activeTab: JobTab;
  onChangeTab: (tab: JobTab) => void;
  onBack: () => void;
  onOpenStep: (workTaskId: number) => void;
  onStartSession: () => void;
  onFinishSession: () => void;
  /** EXEC-1 (US-EXEC-1-05) — same per-work_task-id dicts `PerformToday` already keeps for the Step screen's note box; the Notes tab reuses them, keyed by whichever step the performer picks to leave a note on. */
  noteDrafts: Record<number, string>;
  noteErrors: Record<number, string | null>;
  savingNoteFor: number | null;
  onChangeNoteDraft: (workTaskId: number, text: string) => void;
  onSaveNote: (workTaskId: number) => void;
}) {
  const next = nextSubStepToWork(session);
  const canFinish = canFinishSession(session);
  const notStarted = session.status === 'not_started';
  const progress = jobProgress(session);
  const allSteps = session.items.flatMap((item) => item.subSteps);
  const notes = jobNotes(session);
  // Defaults to the current/next step (design prompt); falls back to the
  // job's first step if every step is already done/skipped.
  const [noteStepId, setNoteStepId] = useState<number | null>(null);
  const activeNoteStepId = noteStepId ?? next?.workTaskId ?? allSteps[0]?.workTaskId ?? null;

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

  // EXEC-1 (US-EXEC-1-06) — the Details tab's quantity lines, fetched
  // ONLY when that tab is actually opened (US-03's decision: reuse
  // `GET work-item/{id}/lines` on open, don't grow `perform/today`).
  // `linesLoadToken` lets "Try again" re-run the same effect without a
  // separate imperative fetch function to keep in sync with it.
  const [lines, setLines] = useState<WorkItemLine[] | null>(null);
  const [linesError, setLinesError] = useState<string | null>(null);
  const [linesLoading, setLinesLoading] = useState(false);
  const [linesLoadToken, setLinesLoadToken] = useState(0);
  useEffect(() => {
    if (activeTab !== 'details') return;
    setLinesLoading(true);
    setLinesError(null);
    let cancelled = false;
    void getWorkItemLines(session.workItemId)
      .then((result) => {
        if (!cancelled) setLines(result.lines);
      })
      .catch(() => {
        if (!cancelled) setLinesError("Couldn't load quantities. Check connection.");
      })
      .finally(() => {
        if (!cancelled) setLinesLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [activeTab, session.workItemId, linesLoadToken]);

  return (
    <div className="min-h-screen bg-zinc-50 pb-40">
      <div className="sticky top-0 z-10 bg-white border-b border-zinc-200">
        <header className="px-3 py-3 flex items-start gap-2">
          <button
            type="button"
            onClick={onBack}
            aria-label="Back to today"
            className="w-11 h-11 -ml-1 shrink-0 flex items-center justify-center text-zinc-700"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div className="min-w-0 flex-1 pt-1">
            <div className="flex items-center gap-2">
              <h1 className="text-base font-semibold text-zinc-900 truncate">{session.title}</h1>
              <StatusPill status={session.status} size="sm" className="shrink-0" />
            </div>
            <p className="text-xs text-zinc-500 truncate">
              {['#' + session.workItemId, session.flowTitle, session.planName].filter(Boolean).join(' · ')}
            </p>
          </div>
        </header>

        {/* Tabs (US-EXEC-1-04): Overview · Steps · Notes · Details. */}
        <div className="flex px-3" role="tablist" aria-label="Job navigation tabs">
          {(['overview', 'steps', 'notes', 'details'] as JobTab[]).map((tab) => (
            <button
              key={tab}
              type="button"
              role="tab"
              onClick={() => onChangeTab(tab)}
              aria-selected={activeTab === tab}
              className={`min-h-[44px] flex-1 border-b-2 px-2 text-sm font-medium ${
                activeTab === tab ? 'border-zinc-900 text-zinc-900' : 'border-transparent text-zinc-500'
              }`}
            >
              {TAB_LABELS[tab]}
            </button>
          ))}
        </div>
      </div>

      <main className="px-4 py-4">
        {/* EXC-2 (US-EXC-2-03) — this job came from a send; follow it back read-only. Shown on every tab: it's provenance, not tab-specific content. */}
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

        {activeTab === 'overview' && (
          <div className="space-y-4">
            <div className="rounded-xl border border-zinc-200 bg-white p-4">
              <ProgressRing progress={progress} />
            </div>
            {next ? (
              <button
                type="button"
                onClick={() => onOpenStep(next.workTaskId)}
                className="flex min-h-[44px] w-full items-center justify-between gap-3 rounded-xl bg-zinc-900 px-4 py-3 text-left text-white"
              >
                <span className="min-w-0 truncate text-sm font-medium">Continue: {nextUpLabel(next)}</span>
                <ChevronRight className="h-4 w-4 shrink-0" />
              </button>
            ) : (
              progress.totalCount > 0 && (
                <p className="rounded-xl border border-zinc-200 bg-white p-4 text-center text-sm text-zinc-500">
                  Every step is done or skipped.
                </p>
              )
            )}

            {/* EXEC-1 (US-EXEC-1-05) — latest 2 notes + "See all". */}
            {notes.length > 0 && (
              <div className="rounded-xl border border-zinc-200 bg-white p-4">
                <div className="mb-2 flex items-center justify-between">
                  <p className="text-sm font-semibold text-zinc-900">Notes</p>
                  <button type="button" onClick={() => onChangeTab('notes')} className="min-h-[44px] text-xs font-medium text-zinc-500">
                    See all ({notes.length})
                  </button>
                </div>
                <ul className="space-y-2">
                  {notes.slice(0, 2).map((n, i) => (
                    <li key={i} className="text-sm text-zinc-700">
                      <p>{n.note}</p>
                      <p className="mt-0.5 text-xs text-zinc-400">
                        {[n.stepLabel, n.author, formatNoteTime(n.occurredAt)].filter(Boolean).join(' · ')}
                      </p>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}

        {activeTab === 'notes' && (
          <div className="space-y-4">
            {/* EXEC-1 (US-EXEC-1-05) — add a note on a chosen step; defaults to current/next. */}
            {activeNoteStepId != null && (
              <div className="rounded-xl border border-zinc-200 bg-white p-3">
                <label className="mb-1 block text-xs font-medium text-zinc-500" htmlFor="note-step-picker">
                  Add a note on
                </label>
                <select
                  id="note-step-picker"
                  value={activeNoteStepId}
                  onChange={(e) => setNoteStepId(Number(e.target.value))}
                  className="mb-2 min-h-[44px] w-full rounded-lg border border-zinc-300 bg-white px-2 text-sm text-zinc-900"
                >
                  {allSteps.map((s) => (
                    <option key={s.workTaskId} value={s.workTaskId}>
                      {s.stageLabel || s.stageKey}
                    </option>
                  ))}
                </select>
                <textarea
                  value={noteDrafts[activeNoteStepId] ?? ''}
                  onChange={(e) => onChangeNoteDraft(activeNoteStepId, e.target.value)}
                  disabled={savingNoteFor === activeNoteStepId}
                  placeholder="Add a note…"
                  rows={3}
                  className="w-full rounded-lg border border-zinc-300 p-2 text-base text-zinc-900 disabled:opacity-50"
                />
                {noteErrors[activeNoteStepId] && <p className="mt-1 text-xs text-red-600">{noteErrors[activeNoteStepId]}</p>}
                <button
                  type="button"
                  onClick={() => onSaveNote(activeNoteStepId)}
                  disabled={savingNoteFor === activeNoteStepId}
                  className="mt-2 min-h-[44px] rounded-lg bg-zinc-900 px-4 text-sm font-medium text-white disabled:opacity-50"
                >
                  {savingNoteFor === activeNoteStepId ? 'Saving…' : 'Save note'}
                </button>
              </div>
            )}

            {notes.length === 0 ? (
              <p className="mt-8 text-center text-sm text-zinc-400">No notes yet.</p>
            ) : (
              <ul className="space-y-3">
                {notes.map((n, i) => (
                  <li key={i} className="rounded-xl border border-zinc-200 bg-white p-3">
                    <p className="text-sm text-zinc-900">{n.note}</p>
                    <p className="mt-1 text-xs text-zinc-400">
                      {n.stepLabel} · {[n.author, formatNoteTime(n.occurredAt)].filter(Boolean).join(' · ')}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}

        {activeTab === 'details' && (
          <div className="space-y-4">
            {/* EXEC-1 (US-EXEC-1-06) — each fact hides cleanly when missing: no row at all, never "undefined" or "0 units". */}
            <dl className="divide-y divide-zinc-100 rounded-xl border border-zinc-200 bg-white px-4">
              <div className="flex items-center justify-between py-3">
                <dt className="text-sm text-zinc-500">Job number</dt>
                <dd className="text-sm font-medium text-zinc-900">#{session.workItemId}</dd>
              </div>
              {session.flowTitle && (
                <div className="flex items-center justify-between py-3">
                  <dt className="text-sm text-zinc-500">Process / Flow</dt>
                  <dd className="text-right text-sm font-medium text-zinc-900">
                    {session.flowTitle}
                    {session.versionNo != null && <span className="text-zinc-400"> · v{session.versionNo}</span>}
                  </dd>
                </div>
              )}
              {/* TW-1 (US-TW-1-05) — read-only; no window, no row. */}
              {session.timeWindow && (
                <div className="flex items-center justify-between py-3">
                  <dt className="text-sm text-zinc-500">Time window</dt>
                  <dd className="text-sm font-medium text-zinc-900">{formatWindow(session.timeWindow)}</dd>
                </div>
              )}
              {session.planName && (
                <div className="flex items-center justify-between py-3">
                  <dt className="text-sm text-zinc-500">Plan</dt>
                  <dd className="text-sm font-medium text-zinc-900">{session.planName}</dd>
                </div>
              )}
              {allSteps.length > 0 && (
                <div className="flex items-center justify-between py-3">
                  <dt className="text-sm text-zinc-500">Scheduled window</dt>
                  <dd className="text-sm font-medium text-zinc-900 tabular-nums">
                    {formatWindowTime(session.plannedStartMinutes)}–{formatWindowTime(session.plannedStartMinutes + session.totalScheduledMinutes)}
                  </dd>
                </div>
              )}
            </dl>

            <div>
              <p className="mb-2 text-sm font-semibold text-zinc-900">Quantity / Scope</p>
              {linesLoading && <p className="text-sm text-zinc-400">Loading…</p>}
              {!linesLoading && linesError && (
                <div className="rounded-xl border border-zinc-200 bg-white p-3">
                  <p className="text-sm text-red-600">{linesError}</p>
                  <button
                    type="button"
                    onClick={() => setLinesLoadToken((t) => t + 1)}
                    className="mt-2 min-h-[44px] rounded-lg border border-zinc-300 bg-white px-3 text-sm font-medium text-zinc-700"
                  >
                    Try again
                  </button>
                </div>
              )}
              {!linesLoading && !linesError && lines && lines.length === 0 && (
                <p className="text-sm text-zinc-400">No lines on this job.</p>
              )}
              {!linesLoading && !linesError && lines && lines.length > 0 && (
                <ul className="divide-y divide-zinc-100 rounded-xl border border-zinc-200 bg-white px-4">
                  {lines.map((line) => (
                    <li key={line.id} className="flex items-center justify-between py-3 text-sm">
                      <span className="text-zinc-900">{line.item_label || line.item_key}</span>
                      <span className="font-medium text-zinc-900 tabular-nums">
                        {line.quantity} {line.unit}
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
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
        {activeTab === 'steps' && (
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
                        {sub && completedLine(sub) && <p className="text-xs text-zinc-500">{completedLine(sub)}</p>}
                      </div>
                      <StatusPill status={item.status} size="sm" />
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
                  <StatusPill status={item.status} size="sm" />
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
                              {completedLine(sub) && <p className="text-xs text-zinc-500">{completedLine(sub)}</p>}
                            </div>
                          </div>
                          <StatusPill status={sub.status} size="sm" labelOverride={isNext ? 'Next' : undefined} />
                        </button>
                      </li>
                    );
                  })}
                </ol>
              </li>
            );
          })}
        </ul>
        )}
      </main>

      {/* Primary action in the bottom third (US-APP-2-08). `bottom-14`,
          not `bottom-0` (EXEC-1 US-EXEC-1-09): the bottom tab bar is
          now the outermost fixed element, 56px tall, and sits below this. */}
      <div className="fixed bottom-14 inset-x-0 bg-white border-t border-zinc-200 p-4">
        {notStarted ? (
          <button
            type="button"
            onClick={onStartSession}
            disabled={pending || offline}
            className="w-full min-h-[44px] rounded-lg bg-zinc-900 px-4 py-3 text-base font-medium text-white disabled:opacity-50"
          >
            Start job
          </button>
        ) : (
          <>
            <button
              type="button"
              onClick={onFinishSession}
              disabled={!canFinish || offline}
              className="w-full min-h-[44px] rounded-lg bg-zinc-900 px-4 py-3 text-base font-medium text-white disabled:opacity-40"
            >
              Finish job
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
