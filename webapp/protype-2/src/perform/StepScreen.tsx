// APP-2 (US-APP-2-05, -06, -07) — Full-screen view of one step: status,
// instructions, notes, and the only way a status ever changes — a
// button, never a dropdown (same rule APP-1 already enforces).
import {ChevronLeft} from 'lucide-react';
import {availableActions, type PerformerAction, type PerformerSubStep, type TaskStatus} from './performerView';
import ExceptionSendPanel from '../exceptions/ExceptionSendPanel';

const REASON_LABELS: Record<string, string> = {
  waiting_on_someone: 'Waiting on someone',
  missing_information: 'Missing information',
  something_went_wrong: 'Something went wrong',
  other: 'Other',
};
const REASON_CODES = Object.keys(REASON_LABELS);

// Epic table (US-APP-2-07): which of availableActions' results is the
// PRIMARY button for that status — styled filled/prominent. Every
// other action availableActions returns still shows (that function's
// own output is the source of truth, pinned by UT-APP-1-01..04 and
// shared with the backend's transition table) — this only controls
// which one looks like the main action.
const PRIMARY_ACTION: Record<TaskStatus, PerformerAction | null> = {
  not_started: 'start',
  in_progress: 'done',
  blocked: 'unblock',
  done: null,
  skipped: null,
};

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
  onBack,
  onTapAction,
  onPickReason,
  onSkipWithoutReason,
  onCancelReason,
  onChangeNoteDraft,
  onSaveNote,
  workItemId,
  onExceptionSent,
}: {
  sub: PerformerSubStep;
  expectedMinutes: number;
  pending: boolean;
  errorMessage: string | null;
  reasonPickerFor: 'blocked' | 'skip' | null;
  noteDraft: string;
  noteSaving: boolean;
  noteError: string | null;
  onBack: () => void;
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
}) {
  const actions = availableActions(sub.status);
  const primary = PRIMARY_ACTION[sub.status];
  const now = Date.now();

  return (
    <div className="min-h-screen bg-zinc-50 pb-40">
      <header className="sticky top-0 bg-white border-b border-zinc-200 px-3 py-3 flex items-center gap-2">
        <button
          type="button"
          onClick={onBack}
          aria-label="Back to session"
          className="w-11 h-11 -ml-1 shrink-0 flex items-center justify-center text-zinc-700"
        >
          <ChevronLeft className="w-5 h-5" />
        </button>
        <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_COLORS[sub.status]}`}>{STATUS_LABELS[sub.status]}</span>
      </header>

      <main className="px-4 py-4 space-y-5">
        {sub.stageLabel && <p className="text-xs font-medium text-zinc-500">{sub.stageLabel}</p>}

        {sub.task && <p className="text-lg text-zinc-900 leading-snug">{sub.task}</p>}

        {sub.doneWhen && (
          <p className="text-base text-zinc-600">
            <span className="font-medium text-zinc-700">Done when:</span> {sub.doneWhen}
          </p>
        )}

        <div className="flex gap-4 text-sm text-zinc-500">
          <span>Expected: {formatMinutes(expectedMinutes)}</span>
          {Boolean(sub.startedAt) && (
            <span>Elapsed: {formatElapsed(sub.startedAt!, sub.completedAt ?? now)}</span>
          )}
        </div>

        {errorMessage && <p className="text-sm text-red-600">{errorMessage}</p>}

        {/* EXC-1 (US-EXC-1-06) — shown only when this stage links somewhere. */}
        {workItemId != null && <ExceptionSendPanel workItemId={workItemId} workTaskId={sub.workTaskId} variant="performer" onSent={onExceptionSent} />}

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

      {/* Action buttons live in the bottom third (US-APP-2-08) */}
      <div className="fixed bottom-0 inset-x-0 bg-white border-t border-zinc-200 p-4">
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
                  disabled={pending}
                  className="min-h-[44px] rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-700 disabled:opacity-50"
                >
                  {REASON_LABELS[code]}
                </button>
              ))}
            </div>
            <div className="mt-2 flex items-center justify-between">
              {reasonPickerFor === 'skip' && (
                <button type="button" onClick={onSkipWithoutReason} disabled={pending} className="min-h-[44px] text-sm text-zinc-600 disabled:opacity-50">
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
                disabled={pending}
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
    </div>
  );
}
