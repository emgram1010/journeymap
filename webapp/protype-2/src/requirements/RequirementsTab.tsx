// REQ-1 (US-REQ-1-01, US-REQ-1-02) — the account's one list of requirements: things a step can need
// and a person can hold. Shown as a tab of the Catalog page. Anyone in the account can read; only an
// admin adds, renames, archives or deletes (the server re-checks every call). A rejected save shows
// the server's plain sentence and KEEPS what was typed. A near match ("Forklift" vs "Forklift
// licence") is shown before anything is saved, and nothing is created until the person says so.
import {useCallback, useEffect, useState} from 'react';
import {Loader2, AlertCircle, Plus, Trash2, Archive, ArchiveRestore, Users} from 'lucide-react';
import {
  listRequirements,
  addRequirement,
  renameRequirement,
  archiveRequirement,
  deleteRequirement,
  listHolders,
  type Requirement,
  type RequirementMatch,
  type Holder,
} from './requirementsApi';
import {validateName, endsSoonLabel, REQUIREMENTS_PER_ACCOUNT_LIMIT} from './requirementModel';

const friendly = (err: unknown, fallback: string): string => (err as {serverMessage?: string | null} | null)?.serverMessage || fallback;

function Holders({requirementId}: {requirementId: number}) {
  const [holders, setHolders] = useState<Holder[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    listHolders(requirementId)
      .then(r => { if (alive) setHolders(r.holders); })
      .catch(err => { if (alive) setError(friendly(err, 'Could not load who holds this.')); });
    return () => { alive = false; };
  }, [requirementId]);
  if (error) return <p className="text-xs text-red-700 mt-2">{error}</p>;
  if (!holders) return <p className="text-xs text-zinc-500 mt-2">Loading…</p>;
  if (holders.length === 0) return <p className="text-xs text-zinc-500 mt-2">Nobody holds this yet. Record it on a person in Agents.</p>;
  return (
    <ul className="mt-2 text-xs text-zinc-700 flex flex-col gap-0.5" data-testid="requirement-holders">
      {holders.map(h => {
        const soon = endsSoonLabel({held: h.held, endsSoon: h.ends_soon, until: h.held_until, daysLeft: h.days_left});
        return (
          <li key={h.agent_profile_id}>
            {h.name || `Profile ${h.agent_profile_id}`}
            {h.held_until ? <span className="text-zinc-500"> · until {h.held_until}</span> : <span className="text-zinc-500"> · no end date</span>}
            {!h.held && <span className="text-red-700"> · ended</span>}
            {soon && <span className="text-amber-700"> · {soon}</span>}
          </li>
        );
      })}
    </ul>
  );
}

function Row({item, isAdmin, onChanged}: {item: Requirement; isAdmin: boolean; onChanged: () => void}) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(item.name);
  const [desc, setDesc] = useState(item.description ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showHolders, setShowHolders] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const run = async (fn: () => Promise<unknown>, fallback: string) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      onChanged();
      return true;
    } catch (err) {
      setError(friendly(err, fallback));
      return false;
    } finally {
      setBusy(false);
    }
  };

  const save = async () => {
    const check = validateName(name);
    if (check.ok === false) { setError(check.message); return; }
    if (await run(() => renameRequirement(item.id, {name, description: desc}), 'Could not save. Try again.')) setEditing(false);
  };

  return (
    <li className="p-3" data-testid={`requirement-row-${item.id}`}>
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          {editing ? (
            <div className="flex flex-col gap-1.5">
              <input value={name} onChange={e => setName(e.target.value)} className="border border-zinc-300 rounded px-2 py-1 text-sm" aria-label="Requirement name" />
              <input value={desc} onChange={e => setDesc(e.target.value)} placeholder="Short description (optional)" className="border border-zinc-300 rounded px-2 py-1 text-xs" aria-label="Description" />
              <p className="text-[11px] text-zinc-500">A rename only changes the label everywhere it is used. If it now means something different, add a new requirement and archive this one.</p>
            </div>
          ) : (
            <>
              <p className="text-sm font-medium text-zinc-900">
                {item.name} {!item.is_active && <span className="text-[11px] font-normal text-zinc-500">(archived)</span>}
              </p>
              {item.description && <p className="text-xs text-zinc-500">{item.description}</p>}
              <p className="text-[11px] text-zinc-500 mt-0.5">
                {item.used_by_steps} step{item.used_by_steps === 1 ? '' : 's'} need it · {item.held_by_people} {item.held_by_people === 1 ? 'person holds' : 'people hold'} it · in {item.in_versions} published version{item.in_versions === 1 ? '' : 's'}
              </p>
            </>
          )}
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <button type="button" onClick={() => setShowHolders(v => !v)} className="p-1.5 text-zinc-500 hover:text-zinc-900" title="Who holds it" aria-label="Who holds it">
            <Users className="w-4 h-4" />
          </button>
          {isAdmin && !editing && (
            <>
              <button type="button" onClick={() => { setEditing(true); setName(item.name); setDesc(item.description ?? ''); }} className="px-2 py-1 text-xs text-zinc-700 hover:bg-zinc-100 rounded">Rename</button>
              <button type="button" disabled={busy} onClick={() => run(() => archiveRequirement(item.id, item.is_active), 'Could not change that. Try again.')} className="p-1.5 text-zinc-500 hover:text-zinc-900" title={item.is_active ? 'Archive' : 'Restore'} aria-label={item.is_active ? 'Archive' : 'Restore'}>
                {item.is_active ? <Archive className="w-4 h-4" /> : <ArchiveRestore className="w-4 h-4" />}
              </button>
              <button type="button" disabled={busy} onClick={() => setConfirmDelete(true)} className="p-1.5 text-zinc-500 hover:text-red-700" title="Delete" aria-label="Delete">
                <Trash2 className="w-4 h-4" />
              </button>
            </>
          )}
          {isAdmin && editing && (
            <>
              <button type="button" disabled={busy} onClick={() => { setEditing(false); setError(null); }} className="px-2 py-1 text-xs text-zinc-600">Cancel</button>
              <button type="button" disabled={busy} onClick={save} className="px-2.5 py-1 text-xs font-semibold text-white bg-zinc-900 rounded disabled:opacity-50">{busy ? 'Saving…' : 'Save'}</button>
            </>
          )}
        </div>
      </div>
      {confirmDelete && (
        <div className="mt-2 border border-red-200 bg-red-50/50 rounded p-2 flex items-center gap-2 text-xs">
          <span className="flex-1">Delete "{item.name}"? It can only be deleted while nothing uses it.</span>
          <button type="button" onClick={() => setConfirmDelete(false)} className="px-2 py-1 text-zinc-600">Cancel</button>
          <button
            type="button"
            disabled={busy}
            onClick={async () => { setConfirmDelete(false); await run(() => deleteRequirement(item.id), 'Could not delete. Try again.'); }}
            className="px-2.5 py-1 font-semibold text-white bg-red-700 rounded disabled:opacity-50"
          >
            Delete
          </button>
        </div>
      )}
      {error && <p className="mt-2 text-xs text-red-700 flex items-start gap-1.5" role="alert"><AlertCircle className="w-3.5 h-3.5 mt-0.5 shrink-0" />{error}</p>}
      {showHolders && <Holders requirementId={item.id} />}
    </li>
  );
}

function AddForm({count, onAdded}: {count: number; onAdded: () => void}) {
  const [name, setName] = useState('');
  const [desc, setDesc] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [matches, setMatches] = useState<RequirementMatch[] | null>(null);

  const submit = async (confirmSimilar: boolean) => {
    const check = validateName(name);
    if (check.ok === false) { setError(check.message); return; }
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      const res = await addRequirement({name, description: desc, confirm_similar: confirmSimilar});
      if (res.outcome === 'similar') {
        setMatches(res.matches);
      } else if (res.outcome === 'exists') {
        setMatches(null);
        setNote(`"${res.requirement?.name ?? name}" is already in the list${res.requirement && !res.requirement.is_active ? ' (archived: restore it instead)' : ''}. Nothing was added.`);
      } else {
        setMatches(null);
        setName('');
        setDesc('');
        onAdded();
      }
    } catch (err) {
      setError(friendly(err, 'Could not add that. Try again.')); // the typing stays
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="mt-4 border border-zinc-200 rounded-md bg-white p-3" data-testid="requirement-add">
      <h3 className="text-sm font-semibold text-zinc-900 mb-2">Add a requirement</h3>
      <div className="flex flex-col sm:flex-row gap-2">
        <input id="requirement-name" value={name} onChange={e => { setName(e.target.value); setMatches(null); setNote(null); }} placeholder="Name, e.g. Forklift licence" className="flex-1 border border-zinc-300 rounded px-2 py-1.5 text-sm" aria-label="Requirement name" />
        <input id="requirement-desc" value={desc} onChange={e => setDesc(e.target.value)} placeholder="Short description (optional)" className="flex-1 border border-zinc-300 rounded px-2 py-1.5 text-sm" aria-label="Description" />
        <button id="requirement-add-btn" type="button" disabled={busy || name.trim() === ''} onClick={() => submit(false)} className="inline-flex items-center justify-center gap-1 px-3 py-1.5 text-sm font-semibold text-white bg-zinc-900 rounded disabled:opacity-50">
          {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />} Add
        </button>
      </div>
      <p className="text-[11px] text-zinc-500 mt-1.5">{count} of {REQUIREMENTS_PER_ACCOUNT_LIMIT}. "Forklift" and " forklift " are the same requirement.</p>
      {matches && (
        <div className="mt-2 border border-amber-200 bg-amber-50/50 rounded p-2 text-xs" role="status">
          <p className="font-medium text-zinc-900">Something like this already exists:</p>
          <ul className="my-1 list-disc pl-5">{matches.map(m => <li key={m.id}>{m.name}{!m.is_active ? ' (archived)' : ''}</li>)}</ul>
          <div className="flex gap-2 justify-end">
            <button type="button" onClick={() => setMatches(null)} className="px-2 py-1 text-zinc-600">Cancel</button>
            <button type="button" disabled={busy} onClick={() => submit(true)} className="px-2.5 py-1 font-semibold text-white bg-zinc-900 rounded disabled:opacity-50">Add "{name.trim()}" anyway</button>
          </div>
        </div>
      )}
      {note && <p className="mt-2 text-xs text-zinc-700" role="status">{note}</p>}
      {error && <p className="mt-2 text-xs text-red-700 flex items-start gap-1.5" role="alert"><AlertCircle className="w-3.5 h-3.5 mt-0.5 shrink-0" />{error}</p>}
    </div>
  );
}

export default function RequirementsTab({isAdmin}: {isAdmin: boolean}) {
  const [items, setItems] = useState<Requirement[]>([]);
  const [showArchived, setShowArchived] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    listRequirements(showArchived)
      .then(r => setItems(r.requirements))
      .catch(err => setError(friendly(err, 'Unable to load requirements.')))
      .finally(() => setLoading(false));
  }, [showArchived]);

  useEffect(() => { load(); }, [load]);

  return (
    <div>
      <p className="text-xs text-zinc-500 mb-3">
        A requirement is something work can need and a person can hold: a licence, a skill, a tool, a language. Pick it on a step of a map, and record who holds it in Agents.
      </p>
      <label className="flex items-center gap-1.5 text-xs text-zinc-600 mb-2">
        <input type="checkbox" checked={showArchived} onChange={e => setShowArchived(e.target.checked)} /> Show archived
      </label>
      {error && <p className="text-xs text-red-700 mb-2" role="alert">{error}</p>}
      {loading ? (
        <p className="text-sm text-zinc-500 flex items-center gap-2"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</p>
      ) : (
        <ul className="divide-y divide-zinc-200 rounded-md border border-zinc-200 bg-white" data-testid="requirement-list">
          {items.length === 0 && <li className="p-4 text-sm text-zinc-500">No requirements yet.{isAdmin ? ' Add the first one below.' : ''}</li>}
          {items.map(item => <Row key={item.id} item={item} isAdmin={isAdmin} onChanged={load} />)}
        </ul>
      )}
      {isAdmin ? <AddForm count={items.filter(i => i.is_active).length} onAdded={load} /> : <p className="text-xs text-zinc-500 mt-3">Only an account admin can change this list.</p>}
    </div>
  );
}
