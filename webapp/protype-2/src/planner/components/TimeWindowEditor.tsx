// TW-1 (US-TW-1-03) — Add, edit and remove a job's time window, inline in
// its JobsModal row. "V1 warns, never blocks" (D-2): this component only
// collects and validates the fields; the DayBoard card is what shows the
// "outside time window" warning.
//
// REJECTED SAVES KEEP TYPING (CLAUDE.md UI rule) — a failed PUT leaves the
// draft exactly as typed; only a successful save (or "Remove") clears it.
// The server is still the authority (D-6): client-side `validateWindow`
// only avoids an obviously-wrong round trip, and the server's own message
// (same codes) is shown as-is if it still refuses.
import {useEffect, useState} from 'react';
import {Clock, Trash2} from 'lucide-react';
import {deleteTimeWindow, putTimeWindow, type RawTimeWindow} from '../plannerApi';
import {formatWindow, validateWindow, type TimeWindow} from '../timeWindowModel';
import {getWindowBounds} from '../utils/dateUtils';

interface TimeWindowEditorProps {
  workItemId: number;
  window: RawTimeWindow | null;
  /** The plan's own window (WIN-1) — bounds the date pickers; D-5 still allows partial overlap server-side. */
  planWindow: {start: string | null; end: string | null};
  onChanged: (window: RawTimeWindow | null, needsRepublish: boolean) => void;
}

type Draft = {start_date: string; start_time: string; end_date: string; end_time: string; note: string};

const toDraft = (w: RawTimeWindow | null): Draft =>
  w
    ? {start_date: w.start_date, start_time: w.start_time, end_date: w.end_date, end_time: w.end_time, note: w.note ?? ''}
    : {start_date: '', start_time: '', end_date: '', end_time: '', note: ''};

export function TimeWindowEditor({workItemId, window, planWindow, onChanged}: TimeWindowEditorProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [draft, setDraft] = useState<Draft>(toDraft(window));
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [confirmRemove, setConfirmRemove] = useState(false);

  // Only reset the draft from the server when NOT mid-edit — a refresh
  // triggered by something else must not erase what the planner is typing.
  useEffect(() => {
    if (!isEditing) setDraft(toDraft(window));
  }, [window, isEditing]);

  const startEdit = () => {
    setDraft(toDraft(window));
    setError(null);
    setIsEditing(true);
  };

  const handleSave = async () => {
    const candidate: TimeWindow = draft;
    const check = validateWindow(candidate, planWindow);
    // `check.ok === false`, not `!check.ok` — this TS setup does not narrow
    // a two-member union whose true-branch has no other fields via `!`.
    if (check.ok === false) {
      setError(check.message);
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      const result = await putTimeWindow(workItemId, {
        start_date: draft.start_date,
        start_time: draft.start_time,
        end_date: draft.end_date,
        end_time: draft.end_time,
        note: draft.note,
      });
      setIsEditing(false);
      onChanged(result.time_window, result.needs_republish);
    } catch (err) {
      // Server message carries the same E-TW-### codes as validateWindow; shown as-is (D-6).
      setError(err instanceof Error ? err.message : "Couldn't save the time window.");
    } finally {
      setIsSaving(false);
    }
  };

  const handleRemove = async () => {
    setIsSaving(true);
    setError(null);
    try {
      const result = await deleteTimeWindow(workItemId);
      setConfirmRemove(false);
      setIsEditing(false);
      onChanged(null, result.needs_republish);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't remove the time window.");
    } finally {
      setIsSaving(false);
    }
  };

  const bounds = getWindowBounds(planWindow.start, planWindow.end);

  if (!isEditing) {
    return (
      <div className="flex items-center gap-2">
        <Clock className="w-3 h-3 text-neutral-400 shrink-0" />
        {window ? (
          <>
            <span className="text-[11px] text-neutral-700">Time window {formatWindow(window)}</span>
            <button type="button" onClick={startEdit} className="text-[11px] text-blue-700 hover:underline">
              Edit
            </button>
            {confirmRemove ? (
              <span className="flex items-center gap-1.5">
                <button
                  type="button"
                  onClick={() => void handleRemove()}
                  disabled={isSaving}
                  className="text-[11px] font-semibold text-red-700 hover:underline disabled:opacity-60"
                >
                  Remove time window
                </button>
                <button type="button" onClick={() => setConfirmRemove(false)} className="text-[11px] text-neutral-500 hover:underline">
                  Keep
                </button>
              </span>
            ) : (
              <button type="button" onClick={() => setConfirmRemove(true)} className="text-[11px] text-neutral-500 hover:text-red-700">
                <Trash2 className="w-3 h-3" />
              </button>
            )}
          </>
        ) : (
          <button type="button" onClick={startEdit} className="text-[11px] text-blue-700 hover:underline">
            Add time window
          </button>
        )}
      </div>
    );
  }

  return (
    <div className="rounded border border-neutral-200 bg-white p-2 flex flex-col gap-2">
      <div className="grid grid-cols-2 gap-2">
        <label className="text-[10px] text-neutral-600">
          Start date
          <input
            type="date"
            value={draft.start_date}
            min={bounds.min}
            max={bounds.max}
            onChange={(e) => setDraft({...draft, start_date: e.target.value})}
            className="mt-0.5 w-full rounded border border-neutral-300 px-1.5 py-1 text-[11px]"
          />
        </label>
        <label className="text-[10px] text-neutral-600">
          Start time
          <input
            type="time"
            value={draft.start_time}
            onChange={(e) => setDraft({...draft, start_time: e.target.value})}
            className="mt-0.5 w-full rounded border border-neutral-300 px-1.5 py-1 text-[11px]"
          />
        </label>
        <label className="text-[10px] text-neutral-600">
          End date
          <input
            type="date"
            value={draft.end_date}
            min={bounds.min}
            max={bounds.max}
            onChange={(e) => setDraft({...draft, end_date: e.target.value})}
            className="mt-0.5 w-full rounded border border-neutral-300 px-1.5 py-1 text-[11px]"
          />
        </label>
        <label className="text-[10px] text-neutral-600">
          End time
          <input
            type="time"
            value={draft.end_time}
            onChange={(e) => setDraft({...draft, end_time: e.target.value})}
            className="mt-0.5 w-full rounded border border-neutral-300 px-1.5 py-1 text-[11px]"
          />
        </label>
      </div>
      <label className="text-[10px] text-neutral-600">
        Note (optional)
        <input
          type="text"
          value={draft.note}
          maxLength={200}
          placeholder="e.g. site opens at 9"
          onChange={(e) => setDraft({...draft, note: e.target.value})}
          className="mt-0.5 w-full rounded border border-neutral-300 px-1.5 py-1 text-[11px]"
        />
      </label>
      {error && <p className="text-[11px] text-red-600">{error}</p>}
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => void handleSave()}
          disabled={isSaving}
          className="px-2 py-1 text-[11px] font-semibold text-white bg-neutral-900 hover:bg-neutral-800 rounded disabled:opacity-60"
        >
          {isSaving ? 'Saving…' : 'Save'}
        </button>
        <button
          type="button"
          onClick={() => {
            setIsEditing(false);
            setError(null);
            setDraft(toDraft(window));
          }}
          className="px-2 py-1 text-[11px] text-neutral-600 hover:text-neutral-900"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
