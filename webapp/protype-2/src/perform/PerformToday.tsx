// APP-1 (US-APP-1-03, -04) — The performer's screen: today's items, in
// order, with one-tap actions. Phone-width first; large tap targets.
//
// This component is a thin shell. Every decision about WHAT to show
// and WHAT buttons are available lives in `performerView.ts`'s pure
// functions; this file only wires fetch results and taps to them.
import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {fetchToday, recordEvent, PerformRequestError, type PerformEventType} from './performApi';
import {
  availableActions,
  toPerformerItems,
  newClientEventId,
  optimisticReducer,
  mapActionError,
  FALLBACK_STATUS,
  type PerformerSnapshot,
  type StatusMap,
  type TaskStatus,
  type PerformerAction,
  type PerformerSubStep,
} from './performerView';
import {logEvent} from '../ops/logEvent';

const REASON_LABELS: Record<string, string> = {
  waiting_on_someone: 'Waiting on someone',
  missing_information: 'Missing information',
  something_went_wrong: 'Something went wrong',
  other: 'Other',
};
const REASON_CODES = Object.keys(REASON_LABELS);

const ACTION_LABELS: Record<PerformerAction, string> = {
  start: 'Start',
  done: 'Done',
  blocked: 'Blocked',
  skip: 'Skip',
  unblock: 'Unblock',
  reopen: 'Reopen',
};

const EVENT_TYPE_FOR_ACTION: Record<PerformerAction, PerformEventType> = {
  start: 'started',
  done: 'completed',
  blocked: 'blocked',
  skip: 'skipped',
  unblock: 'unblocked',
  reopen: 'reopened',
};

/** The optimistic guess applied the instant a tap is sent — replaced by the server's own answer on success, or discarded on failure. */
const OPTIMISTIC_STATUS: Record<PerformerAction, TaskStatus> = {
  start: 'in_progress',
  done: 'done',
  blocked: 'blocked',
  skip: 'skipped',
  unblock: 'in_progress',
  reopen: 'in_progress',
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

function isOffline(): boolean {
  return typeof navigator !== 'undefined' && navigator.onLine === false;
}

type LoadPhase = 'loading' | 'ready' | 'error';

export default function PerformToday() {
  const [phase, setPhase] = useState<LoadPhase>('loading');
  const [snapshot, setSnapshot] = useState<PerformerSnapshot | null>(null);
  const [statuses, setStatuses] = useState<StatusMap>({});
  const [loadError, setLoadError] = useState<string | null>(null);
  const [pendingWorkTaskId, setPendingWorkTaskId] = useState<number | null>(null);
  const [actionError, setActionError] = useState<{workTaskId: number; message: string} | null>(null);
  const [reasonPickerFor, setReasonPickerFor] = useState<number | null>(null);

  const load = useCallback(async () => {
    setPhase('loading');
    setLoadError(null);
    const startedAt = Date.now();
    try {
      const data = await fetchToday();
      setSnapshot(data.snapshot);
      setStatuses(data.statuses);
      setPhase('ready');
      void logEvent({
        feature: 'APP-1',
        step: 'load_today',
        outcome: 'success',
        durationMs: Date.now() - startedAt,
        metadata: {item_count: data.snapshot.items.length},
      });
    } catch (err) {
      const perr = err instanceof PerformRequestError ? err : null;
      const info = mapActionError({status: perr?.status, offline: perr?.offline ?? isOffline()});
      setPhase('error');
      setLoadError(info.message);
      void logEvent({
        feature: 'APP-1',
        step: 'load_today',
        outcome: 'failure',
        errorCode: info.code,
        message: info.message,
        correlationId: perr?.reference ?? null,
      });
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const items = useMemo(() => (snapshot ? toPerformerItems(snapshot, statuses) : []), [snapshot, statuses]);

  const act = useCallback(
    async (workTaskId: number, action: PerformerAction, reasonCode?: string) => {
      if (pendingWorkTaskId !== null) return; // one in-flight tap at a time
      setActionError(null);

      if (isOffline()) {
        const info = mapActionError({offline: true});
        setActionError({workTaskId, message: info.message});
        void logEvent({
          feature: 'APP-1',
          step: 'action_tap',
          outcome: 'failure',
          errorCode: info.code,
          message: info.message,
          entityType: 'work_task',
          entityId: workTaskId,
        });
        return; // non-goal: no offline queue — see the epic's own E-APP-001 rule
      }

      const prior = statuses[workTaskId] ?? null;
      const clientEventId = newClientEventId();
      setStatuses((s) => optimisticReducer(s, {type: 'apply', workTaskId, nextStatus: OPTIMISTIC_STATUS[action], at: Date.now()}));
      setPendingWorkTaskId(workTaskId);

      try {
        const result = await recordEvent({
          workTaskId,
          eventType: EVENT_TYPE_FOR_ACTION[action],
          clientEventId,
          reasonCode,
        });
        setStatuses((s) =>
          optimisticReducer(s, {
            type: 'confirm',
            workTaskId,
            entry: {
              ...(s[workTaskId] ?? prior ?? {work_task_id: workTaskId, ...FALLBACK_STATUS}),
              status: result.to,
              started_at: result.work_task.started_at,
              completed_at: result.work_task.completed_at,
            },
          }),
        );
        setReasonPickerFor(null);
        void logEvent({
          feature: 'APP-1',
          step: 'action_tap',
          outcome: 'success',
          entityType: 'work_task',
          entityId: workTaskId,
          metadata: {event_type: EVENT_TYPE_FOR_ACTION[action], to: result.to, duplicate: result.duplicate},
        });
      } catch (err) {
        if (prior) setStatuses((s) => optimisticReducer(s, {type: 'revert', workTaskId, previous: prior}));
        const perr = err instanceof PerformRequestError ? err : null;
        const info = mapActionError({status: perr?.status, serverMessage: perr?.message ?? null, offline: perr?.offline});
        setActionError({workTaskId, message: info.message});
        void logEvent({
          feature: 'APP-1',
          step: 'action_tap',
          outcome: 'failure',
          errorCode: info.code,
          message: info.message,
          entityType: 'work_task',
          entityId: workTaskId,
          correlationId: perr?.reference ?? null,
        });
      } finally {
        setPendingWorkTaskId(null);
      }
    },
    [pendingWorkTaskId, statuses],
  );

  const onTapAction = useCallback(
    (workTaskId: number, action: PerformerAction) => {
      if (action === 'blocked') {
        setReasonPickerFor(workTaskId);
        return;
      }
      void act(workTaskId, action);
    },
    [act],
  );

  if (phase === 'loading') {
    return (
      <div className="min-h-screen bg-zinc-50 flex items-center justify-center">
        <div className="w-6 h-6 border-2 border-zinc-300 border-t-zinc-700 rounded-full animate-spin" />
      </div>
    );
  }

  if (phase === 'error') {
    return (
      <div className="min-h-screen bg-zinc-50 flex items-center justify-center p-6">
        <div className="max-w-sm text-center">
          <p className="text-sm text-zinc-700">{loadError}</p>
          <button type="button" onClick={() => void load()} className="mt-4 rounded-lg bg-zinc-900 px-4 py-2 text-sm text-white">
            Try again
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-zinc-50">
      <header className="sticky top-0 bg-white border-b border-zinc-200 px-4 py-3">
        <h1 className="text-base font-semibold text-zinc-900">Today</h1>
        <p className="text-xs text-zinc-400">{snapshot?.date}</p>
      </header>

      <main className="px-4 py-4 pb-24">
        {items.length === 0 ? (
          <p className="text-sm text-zinc-500 text-center mt-16">Nothing is scheduled for you today.</p>
        ) : (
          <ul className="space-y-3">
            {items.map((item) => (
              <li key={item.itemRef} className="rounded-xl border border-zinc-200 bg-white p-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="text-xs text-zinc-400">{item.plannedStartLabel}</p>
                    <p className="text-sm font-medium text-zinc-900">{item.title || item.subSteps[0]?.stageLabel || item.itemRef}</p>
                  </div>
                  <span className={`shrink-0 rounded-full px-2 py-1 text-[11px] font-medium ${STATUS_COLORS[item.status]}`}>
                    {STATUS_LABELS[item.status]}
                  </span>
                </div>

                <ul className="mt-3 space-y-3">
                  {item.subSteps.map((sub) => (
                    <SubStepRow
                      key={sub.workTaskId}
                      sub={sub}
                      nested={item.subSteps.length > 1}
                      pending={pendingWorkTaskId === sub.workTaskId}
                      errorMessage={actionError?.workTaskId === sub.workTaskId ? actionError.message : null}
                      showReasonPicker={reasonPickerFor === sub.workTaskId}
                      onTapAction={(action) => onTapAction(sub.workTaskId, action)}
                      onPickReason={(reasonCode) => void act(sub.workTaskId, 'blocked', reasonCode)}
                      onCancelReason={() => setReasonPickerFor(null)}
                    />
                  ))}
                </ul>
              </li>
            ))}
          </ul>
        )}
      </main>
    </div>
  );
}

function SubStepRow({
  sub,
  nested,
  pending,
  errorMessage,
  showReasonPicker,
  onTapAction,
  onPickReason,
  onCancelReason,
}: {
  sub: PerformerSubStep;
  nested: boolean;
  pending: boolean;
  errorMessage: string | null;
  showReasonPicker: boolean;
  onTapAction: (action: PerformerAction) => void;
  onPickReason: (reasonCode: string) => void;
  onCancelReason: () => void;
}) {
  const actions = availableActions(sub.status);

  return (
    <li className={nested ? 'border-l-2 border-zinc-100 pl-3' : ''}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          {nested && <p className="text-xs font-medium text-zinc-500">{sub.stageLabel ?? sub.stageKey}</p>}
          {sub.task && <p className="text-sm text-zinc-700">{sub.task}</p>}
          {sub.doneWhen && <p className="mt-1 text-xs text-zinc-400">Done when: {sub.doneWhen}</p>}
        </div>
        {nested && (
          <span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-medium ${STATUS_COLORS[sub.status]}`}>{STATUS_LABELS[sub.status]}</span>
        )}
      </div>

      {errorMessage && <p className="mt-2 text-xs text-red-600">{errorMessage}</p>}

      {showReasonPicker ? (
        <div className="mt-2 rounded-lg bg-zinc-50 p-2">
          <p className="mb-2 text-xs text-zinc-500">Why is this blocked?</p>
          <div className="grid grid-cols-2 gap-2">
            {REASON_CODES.map((code) => (
              <button
                key={code}
                type="button"
                onClick={() => onPickReason(code)}
                disabled={pending}
                className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-xs text-zinc-700 disabled:opacity-50"
              >
                {REASON_LABELS[code]}
              </button>
            ))}
          </div>
          <button type="button" onClick={onCancelReason} className="mt-2 text-xs text-zinc-400">
            Cancel
          </button>
        </div>
      ) : (
        <div className="mt-2 flex flex-wrap gap-2">
          {actions.map((action) => (
            <button
              key={action}
              type="button"
              onClick={() => onTapAction(action)}
              disabled={pending}
              className="min-h-[44px] rounded-lg bg-zinc-900 px-4 text-sm font-medium text-white disabled:opacity-50"
            >
              {ACTION_LABELS[action]}
            </button>
          ))}
        </div>
      )}
    </li>
  );
}
