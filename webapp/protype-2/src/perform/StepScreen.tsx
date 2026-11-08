// APP-2 (US-APP-2-05, -06, -07) — Full-screen view of one step: status,
// instructions, notes, and the only way a status ever changes — a
// button, never a dropdown (same rule APP-1 already enforces).
//
// EXEC-1 (US-EXEC-1-07) — redesigned to the prototype's step screen:
// "Step N of M", a highlighted Done-when box, an Elapsed row that
// warns once a step runs over its expected minutes, and a "Next step"
// prompt once the step reaches done/skipped. `primaryAction` and
// `isOverExpected` moved to `performerView.ts` as tested pure
// functions (UT-EXEC-1-07a..e) — this file only renders their output.
import {Clock, ChevronLeft, ChevronRight} from 'lucide-react';
import {useEffect, useState} from 'react';
import {availableActions, primaryAction, isOverExpected, elapsedClock, type PerformerAction, type PerformerSubStep, type TimeWindow} from './performerView';
import ExceptionSendPanel from '../exceptions/ExceptionSendPanel';
import JobPeekSheet from '../exceptions/JobPeekSheet';
import type {JobParentLink} from '../planner/plannerApi';
import {formatWindow} from '../planner/timeWindowModel';
import StatusPill from './ui/StatusPill';

// The 4 real reason codes — `activity_log.reason_code`'s enum
// (static/tables/127_activity_log.xs). Never the prototype's longer,
// made-up list (CLAUDE.md's standing rule for this epic).
const REASON_LABELS: Record<string, string> = {
  waiting_on_someone: 'Waiting on someone',
  missing_information: 'Missing information',
  something_went_wrong: 'Something went wrong',
  other: 'Other',
};
const REASON_CODES = Object.keys(REASON_LABELS);

// "Resume", not "Unblock" — the label the epic's own button table uses
// for a blocked step's primary action. The action key stays `unblock`
// (EVENT_TYPE_FOR_ACTION/OPTIMISTIC_STATUS already key off it).
const ACTION_LABELS: Record<PerformerAction, string> = {
  start: 'Start',
  done: 'Done',
  blocked: 'Blocked',
  skip: 'Skip',
  unblock: 'Resume',
  reopen: 'Reopen',
};

function formatMinutes(total: number): string {
  if (total < 60) return `${total} min`;
  const hours = Math.floor(total / 60);
  const minutes = total % 60;
  return minutes === 0 ? `${hours} hr` : `${hours} hr ${minutes} min`;
}

function formatElapsed(startedAt: number, endedAt: number): string {
  const minutes = Math.max(0, Math.round((endedAt - startedAt) / 60000));
  return formatMinutes(minutes);
}

function formatNoteTime(occurredAt: number): string {
  return new Date(occurredAt).toLocaleString(undefined, {month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'});
}

export default function StepScreen({
  sub,
  expectedMinutes,
  pending,
  errorMessage,
  reasonPickerFor,
  noteDraft,
  noteSaving,
  noteError,
  offline = false,
  stepPosition,
  continueLabel,
  onBack,
  onContinue,
  onTapAction,
  onPickReason,
  onSkipWithoutReason,
  onCancelReason,
  onChangeNoteDraft,
  onSaveNote,
  workItemId,
  onExceptionSent,
  timeWindow = null,
}: {
  sub: PerformerSubStep;
  expectedMinutes: number;
  pending: boolean;
  errorMessage: string | null;
  reasonPickerFor: 'blocked' | 'skip' | null;
  noteDraft: string;
  noteSaving: boolean;
  noteError: string | null;
  /** EXEC-1 (US-EXEC-1-08) — disables every action button while offline; a tap would only fail (no queue, see the epic's non-goal). Defaults false so existing callers/tests don't need to pass it. */
  offline?: boolean;
  /** EXEC-1 (US-EXEC-1-07) — "Step N of M"; null when this step isn't found in its job's step list (shouldn't happen, same degrade discipline as the rest of APP-2). */
  stepPosition: {index: number; total: number} | null;
  /** The next step to work after this one, or null once nothing's left — drives the post-done "Next step →" / "Back to job" button's label. */
  continueLabel: string | null;
  onBack: () => void;
  /** Opens the next step, or goes back to the job if `continueLabel` is null. */
  onContinue: () => void;
  onTapAction: (action: PerformerAction) => void;
  onPickReason: (reasonCode: string) => void;
  onSkipWithoutReason: () => void;
  onCancelReason: () => void;
  onChangeNoteDraft: (text: string) => void;
  onSaveNote: () => void;
  /** EXC-1 — the step's job; enables "Send to…" when its pinned version links this stage somewhere. */
  workItemId?: number;
  /** EXC-1 — re-fetch the step after a send: "This step is stuck" changes its status on the server. */
  onExceptionSent?: () => void;
  /** TW-1 (US-TW-1-05) — the job's window; read-only, from the session (Q-1). */
  timeWindow?: TimeWindow | null;
}) {
  const actions = availableActions(sub.status);
  const primary = primaryAction(sub.status);
  const isFinished = sub.status === 'done' || sub.status === 'skipped';

  // EXEC-1 (US-EXEC-1-07) — a live-ish Elapsed clock: ticks every 30s so
  // it doesn't visibly freeze on a long step, without re-rendering every
  // second for a number nobody needs that precise. Nothing is sent to
  // the server from this — it only re-reads `sub.startedAt`, same as
  // before; see CLAUDE.md's "never send time to the server" rule.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (sub.status !== 'in_progress') return;
    const id = setInterval(() => setNow(Date.now()), 30_000);
    return () => clearInterval(id);
  }, [sub.status]);

  // `elapsedClock` (performerView.ts) is the ONE place "what to measure
  // against" is decided, shared with the Elapsed text below — see its
  // own comment for the live bug this fixes (EXEC-1 US-EXEC-1-09).
  const over = isOverExpected(sub.startedAt, elapsedClock(sub.completedAt, now), expectedMinutes);

  // EXC-2 (US-EXC-2-03) — "Came from", fed by ExceptionSendPanel's own
  // fetch (onLinksLoaded) so this never issues a second getWorkItemLinks
  // call for the same screen.
  const [parentLink, setParentLink] = useState<JobParentLink | null>(null);
  const [peekId, setPeekId] = useState<number | null>(null);

  return (
    <div className="min-h-screen bg-zinc-50 pb-52">
      <header className="sticky top-0 bg-white border-b border-zinc-200 px-3 py-3 flex items-center gap-2">
        <button
          type="button"
          onClick={onBack}
          aria-label="Back to job"
          className="w-11 h-11 -ml-1 shrink-0 flex items-center justify-center text-zinc-700"
        >
          <ChevronLeft className="w-5 h-5" />
        </button>
        {stepPosition && (
          <span className="text-xs font-medium text-zinc-500">
            Step {stepPosition.index} of {stepPosition.total}
          </span>
        )}
        <StatusPill status={sub.status} className="ml-auto" />
      </header>

      <main className="px-4 py-4 space-y-5">
        {/* EXC-2 (US-EXC-2-03) — this job came from a send; follow it back read-only. */}
        {parentLink && (
          <button
            type="button"
            data-testid="step-came-from-chip"
            aria-label={`See where this job came from: #${parentLink.work_item_id}`}
            onClick={() => setPeekId(parentLink.work_item_id)}
            className="flex min-h-[44px] w-full items-center gap-2 rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2 text-left"
          >
            <div className="min-w-0 flex-1 text-sm text-zinc-700">
              Came from <span className="font-medium">#{parentLink.work_item_id} · {parentLink.stage_label || parentLink.stage_key}</span>
            </div>
            <ChevronRight className="h-4 w-4 flex-shrink-0 text-zinc-400" />
          </button>
        )}

        {sub.stageLabel && <p className="text-xs font-medium text-zinc-500">{sub.stageLabel}</p>}

        {/* TW-1 (US-TW-1-05) — read-only; no window, no clutter. */}
        {timeWindow && (
          <p className="flex items-center gap-1.5 text-xs text-zinc-500">
            <Clock className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
            Time window {formatWindow(timeWindow)}
          </p>
        )}

        {sub.task && <p className="text-xl text-zinc-900 leading-snug">{sub.task}</p>}

        {sub.doneWhen && (
          <div className="rounded-xl border border-zinc-200 bg-zinc-50 p-3">
            <p className="text-sm text-zinc-700">
              <span className="font-medium text-zinc-900">Done when:</span> {sub.doneWhen}
            </p>
          </div>
        )}

        <div className="flex gap-4 text-sm">
          <span className="text-zinc-500">Expected: {formatMinutes(expectedMinutes)}</span>
          {Boolean(sub.startedAt) && (
            <span className={over ? 'font-medium text-amber-600' : 'text-zinc-500'}>
              Elapsed: {formatElapsed(sub.startedAt!, elapsedClock(sub.completedAt, now))}
              {over && ' · over'}
            </span>
          )}
        </div>

        {isFinished && (
          <button
            type="button"
            onClick={onContinue}
            className="flex min-h-[44px] w-full items-center justify-between gap-3 rounded-xl bg-zinc-900 px-4 py-3 text-left text-white"
          >
            <span className="min-w-0 truncate text-sm font-medium">
              {continueLabel ? `Next step: ${continueLabel}` : 'Back to job'}
            </span>
            <ChevronRight className="h-4 w-4 shrink-0" />
          </button>
        )}

        {errorMessage && <p className="text-sm text-red-600">{errorMessage}</p>}

        {/* EXC-1 (US-EXC-1-06) — shown only when this stage links somewhere. */}
        {workItemId != null && (
          <ExceptionSendPanel
            workItemId={workItemId}
            workTaskId={sub.workTaskId}
            variant="performer"
            onSent={onExceptionSent}
            onLinksLoaded={setParentLink}
          />
        )}

        {/* US-APP-2-06 — notes */}
        <div className="rounded-xl border border-zinc-200 bg-white p-3">
          <p className="mb-2 text-sm font-medium text-zinc-700">Notes</p>
          {sub.notes.length > 0 && (
            <ul className="mb-3 space-y-2">
              {sub.notes.map((n, i) => (
                <li key={i} className="text-sm text-zinc-700 border-b border-zinc-100 pb-2 last:border-0 last:pb-0">
                  <p>{n.note}</p>
                  <p className="mt-0.5 text-xs text-zinc-400">
                    {[n.author, formatNoteTime(n.occurredAt)].filter(Boolean).join(' · ')}
                  </p>
                </li>
              ))}
            </ul>
          )}
          <textarea
            value={noteDraft}
            onChange={(e) => onChangeNoteDraft(e.target.value)}
            disabled={noteSaving}
            placeholder="Add a note…"
            rows={3}
            className="w-full rounded-lg border border-zinc-300 p-2 text-base text-zinc-900 disabled:opacity-50"
          />
          {noteError && <p className="mt-1 text-xs text-red-600">{noteError}</p>}
          <button
            type="button"
            onClick={onSaveNote}
            disabled={noteSaving}
            className="mt-2 min-h-[44px] rounded-lg bg-zinc-900 px-4 text-sm font-medium text-white disabled:opacity-50"
          >
            {noteSaving ? 'Saving…' : 'Save note'}
          </button>
        </div>
      </main>

      {/* Action buttons live in the bottom third (US-APP-2-08). `bottom-14`,
          not `bottom-0` (EXEC-1 US-EXEC-1-09): sits above the 56px bottom tab bar. */}
      <div className="fixed bottom-14 inset-x-0 bg-white border-t border-zinc-200 p-4">
        {reasonPickerFor ? (
          <div>
            <p className="mb-2 text-sm text-zinc-600">
              {reasonPickerFor === 'blocked' ? 'Why is this blocked?' : 'Why are you skipping this? (optional)'}
            </p>
            <div className="grid grid-cols-2 gap-2">
              {REASON_CODES.map((code) => (
                <button
                  key={code}
                  type="button"
                  onClick={() => onPickReason(code)}
                  disabled={pending || offline}
                  className="min-h-[44px] rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-700 disabled:opacity-50"
                >
                  {REASON_LABELS[code]}
                </button>
              ))}
            </div>
            <div className="mt-2 flex items-center justify-between">
              {reasonPickerFor === 'skip' && (
                <button type="button" onClick={onSkipWithoutReason} disabled={pending || offline} className="min-h-[44px] text-sm text-zinc-600 disabled:opacity-50">
                  Skip without a reason
                </button>
              )}
              <button type="button" onClick={onCancelReason} className="min-h-[44px] text-sm text-zinc-400">
                Cancel
              </button>
            </div>
          </div>
        ) : (
          <div className="flex flex-wrap gap-2">
            {actions.map((action) => (
              <button
                key={action}
                type="button"
                onClick={() => onTapAction(action)}
                disabled={pending || offline}
                className={`min-h-[44px] flex-1 rounded-lg px-4 text-base font-medium disabled:opacity-50 ${
                  action === primary ? 'bg-zinc-900 text-white' : 'border border-zinc-300 bg-white text-zinc-700'
                }`}
              >
                {ACTION_LABELS[action]}
              </button>
            ))}
          </div>
        )}
      </div>

      <JobPeekSheet workItemId={peekId ?? 0} open={peekId != null} onClose={() => setPeekId(null)} onOpenJob={setPeekId} />
    </div>
  );
}
