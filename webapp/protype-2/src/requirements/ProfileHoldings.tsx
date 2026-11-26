// REQ-1 (US-REQ-1-02) — what ONE person (lasting profile) holds, and until when. Lives under each
// person in the Agents window. Everyone in the account can read; only an admin PERSON records,
// changes or removes (the server re-checks, and refuses an AI). A holding with no end date never
// ends; one with a date counts through that date and stops the day after. "Ends soon" shows within
// 30 days. A rejected save shows the server's sentence and keeps what was typed.
import {useCallback, useEffect, useState} from 'react';
import {AlertCircle, Plus, X} from 'lucide-react';
import {listHoldings, recordHolding, removeHolding, type RawHolding} from '../planner/plannerApi';
import {listRequirements, type Requirement} from './requirementsApi';
import {endsSoonLabel} from './requirementModel';

const friendly = (err: unknown, fallback: string): string =>
  (err as {serverMessage?: string | null} | null)?.serverMessage || (err instanceof Error ? err.message : fallback);

export default function ProfileHoldings({profileId, isAdmin}: {profileId: number; isAdmin: boolean}) {
  const [holdings, setHoldings] = useState<RawHolding[] | null>(null);
  const [options, setOptions] = useState<Requirement[]>([]);
  const [pick, setPick] = useState(0);
  const [until, setUntil] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [h, r] = await Promise.all([listHoldings(profileId), isAdmin ? listRequirements(false) : Promise.resolve({requirements: [] as Requirement[]})]);
      setHoldings(h.holdings);
      setOptions(r.requirements);
    } catch (err) {
      setError(friendly(err, 'Could not load what this person holds.'));
    }
  }, [profileId, isAdmin]);

  useEffect(() => { void load(); }, [load]);

  const save = async (requirementId: number, heldUntil: string) => {
    setBusy(true);
    setError(null);
    try {
      await recordHolding(profileId, {requirement_id: requirementId, held_until: heldUntil});
      setPick(0);
      setUntil('');
      await load();
    } catch (err) {
      setError(friendly(err, 'Could not save that. Try again.')); // the typing stays
    } finally {
      setBusy(false);
    }
  };

  const remove = async (requirementId: number) => {
    setBusy(true);
    setError(null);
    try {
      await removeHolding(profileId, requirementId);
      await load();
    } catch (err) {
      setError(friendly(err, 'Could not remove that. Try again.'));
    } finally {
      setBusy(false);
    }
  };

  const heldIds = new Set((holdings ?? []).map(h => h.requirement_id));
  const available = options.filter(o => !heldIds.has(o.id));

  return (
    <div className="mt-2 pl-1" data-testid={`holdings-${profileId}`}>
      {holdings === null ? (
        <p className="text-[11px] text-neutral-400">Loading…</p>
      ) : holdings.length === 0 ? (
        <p className="text-[11px] text-neutral-500">Holds nothing recorded yet.</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {holdings.map(h => {
            const soon = endsSoonLabel({held: h.held, endsSoon: h.ends_soon, until: h.held_until, daysLeft: h.days_left});
            return (
              <li key={h.requirement_id} className="flex items-center gap-2 text-[11px] text-neutral-800">
                <span className="min-w-0 flex-1">
                  {h.name}
                  {h.archived && <span className="text-neutral-400"> (archived)</span>}
                  <span className="text-neutral-500">{h.held_until ? ` · until ${h.held_until}` : ' · no end date'}</span>
                  {!h.held && <span className="text-red-700"> · ended</span>}
                  {soon && <span className="text-amber-700"> · {soon}</span>}
                </span>
                {isAdmin && (
                  <button type="button" disabled={busy} onClick={() => void remove(h.requirement_id)} className="p-0.5 text-neutral-400 hover:text-red-700" aria-label={`Remove ${h.name}`}>
                    <X className="w-3.5 h-3.5" />
                  </button>
                )}
              </li>
            );
          })}
        </ul>
      )}
      {isAdmin && (
        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          <select value={pick} onChange={e => setPick(Number(e.target.value))} className="border border-neutral-300 rounded px-1.5 py-1 text-[11px]" aria-label="Requirement to record">
            <option value={0}>Add a requirement…</option>
            {available.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
          </select>
          <input type="date" value={until} onChange={e => setUntil(e.target.value)} className="border border-neutral-300 rounded px-1.5 py-1 text-[11px] font-mono" aria-label="Held until (optional)" />
          <button type="button" disabled={busy || pick === 0} onClick={() => void save(pick, until)} className="inline-flex items-center gap-1 px-2 py-1 text-[11px] font-semibold text-white bg-neutral-900 rounded disabled:opacity-40">
            <Plus className="w-3 h-3" /> Record
          </button>
          {options.length === 0 && <span className="text-[11px] text-neutral-400">No requirements yet: add them in Catalog → Requirements.</span>}
        </div>
      )}
      {isAdmin && holdings && holdings.length > 0 && <p className="text-[10px] text-neutral-400 mt-1">Leave the date empty for no end. To change a date, record the same requirement again.</p>}
      {error && <p className="mt-1.5 text-[11px] text-red-700 flex items-start gap-1" role="alert"><AlertCircle className="w-3 h-3 mt-0.5 shrink-0" />{error}</p>}
    </div>
  );
}
