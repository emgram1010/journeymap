import React, {useCallback, useEffect, useState} from 'react';
import {AlertCircle, Loader2, Plug} from 'lucide-react';
import {addCopilotConnection, friendlyError, listCopilotConnections, setCopilotConnectionLogin, switchCopilotConnection} from '../xano';
import {connectionEntryProblem, connectionStateLabel, loginProblem, type ConnectionRow} from './connectionsModel';

/**
 * COP-6 stories 01 + 02 - the outside systems this account could connect, which are on for this
 * business, and each one's login. A login is WRITE-ONLY: it can be saved, replaced or removed, and
 * the screen only ever knows whether one is stored. The typed value is cleared once it is saved,
 * kept on a refusal (CLAUDE.md), and never logged.
 */
// The server's own sentence, never the raw technical string (friendlyError).
const errText = (e: unknown, fallback: string) => friendlyError(e, fallback);

function LoginForm({archId, row, onChanged}: {archId: number; row: ConnectionRow; onChanged: () => Promise<void>}) {
  const [login, setLogin] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const save = async () => {
    const problem = loginProblem(login);
    if (problem) {
      setMsg(problem);
      return;
    }
    setBusy(true);
    setMsg(null);
    try {
      await setCopilotConnectionLogin({journey_architecture_id: archId, connection_id: row.id, login});
      setLogin('');
      await onChanged();
    } catch (e) {
      setMsg(errText(e, 'The login did not save. Nothing was changed.'));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    if (!window.confirm(`Remove the login for ${row.name}? It stops working at once and the connection is switched off for this business.`)) return;
    setBusy(true);
    setMsg(null);
    try {
      await setCopilotConnectionLogin({journey_architecture_id: archId, connection_id: row.id, remove: true});
      await onChanged();
    } catch (e) {
      setMsg(errText(e, 'The login was not removed. Nothing was changed.'));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="mt-2">
      <div className="flex flex-wrap items-center gap-2">
        <input
          type="password"
          autoComplete="new-password"
          aria-label={`Login for ${row.name}`}
          placeholder={row.has_login ? 'A login is saved - type a new one to replace it' : 'Login or key for this business'}
          value={login}
          onChange={(e) => setLogin(e.target.value)}
          className="rounded-md border border-zinc-300 px-2 py-1 text-sm flex-1 min-w-[14rem]"
        />
        <button onClick={save} disabled={busy} className="px-3 py-1.5 rounded-md border border-zinc-300 text-sm disabled:opacity-50">
          {row.has_login ? 'Replace login' : 'Save login'}
        </button>
        {row.has_login && (
          <button onClick={remove} disabled={busy} className="px-3 py-1.5 rounded-md border border-red-300 text-red-700 text-sm disabled:opacity-50">
            Remove login
          </button>
        )}
      </div>
      <p className="text-xs text-zinc-500 mt-1">Saved logins are encrypted and can never be shown again - not here, not to the copilot.</p>
      {msg && (
        <p role="alert" className="flex items-start gap-2 text-sm text-red-700 mt-1">
          <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" /> {msg}
        </p>
      )}
    </div>
  );
}

export default function ConnectionsSection({archId}: {archId: number}) {
  const [rows, setRows] = useState<ConnectionRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [key, setKey] = useState('');
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const r = await listCopilotConnections(archId);
      setRows(r.connections ?? []);
      setError(null);
    } catch (e) {
      setRows([]);
      setError(errText(e, 'Unable to load connections right now.'));
    } finally {
      setLoading(false);
    }
  }, [archId]);

  useEffect(() => {
    void load();
  }, [load]);

  const add = async () => {
    // The owner's typing is kept on any refusal (CLAUDE.md).
    const problem = connectionEntryProblem(key, name, description);
    if (problem) {
      setFormError(problem);
      return;
    }
    setBusy(true);
    setFormError(null);
    try {
      await addCopilotConnection({key: key.trim(), name: name.trim(), description: description.trim()});
      setKey('');
      setName('');
      setDescription('');
      await load();
    } catch (e) {
      setFormError(errText(e, 'That did not save. Nothing was changed.'));
    } finally {
      setBusy(false);
    }
  };

  const toggle = async (row: ConnectionRow) => {
    setError(null);
    try {
      await switchCopilotConnection({journey_architecture_id: archId, connection_id: row.id, is_on: !row.is_on});
      await load();
    } catch (e) {
      setError(errText(e, 'That did not change. Nothing was changed.'));
    }
  };

  return (
    <section className="mt-8" aria-labelledby="connections-heading">
      <h3 id="connections-heading" className="flex items-center gap-2 text-sm font-semibold text-zinc-900">
        <Plug className="w-4 h-4" /> Connections
      </h3>
      <p className="text-sm text-zinc-600 mt-1">
        Outside systems the copilot could use for this business. A connection needs its own login for each business before it can be switched on.
      </p>
      {error && (
        <p role="alert" className="flex items-center gap-2 text-sm text-red-700 mt-2">
          <AlertCircle className="w-4 h-4" /> {error}
        </p>
      )}
      {loading ? (
        <Loader2 className="w-4 h-4 animate-spin text-zinc-400 mt-3" />
      ) : rows.length === 0 ? (
        <p className="text-sm text-zinc-500 mt-3">No connections yet.</p>
      ) : (
        <ul className="flex flex-col gap-2 mt-3">
          {rows.map((r) => (
            <li key={r.id} className="rounded-lg border border-zinc-200 bg-white p-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-sm font-medium text-zinc-900">{r.name}</p>
                  {r.description && <p className="text-xs text-zinc-500">{r.description}</p>}
                  <p className="text-xs text-zinc-700 mt-1">{connectionStateLabel(r)}</p>
                </div>
                <button
                  onClick={() => toggle(r)}
                  disabled={!r.is_on && !r.has_login}
                  title={!r.is_on && !r.has_login ? 'Needs a login for this business first' : undefined}
                  className="px-3 py-1.5 rounded-md border border-zinc-300 text-sm disabled:opacity-50"
                >
                  {r.is_on ? 'Switch off' : 'Switch on'}
                </button>
              </div>
              <LoginForm archId={archId} row={r} onChanged={load} />
            </li>
          ))}
        </ul>
      )}
      <div className="mt-4 rounded-lg border border-dashed border-zinc-300 p-3">
        <p className="text-sm font-medium text-zinc-900">Add a connection</p>
        <div className="flex flex-wrap gap-2 mt-2">
          <input aria-label="Connection key" placeholder="key, e.g. booking-tool" value={key} onChange={(e) => setKey(e.target.value)} className="rounded-md border border-zinc-300 px-2 py-1 text-sm" />
          <input aria-label="Connection name" placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} className="rounded-md border border-zinc-300 px-2 py-1 text-sm" />
          <input aria-label="Connection description" placeholder="What it is (optional)" value={description} onChange={(e) => setDescription(e.target.value)} className="rounded-md border border-zinc-300 px-2 py-1 text-sm flex-1 min-w-[12rem]" />
          <button onClick={add} disabled={busy} className="px-3 py-1.5 rounded-md bg-zinc-900 text-white text-sm disabled:opacity-50">
            Add
          </button>
        </div>
        {formError && (
          <p role="alert" className="flex items-start gap-2 text-sm text-red-700 mt-2">
            <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" /> {formError}
          </p>
        )}
      </div>
    </section>
  );
}
