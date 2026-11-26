// REQ-1 (US-REQ-1-04) — what ONE step of the map needs, hard (a must) or soft (preferred). Shown in
// the selected-step panel of the map screen. A DRAFT edit like any other change to a step: nothing
// reaches a job until the map is published as a new version. Needs are picked from the account's
// list (Catalog → Requirements), never typed here, so a need and a holding always mean the same
// thing. "Apply to every step in this row" is a shortcut that writes the same per-step needs through
// the same server rule. Zero people holding a need NOW is a plain warning, never a block: the
// designer may be setting up before the people are recorded. The server re-checks every rule.
import {useCallback, useEffect, useState} from 'react';
import {AlertCircle, AlertTriangle, X} from 'lucide-react';
import {
  listMapNeeds,
  listRequirements,
  setStepNeed,
  removeStepNeed,
  applyNeedToRow,
  type StepNeed,
  type Requirement,
} from './requirementsApi';
import {strengthLabel, nextStrength, addNeedAllowed, type Strength} from './requirementModel';

const friendly = (err: unknown, fallback: string): string =>
  (err as {serverMessage?: string | null} | null)?.serverMessage || (err instanceof Error ? err.message : fallback);

interface Props {
  mapId: number;
  cellXanoId?: number;
  lensXanoId?: number;
  /** Does this step's row do planned work? Needs can only be set on planned work. */
  plannedWork: boolean;
  locked: boolean;
}

export default function StepNeeds({mapId, cellXanoId, lensXanoId, plannedWork, locked}: Props) {
  const [needs, setNeeds] = useState<StepNeed[] | null>(null);
  const [options, setOptions] = useState<Requirement[]>([]);
  const [pick, setPick] = useState(0);
  const [strength, setStrength] = useState<Strength>('hard');
  const [wholeRow, setWholeRow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [n, r] = await Promise.all([listMapNeeds(mapId), listRequirements(false)]);
      setNeeds(n.needs);
      setOptions(r.requirements);
    } catch (err) {
      setError(friendly(err, 'Could not load what this step needs.'));
    }
  }, [mapId]);

  useEffect(() => { setNeeds(null); setError(null); setNote(null); setPick(0); void load(); }, [load, cellXanoId]);

  if (cellXanoId == null) return null;
  const mine = (needs ?? []).filter(n => n.journey_cell_id === cellXanoId);
  const mineIds = new Set(mine.map(n => n.requirement_id));
  const chosen = options.find(o => o.id === pick);
  const check = chosen ? addNeedAllowed({currentCount: mine.length, alreadyOnStep: mineIds.has(chosen.id), archived: !chosen.is_active}) : {ok: true as const};
  const disabledWhy = !plannedWork ? 'This row is not marked as planned work, so its steps cannot have needs.' : locked ? "This step is locked, so it can't be changed." : null;

  const run = async (fn: () => Promise<unknown>, fallback: string) => {
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      await fn();
      await load();
      return true;
    } catch (err) {
      setError(friendly(err, fallback)); // the choices stay
      return false;
    } finally {
      setBusy(false);
    }
  };

  const add = async () => {
    if (!chosen) return;
    if (wholeRow && lensXanoId != null) {
      const ok = await run(async () => {
        const res = await applyNeedToRow(mapId, lensXanoId, chosen.id, strength);
        const skipped = res.refused.length;
        setNote(`${res.added + res.changed} of ${res.steps_in_row} steps in this row changed${res.already_there ? `, ${res.already_there} already had it` : ''}${skipped ? `, ${skipped} skipped (locked or full)` : ''}.`);
      }, 'Could not apply that to the row.');
      if (ok) setPick(0);
      return;
    }
    if (await run(() => setStepNeed(cellXanoId, chosen.id, strength), 'Could not add that need.')) setPick(0);
  };

  return (
    <div className="px-4 pb-4 space-y-2" data-testid="step-needs">
      <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">What this step needs</label>
      {needs === null ? (
        <p className="text-xs text-zinc-400">Loading…</p>
      ) : mine.length === 0 ? (
        <p className="text-xs text-zinc-500">Nothing in particular: anyone can be given this step.</p>
      ) : (
        <ul className="space-y-1">
          {mine.map(n => (
            <li key={n.requirement_id} className="text-xs border border-zinc-200 rounded px-2 py-1.5 bg-zinc-50">
              <div className="flex items-center gap-2">
                <span className="flex-1 min-w-0 truncate font-medium text-zinc-800">
                  {n.name}
                  {n.archived && <span className="font-normal text-zinc-400"> (archived)</span>}
                </span>
                <button
                  type="button"
                  disabled={busy || disabledWhy !== null}
                  onClick={() => void run(() => setStepNeed(cellXanoId, n.requirement_id, nextStrength(n.strength)), 'Could not change that.')}
                  className={`px-1.5 py-0.5 rounded text-[10px] font-semibold border ${n.strength === 'hard' ? 'bg-zinc-900 text-white border-zinc-900' : 'bg-white text-zinc-700 border-zinc-300'} disabled:opacity-50`}
                  title="Click to switch between a must and a preference"
                >
                  {strengthLabel(n.strength)}
                </button>
                <button type="button" disabled={busy || locked} onClick={() => void run(() => removeStepNeed(cellXanoId, n.requirement_id), 'Could not remove that.')} className="p-0.5 text-zinc-400 hover:text-red-700" aria-label={`Remove ${n.name}`}>
                  <X className="w-3.5 h-3.5" />
                </button>
              </div>
              <p className={`text-[10px] mt-0.5 ${n.holders_now === 0 ? 'text-amber-700' : 'text-zinc-500'}`}>
                {n.holders_now === 0 ? (
                  <><AlertTriangle className="inline w-3 h-3 -mt-0.5 mr-0.5" />No one holds this right now.</>
                ) : (
                  `${n.holders_now} ${n.holders_now === 1 ? 'person holds' : 'people hold'} this right now.`
                )}
              </p>
            </li>
          ))}
        </ul>
      )}
      {disabledWhy ? (
        <p className="text-[11px] text-zinc-500">{disabledWhy}</p>
      ) : (
        <div className="flex flex-col gap-1.5">
          <div className="flex flex-wrap items-center gap-1.5">
            <select value={pick} onChange={e => setPick(Number(e.target.value))} className="border border-zinc-300 rounded px-1.5 py-1 text-xs flex-1 min-w-[8rem]" aria-label="Requirement to add">
              <option value={0}>{options.length === 0 ? 'No requirements yet' : 'Add a need…'}</option>
              {options.filter(o => !mineIds.has(o.id)).map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
            </select>
            <select value={strength} onChange={e => setStrength(e.target.value as Strength)} className="border border-zinc-300 rounded px-1.5 py-1 text-xs" aria-label="Must have or preferred">
              <option value="hard">Must have</option>
              <option value="soft">Preferred</option>
            </select>
            <button type="button" disabled={busy || pick === 0 || check.ok === false} onClick={() => void add()} className="px-2.5 py-1 text-xs font-semibold text-white bg-zinc-900 rounded disabled:opacity-40">
              Add
            </button>
          </div>
          {check.ok === false && <p className="text-[11px] text-red-700">{check.message}</p>}
          {lensXanoId != null && (
            <label className="flex items-center gap-1.5 text-[11px] text-zinc-600">
              <input type="checkbox" checked={wholeRow} onChange={e => setWholeRow(e.target.checked)} /> Apply to every step in this row
            </label>
          )}
          {options.length === 0 && <p className="text-[11px] text-zinc-500">Add requirements first in Catalog → Requirements.</p>}
        </div>
      )}
      <p className="text-[11px] text-zinc-500">Takes effect for new jobs after you Publish version.</p>
      {note && <p className="text-[11px] text-zinc-700" role="status">{note}</p>}
      {error && <p className="text-[11px] text-red-700 flex items-start gap-1" role="alert"><AlertCircle className="w-3 h-3 mt-0.5 shrink-0" />{error}</p>}
    </div>
  );
}
