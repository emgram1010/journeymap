// QUE-1 (US-QUE-1-06) — the friendly warning before work comes off a
// day. The founder's own words: "provide a friendly warning pop-up to
// inform the user that they're about to unschedule a job and if they
// really want to move forward with it or cancel it."
//
// Scoped to JOB SLOTS only (US-QUE-1-05/boardModel's
// `classifyUnscheduleTarget`): a plain task's existing behaviour was
// never silent about what it does, so it keeps its own path (Q-4).
//
// The server still has the last word (E-SCHED-006/007) — this dialog
// only gets the planner's intent; PlannerApp re-checks via the same
// `unscheduleWorkTask` call every other path already used, and shows
// its refusal sentence if the day turned out to be published or
// recorded against since the menu opened.
import {useEffect} from 'react';
import {AlertTriangle} from 'lucide-react';

export interface UnscheduleConfirmTarget {
  workTaskId: number;
  jobTitle: string;
  dayLabel: string;
}

interface UnscheduleConfirmModalProps {
  target: UnscheduleConfirmTarget | null;
  isWorking: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}

export function UnscheduleConfirmModal({target, isWorking, onCancel, onConfirm}: UnscheduleConfirmModalProps) {
  // Escape cancels, like every other dismissable thing on this board. An
  // `alertdialog` that can only be left with the mouse is the gap the Opus
  // review (2026-10-31) found; it also stays shut while the request is in
  // flight, same rule as the two buttons.
  useEffect(() => {
    if (!target) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !isWorking) onCancel();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [target, isWorking, onCancel]);

  if (!target) return null;
  return (
    <div
      id="unschedule-confirm-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4"
      /* Not while the server is answering: both buttons are disabled for
         that window, so letting a backdrop click through would close the
         dialog out from under an in-flight release and hide its refusal
         sentence (E-SCHED-006/007). */
      onClick={() => {
        if (!isWorking) onCancel();
      }}
    >
      <div
        id="unschedule-confirm-modal"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="unschedule-confirm-title"
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-sm p-4 flex flex-col gap-3"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start gap-2.5">
          <AlertTriangle className="w-5 h-5 text-amber-600 shrink-0 mt-0.5" />
          <div className="min-w-0">
            <p id="unschedule-confirm-title" className="text-sm font-semibold text-neutral-900">
              Take this off the day?
            </p>
            <p className="mt-1 text-xs text-neutral-600">
              "{target.jobTitle}" will come off {target.dayLabel} and go back to Unscheduled. The work itself is
              unchanged — nothing is deleted.
            </p>
          </div>
        </div>
        <div className="flex items-center justify-end gap-2 pt-1">
          <button
            type="button"
            id="unschedule-confirm-cancel"
            onClick={onCancel}
            disabled={isWorking}
            className="px-3 py-1.5 text-xs text-neutral-600 hover:text-neutral-900 rounded disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            id="unschedule-confirm-confirm"
            onClick={onConfirm}
            disabled={isWorking}
            className="px-3.5 py-1.5 bg-neutral-900 text-white text-xs font-semibold rounded hover:bg-neutral-800 disabled:opacity-60"
          >
            {isWorking ? 'Unscheduling…' : 'Unschedule'}
          </button>
        </div>
      </div>
    </div>
  );
}
