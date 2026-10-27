// APP-1/APP-2 — The performer's app: Today → Session → Step. A thin
// shell over three screens. Every decision about what's available and
// how it's grouped lives in `performerView.ts`/`sessionModel.ts`'s pure
// functions; this file only wires fetch results, navigation and taps
// to them.
import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {fetchToday, recordEvent, PerformRequestError, type PerformEventType} from './performApi';
import {publishedDays, addDays, diagnoseEmptyDay} from './dayNavigation';
import {
  toPerformerItems,
  newClientEventId,
  optimisticReducer,
  mapActionError,
  FALLBACK_STATUS,
  type PerformerSnapshot,
  type StatusMap,
  type TaskStatus,
  type PerformerAction,
} from './performerView';
import {toSessions} from './sessionModel';
import {logEvent} from '../ops/logEvent';
import TodayScreen from './TodayScreen';
import SessionScreen from './SessionScreen';
import StepScreen from './StepScreen';

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

function isOffline(): boolean {
  return typeof navigator !== 'undefined' && navigator.onLine === false;
}

type LoadPhase = 'loading' | 'ready' | 'error';

type View = {type: 'today'} | {type: 'session'; workItemId: number} | {type: 'step'; workItemId: number; workTaskId: number};

const NOTE_MAX_LENGTH = 1000;

export default function PerformToday() {
  const [phase, setPhase] = useState<LoadPhase>('loading');
  const [snapshot, setSnapshot] = useState<PerformerSnapshot | null>(null);
  const [statuses, setStatuses] = useState<StatusMap>({});
  // GAP-FIX W4 — which day is on screen. `null` means "whatever the
  // server calls today", which is NOT the same as hardcoding today's
  // date here: the server decides, in the performer's own zone (W8),
  // and the device's clock is still never trusted for it.
  const [viewDate, setViewDate] = useState<string | null>(null);
  // GAP-FIX W4/W5 — the facts the empty state needs to say anything
  // useful: the server's today, which days have published work, and
  // whether this login is linked to an agent at all.
  const [serverToday, setServerToday] = useState<string>('');
  const [myDates, setMyDates] = useState<string[]>([]);
  const [agentIds, setAgentIds] = useState<number[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [pendingWorkTaskId, setPendingWorkTaskId] = useState<number | null>(null);
  const [actionError, setActionError] = useState<{workTaskId: number; message: string} | null>(null);
  const [reasonPickerFor, setReasonPickerFor] = useState<{workTaskId: number; action: 'blocked' | 'skip'} | null>(null);
  const [view, setView] = useState<View>({type: 'today'});
  const [noteDrafts, setNoteDrafts] = useState<Record<number, string>>({});
  const [noteErrors, setNoteErrors] = useState<Record<number, string | null>>({});
  const [savingNoteFor, setSavingNoteFor] = useState<number | null>(null);

  const load = useCallback(async (date: string | null = null) => {
    setPhase('loading');
    setLoadError(null);
    const startedAt = Date.now();
    try {
      const data = await fetchToday(date ?? undefined);
      setSnapshot(data.snapshot);
      setStatuses(data.statuses);
      setServerToday(data.today);
      setMyDates(data.my_dates ?? []);
      setAgentIds(data.agent_ids ?? []);
      setViewDate(data.date);
      setPhase('ready');
      void logEvent({
        feature: 'APP-1',
        step: 'load_today',
        outcome: 'success',
        durationMs: Date.now() - startedAt,
        metadata: {item_count: data.snapshot.items.length, date: data.date, zone: data.zone},
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
    // Deliberately runs ONCE. `load` takes the day as an argument
    // rather than reading state, so re-running it on every day change
    // would double-fetch; the navigation handlers below call it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Re-fetches without flipping `phase` — used after a note saves, so
  // the screen gets the server-stamped note (real author, real time)
  // without losing the user's place on the Step screen.
  const refresh = useCallback(async () => {
    try {
      // Refreshes the day being LOOKED AT, not the server's today —
      // otherwise saving a note while viewing another day would
      // silently jump the screen back (GAP-FIX W4).
      const data = await fetchToday(viewDate ?? undefined);
      setSnapshot(data.snapshot);
      setStatuses(data.statuses);
      setMyDates(data.my_dates ?? []);
    } catch {
      // Best effort: the write already succeeded; a failed refresh just
      // means the confirmation doesn't show until the next reload.
    }
  }, [viewDate]);

  const items = useMemo(() => (snapshot ? toPerformerItems(snapshot, statuses) : []), [snapshot, statuses]);
  const sessions = useMemo(() => toSessions(items), [items]);

  const act = useCallback(
    async (workTaskId: number, action: PerformerAction, reasonCode?: string) => {
      if (pendingWorkTaskId !== null) return; // one in-flight tap at a time
      setActionError(null);

      if (isOffline()) {
        const info = mapActionError({offline: true});
        setActionError({workTaskId, message: info.message});
        void logEvent({
          feature: 'APP-2',
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
          feature: 'APP-2',
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
          feature: 'APP-2',
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
      if (action === 'blocked' || action === 'skip') {
        setReasonPickerFor({workTaskId, action});
        return;
      }
      void act(workTaskId, action);
    },
    [act],
  );

  const onSaveNote = useCallback(
    async (workTaskId: number) => {
      const draft = (noteDrafts[workTaskId] ?? '').trim();
      if (draft === '') {
        setNoteErrors((e) => ({...e, [workTaskId]: 'Write something before saving.'}));
        return;
      }
      if (draft.length > NOTE_MAX_LENGTH) {
        setNoteErrors((e) => ({...e, [workTaskId]: 'Notes can be up to 1,000 characters.'}));
        return;
      }
      if (savingNoteFor !== null) return;
      setNoteErrors((e) => ({...e, [workTaskId]: null}));
      setSavingNoteFor(workTaskId);
      try {
        await recordEvent({workTaskId, eventType: 'note', clientEventId: newClientEventId(), note: draft});
        setNoteDrafts((d) => ({...d, [workTaskId]: ''}));
        void logEvent({feature: 'APP-2', step: 'note_save', outcome: 'success', entityType: 'work_task', entityId: workTaskId});
        await refresh();
      } catch (err) {
        const perr = err instanceof PerformRequestError ? err : null;
        const info = mapActionError({status: perr?.status, serverMessage: perr?.message ?? null, offline: perr?.offline ?? isOffline()});
        setNoteErrors((e) => ({...e, [workTaskId]: info.message})); // the typed draft is left in place — a failed save keeps the text
        void logEvent({
          feature: 'APP-2',
          step: 'note_save',
          outcome: 'failure',
          errorCode: info.code,
          message: info.message,
          entityType: 'work_task',
          entityId: workTaskId,
          correlationId: perr?.reference ?? null,
        });
      } finally {
        setSavingNoteFor(null);
      }
    },
    [noteDrafts, savingNoteFor, refresh],
  );

  // GAP-FIX W4 — day navigation. ‹ › step one calendar day; the
  // "next/last work" jump uses the published-days list so a performer
  // doesn't have to click through a quiet week to find their work.
  const days = useMemo(() => publishedDays(myDates), [myDates]);
  const shownDate = viewDate ?? serverToday;

  const goToDay = useCallback(
    (date: string) => {
      setView({type: 'today'});
      void logEvent({feature: 'APP-2', step: 'change_day', outcome: 'success', metadata: {date}});
      void load(date);
    },
    [load],
  );

  const diagnosis = useMemo(
    () => diagnoseEmptyDay({date: shownDate, today: serverToday, agentIds, days}),
    [shownDate, serverToday, agentIds, days],
  );

  const onOpenSession = useCallback((workItemId: number) => {
    void logEvent({feature: 'APP-2', step: 'open_session', outcome: 'success', entityType: 'work_item', entityId: workItemId});
    setView({type: 'session', workItemId});
  }, []);

  const onStartSession = useCallback(
    (workItemId: number) => {
      const session = sessions.find((s) => s.workItemId === workItemId);
      const firstTask = session?.items[0]?.subSteps[0]?.workTaskId;
      if (firstTask === undefined) return;
      void logEvent({feature: 'APP-2', step: 'start_session', outcome: 'success', entityType: 'work_item', entityId: workItemId});
      void act(firstTask, 'start');
    },
    [sessions, act],
  );

  const onFinishSession = useCallback((workItemId: number) => {
    void logEvent({feature: 'APP-2', step: 'finish_session', outcome: 'success', entityType: 'work_item', entityId: workItemId});
    setView({type: 'today'});
  }, []);

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

  // Defensive fallback for both branches below: an item is never
  // actually removed from the frozen snapshot (same guarantee APP-1
  // already relies on), so `session`/`item`/`sub` should never be
  // missing in practice — but a merge must degrade to Today rather
  // than crash if a stale `view` ever outlives its target.
  const todayFallback = (
    <TodayScreen
      date={shownDate}
      isToday={shownDate === serverToday}
      sessions={sessions}
      diagnosis={diagnosis}
      onOpenSession={onOpenSession}
      onPrevDay={() => goToDay(addDays(shownDate, -1))}
      onNextDay={() => goToDay(addDays(shownDate, 1))}
      onGoToToday={() => goToDay(serverToday)}
      onJumpTo={goToDay}
    />
  );

  if (view.type === 'session') {
    const session = sessions.find((s) => s.workItemId === view.workItemId);
    if (!session) {
      return todayFallback;
    }
    return (
      <SessionScreen
        session={session}
        pending={pendingWorkTaskId !== null}
        onBack={() => setView({type: 'today'})}
        onOpenStep={(workTaskId) => setView({type: 'step', workItemId: view.workItemId, workTaskId})}
        onStartSession={() => onStartSession(view.workItemId)}
        onFinishSession={() => onFinishSession(view.workItemId)}
      />
    );
  }

  if (view.type === 'step') {
    const session = sessions.find((s) => s.workItemId === view.workItemId);
    const item = session?.items.find((i) => i.subSteps.some((s) => s.workTaskId === view.workTaskId));
    const sub = item?.subSteps.find((s) => s.workTaskId === view.workTaskId);
    if (!session || !item || !sub) {
      return todayFallback;
    }
    const workTaskId = view.workTaskId;
    return (
      <StepScreen
        sub={sub}
        expectedMinutes={sub.expectedMinutes ?? item.scheduledMinutes}
        pending={pendingWorkTaskId === workTaskId}
        errorMessage={actionError?.workTaskId === workTaskId ? actionError.message : null}
        reasonPickerFor={reasonPickerFor?.workTaskId === workTaskId ? reasonPickerFor.action : null}
        noteDraft={noteDrafts[workTaskId] ?? ''}
        noteSaving={savingNoteFor === workTaskId}
        noteError={noteErrors[workTaskId] ?? null}
        onBack={() => setView({type: 'session', workItemId: view.workItemId})}
        onTapAction={(action) => onTapAction(workTaskId, action)}
        onPickReason={(reasonCode) => void act(workTaskId, reasonPickerFor!.action, reasonCode)}
        onSkipWithoutReason={() => void act(workTaskId, 'skip')}
        onCancelReason={() => setReasonPickerFor(null)}
        onChangeNoteDraft={(text) => setNoteDrafts((d) => ({...d, [workTaskId]: text}))}
        onSaveNote={() => void onSaveNote(workTaskId)}
        workItemId={view.workItemId}
        onExceptionSent={() => void refresh()}
      />
    );
  }

  return todayFallback;
}
