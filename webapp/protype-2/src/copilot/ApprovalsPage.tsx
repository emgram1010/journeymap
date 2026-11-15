import React, {useCallback, useEffect, useState} from 'react';
import {AlertCircle, Check, Loader2} from 'lucide-react';
import {
  decideCopilotAction,
  listCopilotActions,
  listCopilotLevels,
  listJourneyArchitectures,
  markCopilotActionSeen,
  setCopilotLevel,
  XanoHttpError,
  type XanoCopilotAction,
  type XanoCopilotLevelRow,
  type XanoJourneyArchitecture,
} from '../xano';
import {
  LEVEL_LABELS,
  TOUCHES_LABELS,
  isNewlyTold,
  levelChangeNeedsConfirm,
  limitProblem,
  parseEditedPayload,
  prettyPayload,
  statusLabel,
  undoState,
  type Level,
  actionTypeLabel,
} from './approvalsModel';

/**
 * COP-2 — Approvals. Three tabs: Waiting for you, What the copilot did, Approval levels.
 * The server decides everything and refuses again; its own sentence is shown on refusal,
 * and anything the person typed is kept.
 */

type Tab = 'waiting' | 'done' | 'levels';

const serverText = (e: unknown, fallback: string): string => {
  if (e instanceof XanoHttpError) return e.serverMessage || fallback;
  return fallback;
};

const formatWhen = (v: number | string | null | undefined): string => {
  if (v == null || v === '') return '';
  const d = new Date(typeof v === 'number' ? v : Number(v) || v);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleString();
};

export default function ApprovalsPage() {
  const [tab, setTab] = useState<Tab>('waiting');
  const [waiting, setWaiting] = useState<XanoCopilotAction[]>([]);
  const [done, setDone] = useState<XanoCopilotAction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const r = await listCopilotActions();
      setWaiting(r.waiting ?? []);
      setDone(r.done ?? []);
      setError(null);
      window.dispatchEvent(new Event('copilot-actions-changed'));
    } catch (e) {
      setError(serverText(e, 'Unable to load approvals right now.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const tabs: {id: Tab; label: string; count?: number}[] = [
    {id: 'waiting', label: 'Waiting for you', count: waiting.length},
    {id: 'done', label: 'What the copilot did', count: done.filter((d) => isNewlyTold(d.status)).length},
    {id: 'levels', label: 'Approval levels'},
  ];

  return (
    <div className="p-6 max-w-4xl mx-auto w-full overflow-y-auto">
      <h1 className="text-xl font-semibold text-zinc-900 mb-4">Approvals</h1>
      <div role="tablist" className="flex gap-1 border-b border-zinc-200 mb-4">
        {tabs.map((t) => (
          <button
            key={t.id}
            id={`approvals-tab-${t.id}`}
            role="tab"
            aria-selected={tab === t.id}
            onClick={() => setTab(t.id)}
            className={`px-3 py-2 text-sm font-medium border-b-2 -mb-px ${
              tab === t.id ? 'border-zinc-900 text-zinc-900' : 'border-transparent text-zinc-500 hover:text-zinc-900'
            }`}
          >
            {t.label}
            {t.count ? (
              <span className="ml-2 rounded-full bg-zinc-900 text-white text-xs px-1.5 py-0.5">{t.count}</span>
            ) : null}
          </button>
        ))}
      </div>
      {error && tab !== 'levels' && (
        <p role="alert" className="flex items-center gap-2 text-sm text-red-700 mb-3">
          <AlertCircle className="w-4 h-4" /> {error}
        </p>
      )}
      {tab !== 'levels' && loading && <Loader2 className="w-4 h-4 animate-spin text-zinc-400" />}
      {tab === 'waiting' && !loading && <WaitingTab items={waiting} onChanged={load} />}
      {tab === 'done' && !loading && <DoneTab items={done} onChanged={load} />}
      {tab === 'levels' && <LevelsTab />}
    </div>
  );
}

function PayloadBox({value}: {value: unknown}) {
  return (
    <pre className="mt-2 max-h-56 overflow-auto rounded-md bg-zinc-50 border border-zinc-200 p-2 text-xs text-zinc-800 whitespace-pre-wrap">
      {prettyPayload(value)}
    </pre>
  );
}

function WaitingTab({items, onChanged}: {items: XanoCopilotAction[]; onChanged: () => Promise<void>}) {
  if (items.length === 0) return <p className="text-sm text-zinc-500">Nothing is waiting for you.</p>;
  return (
    <ul className="flex flex-col gap-3">
      {items.map((a) => (
        <WaitingItem key={a.id} a={a} onChanged={onChanged} />
      ))}
    </ul>
  );
}

function WaitingItem({a, onChanged}: {a: XanoCopilotAction; onChanged: () => Promise<void>}) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(() => prettyPayload(a.payload));

  const decide = async (decision: 'approve' | 'edit' | 'reject') => {
    setMessage(null);
    let edited: unknown;
    if (decision === 'edit') {
      const parsed = parseEditedPayload(text);
      if (parsed.ok === false) {
        setMessage(parsed.message); // typing is kept
        return;
      }
      edited = parsed.value;
    }
    setBusy(true);
    try {
      await decideCopilotAction(a.id, decision, edited);
      await onChanged();
    } catch (e) {
      setMessage(serverText(e, 'That did not go through. Nothing was changed.'));
      // Keep the typing and the message on screen (CLAUDE.md: keep the user's typing on any
      // rejected save). The item may now be decided, expired or out of date; the owner refreshes.
    } finally {
      setBusy(false);
    }
  };

  return (
    <li className="rounded-lg border border-zinc-200 bg-white p-4" id={`approval-${a.id}`}>
      <p className="text-sm font-medium text-zinc-900">{a.summary || 'Copilot action'}</p>
      <p className="text-xs text-zinc-500 mt-0.5">
        {actionTypeLabel(a.action_type)} · {formatWhen(a.created_at)}
      </p>
      {a.reason && <p className="text-sm text-zinc-700 mt-1">Why it is waiting: {a.reason}</p>}
      {!editing && <PayloadBox value={a.payload} />}
      {editing && (
        <textarea
          aria-label="Edited version"
          value={text}
          onChange={(e) => setText(e.target.value)}
          rows={10}
          className="mt-2 w-full rounded-md border border-zinc-300 p-2 font-mono text-xs"
        />
      )}
      {message && (
        <p role="alert" className="flex items-start gap-2 text-sm text-red-700 mt-2">
          <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" /> {message}
          <button type="button" onClick={() => void onChanged()} className="underline text-zinc-700 shrink-0">
            Refresh list
          </button>
        </p>
      )}
      <div className="flex flex-wrap gap-2 mt-3">
        {!editing && (
          <>
            <button disabled={busy} onClick={() => decide('approve')} className="px-3 py-1.5 rounded-md bg-zinc-900 text-white text-sm disabled:opacity-50">
              Approve
            </button>
            <button disabled={busy} onClick={() => setEditing(true)} className="px-3 py-1.5 rounded-md border border-zinc-300 text-sm">
              Edit
            </button>
            <button disabled={busy} onClick={() => decide('reject')} className="px-3 py-1.5 rounded-md border border-zinc-300 text-sm text-red-700">
              Reject
            </button>
          </>
        )}
        {editing && (
          <>
            <button disabled={busy} onClick={() => decide('edit')} className="px-3 py-1.5 rounded-md bg-zinc-900 text-white text-sm disabled:opacity-50">
              Send my version
            </button>
            <button disabled={busy} onClick={() => setEditing(false)} className="px-3 py-1.5 rounded-md border border-zinc-300 text-sm">
              Cancel edit
            </button>
          </>
        )}
      </div>
    </li>
  );
}

function DoneTab({items, onChanged}: {items: XanoCopilotAction[]; onChanged: () => Promise<void>}) {
  const [busyId, setBusyId] = useState<number | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  // reversibility is not on the row: look it up from the level catalogue (any business gives the same flags)
  const [reversible, setReversible] = useState<Record<string, boolean>>({});
  useEffect(() => {
    listCopilotLevels(0)
      .then((r) => setReversible(Object.fromEntries(r.types.map((t) => [t.key, t.reversible]))))
      .catch(() => setReversible({}));
  }, []);

  const seen = async (id: number) => {
    setBusyId(id);
    setMessage(null);
    try {
      await markCopilotActionSeen(id);
      await onChanged();
    } catch (e) {
      setMessage(serverText(e, 'Could not mark that as seen.'));
    } finally {
      setBusyId(null);
    }
  };

  if (items.length === 0) return <p className="text-sm text-zinc-500">The copilot has not done anything yet.</p>;
  return (
    <div>
      {message && (
        <p role="alert" className="text-sm text-red-700 mb-2">
          {message}
        </p>
      )}
      <ul className="flex flex-col gap-3">
        {items.map((a) => {
          const known = a.action_type != null && a.action_type in reversible;
          const undo = known ? undoState({reversible: reversible[a.action_type as string]}) : null;
          return (
            <li key={a.id} className="rounded-lg border border-zinc-200 bg-white p-4" id={`done-${a.id}`}>
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-sm font-medium text-zinc-900">
                    {a.summary || 'Copilot action'}
                    {isNewlyTold(a.status) && (
                      <span className="ml-2 rounded-full bg-blue-100 text-blue-800 text-xs px-2 py-0.5">New</span>
                    )}
                  </p>
                  <p className="text-xs text-zinc-500 mt-0.5">
                    {statusLabel(a.status)} · {actionTypeLabel(a.action_type)} · {formatWhen(a.updated_at ?? a.created_at)}
                  </p>
                  {a.reason && <p className="text-sm text-zinc-700 mt-1">{a.reason}</p>}
                </div>
                {isNewlyTold(a.status) && (
                  <button
                    disabled={busyId === a.id}
                    onClick={() => seen(a.id)}
                    className="shrink-0 px-3 py-1.5 rounded-md border border-zinc-300 text-sm disabled:opacity-50"
                  >
                    Mark as seen
                  </button>
                )}
              </div>
              {undo && undo.kind === 'cannot' && <p className="text-xs text-zinc-500 mt-2">{undo.label}</p>}
              {undo && undo.kind === 'undo' && (
                <div className="mt-2 flex items-center gap-2">
                  <button disabled title={undo.note} className="px-2 py-1 rounded-md border border-zinc-200 text-xs text-zinc-400">
                    {undo.label}
                  </button>
                  <span className="text-xs text-zinc-500">{undo.note}</span>
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function LevelsTab() {
  const [archs, setArchs] = useState<XanoJourneyArchitecture[]>([]);
  const [archId, setArchId] = useState(0);
  const [rows, setRows] = useState<XanoCopilotLevelRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listJourneyArchitectures()
      .then(setArchs)
      .catch(() => setArchs([]));
  }, []);

  const load = useCallback(async (id: number) => {
    setLoading(true);
    try {
      const r = await listCopilotLevels(id);
      setRows(r.types ?? []);
      setError(null);
    } catch (e) {
      setRows([]);
      setError(serverText(e, 'Unable to load approval levels right now.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load(archId);
  }, [archId, load]);

  return (
    <div>
      <label className="block text-sm text-zinc-700 mb-3">
        Business{' '}
        <select
          id="approval-levels-business"
          value={archId}
          onChange={(e) => setArchId(Number(e.target.value))}
          className="ml-2 rounded-md border border-zinc-300 px-2 py-1 text-sm"
        >
          <option value={0}>Maps outside any business</option>
          {archs.map((a) => (
            <option key={a.id} value={a.id}>
              {a.title || `Business ${a.id}`}
            </option>
          ))}
        </select>
      </label>
      {archId === 0 && (
        <p className="text-sm text-zinc-600 mb-3">
          Maps outside any business always use these safe defaults. Pick a business to change its levels.
        </p>
      )}
      {error && (
        <p role="alert" className="flex items-center gap-2 text-sm text-red-700 mb-3">
          <AlertCircle className="w-4 h-4" /> {error}
        </p>
      )}
      {loading ? (
        <Loader2 className="w-4 h-4 animate-spin text-zinc-400" />
      ) : (
        <ul className="flex flex-col gap-3">
          {rows.map((r) => (
            <LevelRow key={`${archId}-${r.key}`} row={r} archId={archId} onSaved={() => load(archId)} />
          ))}
        </ul>
      )}
    </div>
  );
}

function LevelRow({row, archId, onSaved}: {row: XanoCopilotLevelRow; archId: number; onSaved: () => Promise<void>}) {
  const locked = row.locked || row.person_only || archId === 0;
  const [level, setLevel] = useState<Level>(row.level);
  const [limit, setLimit] = useState(String(row.limit_amount ?? 0));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const dirty = level !== row.level || (row.has_limit && limit.trim() !== String(row.limit_amount ?? 0));
  const needsConfirm = levelChangeNeedsConfirm({reversible: row.reversible, touches: row.touches, level});
  const [confirming, setConfirming] = useState(false);

  const save = async (confirmed: boolean) => {
    setMessage(null);
    setSaved(false);
    const problem = limitProblem(limit, row.has_limit);
    if (problem) {
      setMessage(problem);
      return;
    }
    if (needsConfirm && !confirmed) {
      setConfirming(true);
      return;
    }
    setConfirming(false);
    setBusy(true);
    try {
      await setCopilotLevel({
        journey_architecture_id: archId,
        action_type: row.key,
        level,
        limit_amount: row.has_limit ? Number(limit.trim()) : 0,
        ...(needsConfirm ? {confirm_irreversible: true} : {}),
      });
      setSaved(true);
      await onSaved();
    } catch (e) {
      setMessage(serverText(e, 'That did not save. Nothing was changed.'));
    } finally {
      setBusy(false);
    }
  };

  return (
    <li className="rounded-lg border border-zinc-200 bg-white p-4" id={`level-${row.key}`}>
      <div className="flex items-center gap-2 flex-wrap">
        <p className="text-sm font-medium text-zinc-900">{row.name}</p>
        {locked && <span className="rounded-full bg-zinc-100 text-zinc-700 text-xs px-2 py-0.5">Locked</span>}
        {!row.wired && <span className="text-xs text-zinc-500">Not used by the copilot yet</span>}
      </div>
      <p className="text-xs text-zinc-500 mt-0.5">
        {TOUCHES_LABELS[row.touches] ?? row.touches}
        {row.reversible ? '' : " · Can't be undone"}
      </p>
      {row.person_only && <p className="text-sm text-zinc-700 mt-1">Only a person can do this.</p>}
      {row.suggest_down && (
        <p className="text-sm text-amber-800 mt-1">
          You approved most of these unchanged. Consider moving it down one level.
        </p>
      )}
      <div className="flex flex-wrap items-center gap-3 mt-3">
        <select
          aria-label={`Level for ${row.name}`}
          disabled={locked || busy}
          value={level}
          onChange={(e) => {
            setLevel(e.target.value as Level);
            setConfirming(false);
            setSaved(false);
          }}
          className="rounded-md border border-zinc-300 px-2 py-1 text-sm disabled:bg-zinc-100"
        >
          {(Object.keys(LEVEL_LABELS) as Level[]).map((l) => (
            <option key={l} value={l}>
              {LEVEL_LABELS[l]}
            </option>
          ))}
        </select>
        {row.has_limit && (
          <label className="text-sm text-zinc-700">
            Limit{' '}
            <input
              inputMode="numeric"
              disabled={locked || busy}
              value={limit}
              onChange={(e) => setLimit(e.target.value)}
              className="w-24 rounded-md border border-zinc-300 px-2 py-1 text-sm"
            />
          </label>
        )}
        {!locked && (
          <button
            disabled={busy || !dirty}
            onClick={() => save(false)}
            className="px-3 py-1.5 rounded-md bg-zinc-900 text-white text-sm disabled:opacity-40"
          >
            Save
          </button>
        )}
        {saved && !dirty && (
          <span className="flex items-center gap-1 text-sm text-green-700">
            <Check className="w-4 h-4" /> Saved
          </span>
        )}
      </div>
      {confirming && (
        <div role="alertdialog" className="mt-3 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
          <p>This can&apos;t be undone once the copilot does it. Let it do this without asking you first?</p>
          <div className="flex gap-2 mt-2">
            <button onClick={() => save(true)} className="px-3 py-1.5 rounded-md bg-zinc-900 text-white text-sm">
              Yes, allow it
            </button>
            <button onClick={() => setConfirming(false)} className="px-3 py-1.5 rounded-md border border-zinc-300 text-sm">
              Keep asking me
            </button>
          </div>
        </div>
      )}
      {message && (
        <p role="alert" className="flex items-start gap-2 text-sm text-red-700 mt-2">
          <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" /> {message}
        </p>
      )}
    </li>
  );
}
