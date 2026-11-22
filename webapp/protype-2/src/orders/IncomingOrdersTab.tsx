// Orders — "Incoming orders" tab: where orders from an outside system go
// (routing rules and order keys), what arrived in the last 24 hours, and
// the orders and jobs that need a person.
//
// An order key is shown ONCE, held only in this component's memory, and
// dropped the moment "Done" is pressed. It is never written to
// localStorage or anywhere else.
import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {AlertCircle, Check, Copy, KeyRound, Loader2, Plus, RefreshCw, Trash2} from 'lucide-react';
import {friendlyError, listJourneyMaps, XanoHttpError, type XanoJourneyMap} from '../xano';
import {
  getOrderSetup,
  saveOrderRoute,
  deleteOrderRoute,
  createOrderKey,
  clearOrderFlag,
  retryOrder,
  orderInboundUrl,
} from './ordersApi';
import {
  sourceNameProblem,
  mapsForPlan,
  outcomeLabel,
  flagLabel,
  type OrderSetup,
  type OrderRoute,
  type OrderNeedingPerson,
  type FlaggedJob,
  type OrderCounts,
} from './ordersModel';

const ADMIN_ONLY = 'Only an account admin can set up incoming orders.';

const EMPTY_COUNTS: OrderCounts = {created: 0, updated: 0, duplicate: 0, flagged: 0, no_route: 0, held: 0, refused: 0, failed: 0};

const isAccessError = (err: unknown) => err instanceof XanoHttpError && (err.status === 401 || err.status === 403);

function formatWhen(value: number | string | null | undefined): string {
  if (value === null || value === undefined || value === '' || value === 0) return '';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleString();
}

export default function IncomingOrdersTab() {
  const [setup, setSetup] = useState<OrderSetup | null>(null);
  const [maps, setMaps] = useState<XanoJourneyMap[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  /** The one-time key, in memory only. Cleared by "Done". */
  const [shownKey, setShownKey] = useState<{source: string; key: string} | null>(null);

  const load = useCallback(() => {
    setLoadError(null);
    // Map titles are a nice-to-have: without them a rule still shows "Map #id".
    Promise.all([getOrderSetup(), listJourneyMaps().catch(() => [] as XanoJourneyMap[])])
      .then(([setupRes, mapList]) => {
        setSetup(setupRes ?? null);
        setMaps(Array.isArray(mapList) ? mapList : []);
      })
      .catch((err) => setLoadError(isAccessError(err) ? ADMIN_ONLY : friendlyError(err, 'Unable to load incoming orders.')))
      .finally(() => setIsLoading(false));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const routes = setup?.routes ?? [];
  const needsPerson = setup?.needs_person ?? [];
  const flagged = setup?.flagged ?? [];
  const plans = setup?.plans ?? [];
  const planMaps = setup?.plan_maps ?? [];
  const counts = {...EMPTY_COUNTS, ...(setup?.last_24_hours ?? {})};

  const mapTitle = useCallback((id: number) => maps.find((m) => m.id === id)?.title || `Map #${id}`, [maps]);
  const planName = useCallback((id: number) => plans.find((p) => p.id === id)?.name || `Plan #${id}`, [plans]);

  if (isLoading) {
    return (
      <div className="flex items-center gap-2 p-4 text-sm text-zinc-500">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading…
      </div>
    );
  }

  if (!setup) {
    return <ErrorBanner message={loadError ?? 'Unable to load incoming orders.'} />;
  }

  return (
    <div className="space-y-8">
      <p className="text-sm text-zinc-500">
        Orders from your order system arrive here and become jobs in the plan you choose.
      </p>
      {loadError && <ErrorBanner message={loadError} />}
      {actionError && <ErrorBanner message={actionError} />}

      {/* 1 — Routing rules */}
      <section>
        <h2 className="text-sm font-semibold text-zinc-900">Routing rules</h2>
        <p className="mt-0.5 text-xs text-zinc-500">Each rule says which plan and map an order goes to.</p>

        {shownKey && <KeyPanel source={shownKey.source} orderKey={shownKey.key} onDone={() => setShownKey(null)} />}

        <div className="mt-2 overflow-x-auto rounded-md border border-zinc-200 bg-white">
          <table className="w-full text-left text-xs">
            <thead className="border-b border-zinc-200 bg-zinc-50 text-zinc-500">
              <tr>
                <th className="px-3 py-2 font-medium">Order system</th>
                <th className="px-3 py-2 font-medium">Fulfilment type</th>
                <th className="px-3 py-2 font-medium">Plan</th>
                <th className="px-3 py-2 font-medium">Map</th>
                <th className="px-3 py-2 font-medium">On / off</th>
                <th className="px-3 py-2 font-medium">Key</th>
                <th className="px-3 py-2" />
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-200">
              {routes.length === 0 && (
                <tr>
                  <td colSpan={7} className="p-4 text-sm text-zinc-500">
                    No routing rules yet. Add one below to start receiving orders.
                  </td>
                </tr>
              )}
              {routes.map((route) => (
                <RouteRow
                  key={route.route_id}
                  route={route}
                  planName={planName(route.workspace_id)}
                  mapTitle={mapTitle(route.journey_map_id)}
                  onChanged={load}
                  onError={setActionError}
                  onKey={(key) => {
                    setShownKey({source: route.source_system, key});
                    load();
                  }}
                />
              ))}
            </tbody>
          </table>
        </div>

        <AddRuleForm plans={plans} planMaps={planMaps} mapTitle={mapTitle} onAdded={load} />

        <div className="mt-4 rounded-md border border-zinc-200 bg-zinc-100 p-3 text-xs text-zinc-600">
          <p className="font-medium text-zinc-700">How to send an order</p>
          <p className="mt-1">
            Send a <code className="font-mono">POST</code> to:
          </p>
          <p className="mt-1 break-all font-mono text-zinc-800">{orderInboundUrl()}</p>
          <p className="mt-2">With this header:</p>
          <p className="mt-1 break-all font-mono text-zinc-800">Authorization: Bearer &lt;your order key&gt;</p>
          <p className="mt-2">And these JSON fields:</p>
          <ul className="mt-1 list-disc space-y-0.5 pl-4 font-mono text-zinc-800">
            <li>external_id</li>
            <li>order_number</li>
            <li>
              status <span className="font-sans text-zinc-500">(active or cancelled)</span>
            </li>
            <li>fulfilment</li>
            <li>starts_on</li>
            <li>ends_on</li>
            <li>lines [{'{external_id, name, quantity}'}]</li>
          </ul>
        </div>
      </section>

      {/* 2 — Last 24 hours */}
      <section>
        <h2 className="text-sm font-semibold text-zinc-900">Last 24 hours</h2>
        <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <Count label="New jobs" value={counts.created} />
          <Count label="Updated" value={counts.updated} />
          <Count label="Already received" value={counts.duplicate} />
          <Count label="Flagged to check" value={counts.flagged} />
          <Count label="No rule matched" value={counts.no_route} warn />
          <Count label="Held" value={counts.held} warn />
          <Count label="Refused" value={counts.refused} warn />
          <Count label="Could not be added" value={counts.failed} warn />
        </div>
      </section>

      {/* 3 — Orders that need you */}
      <section>
        <h2 className="text-sm font-semibold text-zinc-900">Orders that need you ({needsPerson.length})</h2>
        <ul className="mt-2 divide-y divide-zinc-200 rounded-md border border-zinc-200 bg-white">
          {needsPerson.length === 0 && <li className="p-4 text-sm text-zinc-500">No orders are waiting for you.</li>}
          {needsPerson.map((order) => (
            <NeedsPersonRow key={order.order_inbox_id} order={order} onChanged={load} />
          ))}
        </ul>
      </section>

      {/* 4 — Jobs to check */}
      <section>
        <h2 className="text-sm font-semibold text-zinc-900">Jobs to check ({flagged.length})</h2>
        <ul className="mt-2 divide-y divide-zinc-200 rounded-md border border-zinc-200 bg-white">
          {flagged.length === 0 && <li className="p-4 text-sm text-zinc-500">No jobs need checking.</li>}
          {flagged.map((job) => (
            <FlaggedRow key={job.work_item_id} job={job} onChanged={load} />
          ))}
        </ul>
      </section>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Routing rules
// ──────────────────────────────────────────────────────────────────────

function RouteRow({
  route,
  planName,
  mapTitle,
  onChanged,
  onError,
  onKey,
}: {
  route: OrderRoute;
  planName: string;
  mapTitle: string;
  onChanged: () => void;
  onError: (message: string | null) => void;
  onKey: (key: string) => void;
}) {
  const [confirming, setConfirming] = useState<'delete' | 'key' | null>(null);
  const [isBusy, setIsBusy] = useState(false);

  const run = async (work: () => Promise<void>, fallback: string) => {
    setIsBusy(true);
    onError(null);
    try {
      await work();
      setConfirming(null);
    } catch (err) {
      onError(isAccessError(err) ? ADMIN_ONLY : friendlyError(err, fallback));
    } finally {
      setIsBusy(false);
    }
  };

  const toggle = () =>
    run(async () => {
      await saveOrderRoute({
        route_id: route.route_id,
        source_system: route.source_system,
        match_fulfilment: route.match_fulfilment ?? '',
        workspace_id: route.workspace_id,
        journey_map_id: route.journey_map_id,
        disabled: route.is_enabled,
      });
      onChanged();
    }, 'Unable to change this rule.');

  return (
    <>
      <tr>
        <td className="px-3 py-2 font-medium text-zinc-900">{route.source_system}</td>
        <td className="px-3 py-2 text-zinc-700">{route.match_fulfilment || 'Any'}</td>
        <td className="px-3 py-2 text-zinc-700">{planName}</td>
        <td className="px-3 py-2 text-zinc-700">{mapTitle}</td>
        <td className="px-3 py-2">
          <button
            type="button"
            onClick={toggle}
            disabled={isBusy}
            title={route.is_enabled ? 'Turn this rule off' : 'Turn this rule on'}
            className={`rounded px-1.5 py-0.5 text-xs font-medium disabled:opacity-50 ${
              route.is_enabled ? 'bg-emerald-100 text-emerald-800 hover:bg-emerald-200' : 'bg-zinc-100 text-zinc-600 hover:bg-zinc-200'
            }`}
          >
            {route.is_enabled ? 'On' : 'Off'}
          </button>
        </td>
        <td className="px-3 py-2 text-zinc-700">{route.has_key ? 'Has a key' : 'No key yet'}</td>
        <td className="px-3 py-2">
          <div className="flex items-center justify-end gap-1">
            <button
              type="button"
              onClick={() => setConfirming('key')}
              disabled={isBusy}
              className="flex items-center gap-1 whitespace-nowrap rounded px-2 py-1 text-xs font-medium text-zinc-600 hover:bg-zinc-100 disabled:opacity-50"
            >
              <KeyRound className="h-3.5 w-3.5" />
              Create order key
            </button>
            <button
              type="button"
              title="Delete this rule"
              onClick={() => setConfirming('delete')}
              disabled={isBusy}
              className="rounded p-1.5 text-zinc-500 hover:bg-red-50 hover:text-red-600 disabled:opacity-50"
            >
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        </td>
      </tr>
      {confirming && (
        <tr>
          <td colSpan={7} className="bg-amber-50 px-3 py-2">
            <InlineConfirm
              message={
                confirming === 'key'
                  ? route.has_key
                    ? `Create a new order key for ${route.source_system}? This replaces the current key. The old one stops working.`
                    : `Create an order key for ${route.source_system}?`
                  : `Delete this rule? Orders from ${route.source_system} that only match this rule will stop being added.`
              }
              confirmLabel={confirming === 'key' ? 'Create key' : 'Delete rule'}
              isBusy={isBusy}
              onCancel={() => setConfirming(null)}
              onConfirm={() =>
                confirming === 'key'
                  ? run(async () => {
                      const res = await createOrderKey(route.source_system);
                      if (!res?.order_key) throw new Error('no key returned');
                      onKey(res.order_key);
                    }, 'Unable to create an order key.')
                  : run(async () => {
                      await deleteOrderRoute(route.route_id);
                      onChanged();
                    }, 'Unable to delete this rule.')
              }
            />
          </td>
        </tr>
      )}
    </>
  );
}

function KeyPanel({source, orderKey, onDone}: {source: string; orderKey: string; onDone: () => void}) {
  const [copied, setCopied] = useState(false);
  const [copyFailed, setCopyFailed] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(orderKey);
      setCopied(true);
      setCopyFailed(false);
    } catch {
      setCopyFailed(true);
    }
  };

  return (
    <div className="mt-2 rounded-md border border-amber-300 bg-amber-50 p-3">
      <p className="text-sm font-semibold text-amber-900">Order key for {source}</p>
      <p className="mt-0.5 text-xs text-amber-900">Copy it now. It will not be shown again.</p>
      <p className="mt-2 select-all break-all rounded border border-amber-200 bg-white p-2 font-mono text-xs text-zinc-900">{orderKey}</p>
      {copyFailed && <p className="mt-1 text-xs text-red-600">Could not copy. Select the key above and copy it by hand.</p>}
      <div className="mt-2 flex gap-2">
        <button
          type="button"
          onClick={copy}
          className="flex items-center gap-1 rounded bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-zinc-800"
        >
          {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
          {copied ? 'Copied' : 'Copy'}
        </button>
        <button type="button" onClick={onDone} className="rounded px-3 py-1.5 text-xs font-medium text-amber-900 hover:bg-amber-100">
          Done
        </button>
      </div>
    </div>
  );
}

function AddRuleForm({
  plans,
  planMaps,
  mapTitle,
  onAdded,
}: {
  plans: {id: number; name: string}[];
  planMaps: {workspace_id: number; journey_map_id: number}[];
  mapTitle: (id: number) => string;
  onAdded: () => void;
}) {
  const [source, setSource] = useState('');
  const [fulfilment, setFulfilment] = useState('');
  const [planId, setPlanId] = useState(0);
  const [mapId, setMapId] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  const mapOptions = useMemo(() => mapsForPlan(planId, planMaps), [planId, planMaps]);

  const submit = async () => {
    const sourceProblem = sourceNameProblem(source);
    if (sourceProblem) {
      setError(`Order system: ${sourceProblem}`);
      return;
    }
    if (!planId) {
      setError('Choose the plan these orders go to.');
      return;
    }
    if (!mapId || !mapOptions.includes(mapId)) {
      setError('Choose one of the maps that plan uses.');
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      await saveOrderRoute({
        source_system: source.trim(),
        match_fulfilment: fulfilment.trim(),
        workspace_id: planId,
        journey_map_id: mapId,
      });
      setSource('');
      setFulfilment('');
      setPlanId(0);
      setMapId(0);
      onAdded();
    } catch (err) {
      // Nothing is cleared on failure — what was typed stays in the form.
      setError(isAccessError(err) ? ADMIN_ONLY : friendlyError(err, 'Unable to add this rule. What you typed is kept.'));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="mt-3 rounded-md border border-dashed border-zinc-300 bg-white p-3">
      <div className="grid grid-cols-2 gap-2">
        <input
          value={source}
          onChange={(e) => setSource(e.target.value)}
          placeholder="Order system, e.g. my-shop"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm"
        />
        <input
          value={fulfilment}
          onChange={(e) => setFulfilment(e.target.value)}
          placeholder="Fulfilment type (leave empty for any)"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm"
        />
        <select
          value={planId}
          onChange={(e) => {
            setPlanId(Number(e.target.value));
            setMapId(0);
          }}
          aria-label="Plan"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm"
        >
          <option value={0}>Choose a plan…</option>
          {plans.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
        <select
          value={mapId}
          onChange={(e) => setMapId(Number(e.target.value))}
          disabled={!planId || mapOptions.length === 0}
          aria-label="Map"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm disabled:bg-zinc-50 disabled:text-zinc-400"
        >
          <option value={0}>{!planId ? 'Choose a plan first' : mapOptions.length === 0 ? 'This plan has no maps yet' : 'Choose a map…'}</option>
          {mapOptions.map((id) => (
            <option key={id} value={id}>
              {mapTitle(id)}
            </option>
          ))}
        </select>
      </div>
      {plans.length === 0 && <p className="mt-2 text-xs text-zinc-500">You need a plan before you can add a rule.</p>}
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
      <button
        type="button"
        onClick={submit}
        disabled={isSaving || !source.trim()}
        className="mt-2 flex items-center gap-1 rounded bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
      >
        {isSaving ? <Loader2 className="h-3 w-3 animate-spin" /> : <Plus className="h-3 w-3" />}
        Add rule
      </button>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Orders that need you / Jobs to check
// ──────────────────────────────────────────────────────────────────────

function NeedsPersonRow({order, onChanged}: {order: OrderNeedingPerson; onChanged: () => void}) {
  const [isBusy, setIsBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<string | null>(null);

  const retry = async () => {
    setIsBusy(true);
    setError(null);
    setResult(null);
    try {
      const res = await retryOrder(order.order_inbox_id);
      setResult(`${outcomeLabel(res?.outcome ?? '')}${res?.detail ? ` — ${res.detail}` : ''}`);
      onChanged();
    } catch (err) {
      setError(isAccessError(err) ? ADMIN_ONLY : friendlyError(err, 'Unable to try this order again.'));
    } finally {
      setIsBusy(false);
    }
  };

  const when = formatWhen(order.received_at);

  return (
    <li className="p-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-medium text-zinc-900">Order {order.order_number || order.external_id}</span>
            <span className="rounded bg-amber-100 px-1.5 py-0.5 text-xs text-amber-800">{outcomeLabel(order.outcome)}</span>
          </div>
          <div className="text-xs text-zinc-500">
            {order.source_system}
            {when ? ` · received ${when}` : ''}
          </div>
          {order.detail && <p className="mt-1 break-words text-xs text-zinc-700">{order.detail}</p>}
        </div>
        <button
          type="button"
          onClick={retry}
          disabled={isBusy}
          className="flex shrink-0 items-center gap-1 rounded border border-zinc-300 px-2 py-1 text-xs font-medium text-zinc-700 hover:bg-zinc-100 disabled:opacity-50"
        >
          {isBusy ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />}
          Try again
        </button>
      </div>
      {result && <p className="mt-1 text-xs text-zinc-600">Result: {result}</p>}
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
    </li>
  );
}

function FlaggedRow({job, onChanged}: {job: FlaggedJob; onChanged: () => void}) {
  const [confirming, setConfirming] = useState(false);
  const [isBusy, setIsBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const clear = async () => {
    setIsBusy(true);
    setError(null);
    try {
      await clearOrderFlag(job.work_item_id);
      setConfirming(false);
      onChanged();
    } catch (err) {
      setError(isAccessError(err) ? ADMIN_ONLY : friendlyError(err, 'Unable to mark this job as handled.'));
    } finally {
      setIsBusy(false);
    }
  };

  return (
    <li className="p-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-medium text-zinc-900">Order {job.order_number || `job #${job.work_item_id}`}</span>
            <span className="rounded bg-amber-100 px-1.5 py-0.5 text-xs text-amber-800">{flagLabel(job.order_flag)}</span>
          </div>
          <div className="text-xs text-zinc-500">
            {job.source_system}
            {job.starts_on ? ` · starts ${job.starts_on}` : ''}
          </div>
        </div>
        {!confirming && (
          <button
            type="button"
            onClick={() => setConfirming(true)}
            className="shrink-0 rounded border border-zinc-300 px-2 py-1 text-xs font-medium text-zinc-700 hover:bg-zinc-100"
          >
            Mark as handled
          </button>
        )}
      </div>
      {confirming && (
        <div className="mt-2 rounded-md bg-amber-50 p-2">
          <InlineConfirm
            message="Mark this job as handled? It leaves this list. The job itself is not changed."
            confirmLabel="Mark as handled"
            isBusy={isBusy}
            onCancel={() => setConfirming(false)}
            onConfirm={clear}
          />
        </div>
      )}
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
    </li>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Shared bits
// ──────────────────────────────────────────────────────────────────────

function InlineConfirm({
  message,
  confirmLabel,
  isBusy,
  onConfirm,
  onCancel,
}: {
  message: string;
  confirmLabel: string;
  isBusy: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-2 text-xs text-amber-900">
      <span>{message}</span>
      <button
        type="button"
        onClick={onConfirm}
        disabled={isBusy}
        className="flex items-center gap-1 rounded bg-zinc-900 px-2 py-1 font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
      >
        {isBusy && <Loader2 className="h-3 w-3 animate-spin" />}
        {confirmLabel}
      </button>
      <button type="button" onClick={onCancel} disabled={isBusy} className="rounded px-2 py-1 text-zinc-600 hover:bg-amber-100">
        Cancel
      </button>
    </div>
  );
}

function Count({label, value, warn = false}: {label: string; value: number; warn?: boolean}) {
  const n = Number(value) || 0;
  return (
    <div className="rounded-md border border-zinc-200 bg-white p-2">
      <div className={`text-lg font-semibold ${warn && n > 0 ? 'text-amber-700' : 'text-zinc-900'}`}>{n}</div>
      <div className="text-xs text-zinc-500">{label}</div>
    </div>
  );
}

function ErrorBanner({message}: {message: string}) {
  return (
    <div className="mt-2 flex items-start gap-2 rounded-md border border-red-200 bg-red-50 p-2 text-xs text-red-700">
      <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
      <span>{message}</span>
    </div>
  );
}
