// CAT-1 (US-CAT-1-04) — Settings screen: "Items" and "Methods". Any
// signed-in member can add; only an admin can deactivate, reactivate or
// delete (D-1) — gated here with `canManageTeam`, the same function
// AppLayout's own "Manage users" item and its route guard already use,
// so this page cannot drift from that answer either.
//
// Rejected saves show the friendly server sentence (XanoHttpError's
// `serverMessage`, which already carries the (E-CAT-XXX) suffix) and
// keep the user's typing — the draft state is never cleared on failure.
import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {Boxes, Plus, Loader2, AlertCircle, Power, PowerOff, Trash2} from 'lucide-react';
import {useAuth} from '../AuthContext';
import {canManageTeam} from '../team/teamModel';
import {listJourneyMaps, type XanoJourneyMap} from '../xano';
import {
  listItemTypes,
  createItemType,
  updateItemType,
  deactivateItemType,
  deleteItemType,
  listMethods,
  createMethod,
  updateMethod,
  deactivateMethod,
  deleteMethod,
} from './catalogApi';
import {normaliseKey, validateKey, validateLabel, validateUnit, validateSizeLabel, validateExternalRef} from './catalogValidation';
import type {ItemType, CatalogMethod, CatalogUnit} from './catalogTypes';

type Tab = 'items' | 'methods';

function friendlyError(err: unknown, fallback: string): string {
  const withServerMessage = err as {serverMessage?: string | null} | null;
  return withServerMessage?.serverMessage || fallback;
}

/** Confirms a destructive action with the plain-language explanation US-CAT-1-04 asks for. */
function ConfirmDialog({
  title,
  body,
  confirmLabel,
  onConfirm,
  onCancel,
}: {
  title: string;
  body: string;
  confirmLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-lg bg-white p-5 shadow-xl">
        <h3 className="text-sm font-semibold text-zinc-900">{title}</h3>
        <p className="mt-2 text-sm text-zinc-600">{body}</p>
        <div className="mt-4 flex justify-end gap-2">
          <button
            type="button"
            onClick={onCancel}
            className="rounded-md px-3 py-1.5 text-sm font-medium text-zinc-600 hover:bg-zinc-100"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            className="rounded-md bg-zinc-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-zinc-800"
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function CatalogPage() {
  const {user} = useAuth();
  const isAdmin = canManageTeam(user);
  const [tab, setTab] = useState<Tab>('items');

  return (
    <div className="min-h-screen bg-zinc-50 font-sans">
      <div className="mx-auto max-w-3xl px-6 py-8">
        <div className="flex items-center gap-2">
          <Boxes className="h-5 w-5 text-zinc-500" />
          <h1 className="text-lg font-semibold text-zinc-900">Catalog</h1>
        </div>
        <p className="mt-1 text-sm text-zinc-500">
          The items you process and the methods you process them by. Maps reference these — they never redefine
          them.
        </p>

        <div className="mt-6 flex gap-1 border-b border-zinc-200">
          {(['items', 'methods'] as Tab[]).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              className={`px-3 py-2 text-sm font-medium capitalize ${
                tab === t ? 'border-b-2 border-zinc-900 text-zinc-900' : 'text-zinc-500 hover:text-zinc-700'
              }`}
            >
              {t}
            </button>
          ))}
        </div>

        <div className="mt-6">
          {tab === 'items' ? <ItemTypesTab isAdmin={isAdmin} /> : <MethodsTab isAdmin={isAdmin} />}
        </div>
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Items
// ──────────────────────────────────────────────────────────────────────

const UNIT_OPTIONS: CatalogUnit[] = ['each', 'set', 'pair'];

function ItemTypesTab({isAdmin}: {isAdmin: boolean}) {
  const [items, setItems] = useState<ItemType[]>([]);
  const [methods, setMethods] = useState<CatalogMethod[]>([]);
  const [showInactive, setShowInactive] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [listError, setListError] = useState<string | null>(null);
  const [pendingDeactivate, setPendingDeactivate] = useState<ItemType | null>(null);

  const load = useCallback(() => {
    setIsLoading(true);
    setListError(null);
    Promise.all([listItemTypes(showInactive), listMethods(true)])
      .then(([itemRes, methodRes]) => {
        setItems(itemRes.items);
        setMethods(methodRes.methods);
      })
      .catch((err) => setListError(friendlyError(err, 'Unable to load items.')))
      .finally(() => setIsLoading(false));
  }, [showInactive]);

  useEffect(() => {
    load();
  }, [load]);

  const activeMethods = useMemo(() => methods.filter((m) => m.is_active), [methods]);

  return (
    <div>
      <ListToolbar showInactive={showInactive} onToggle={setShowInactive} />

      {listError && <ErrorBanner message={listError} />}

      {isLoading ? (
        <LoadingRow />
      ) : (
        <ul className="divide-y divide-zinc-200 rounded-md border border-zinc-200 bg-white">
          {items.length === 0 && <li className="p-4 text-sm text-zinc-500">No items yet.</li>}
          {items.map((item) => (
            <ItemTypeRow
              key={item.id}
              item={item}
              methods={methods}
              isAdmin={isAdmin}
              onSaved={load}
              onRequestDeactivate={() => setPendingDeactivate(item)}
              onDeleted={load}
            />
          ))}
        </ul>
      )}

      <AddItemTypeForm methods={activeMethods} onCreated={load} />

      {pendingDeactivate && (
        <ConfirmDialog
          title={pendingDeactivate.is_active ? 'Deactivate this item?' : 'Reactivate this item?'}
          body={
            pendingDeactivate.is_active
              ? 'Hidden from new maps; published versions keep it.'
              : 'It becomes available to new maps again.'
          }
          confirmLabel={pendingDeactivate.is_active ? 'Deactivate' : 'Reactivate'}
          onCancel={() => setPendingDeactivate(null)}
          onConfirm={async () => {
            const target = pendingDeactivate;
            setPendingDeactivate(null);
            if (!target) return;
            try {
              if (target.is_active) {
                await deactivateItemType(target.id);
              } else {
                await updateItemType(target.id, {is_active: true});
              }
              load();
            } catch (err) {
              setListError(friendlyError(err, 'Unable to change active status.'));
            }
          }}
        />
      )}
    </div>
  );
}

function ItemTypeRow({
  item,
  methods,
  isAdmin,
  onSaved,
  onRequestDeactivate,
  onDeleted,
}: {
  item: ItemType;
  methods: CatalogMethod[];
  isAdmin: boolean;
  onSaved: () => void;
  onRequestDeactivate: () => void;
  onDeleted: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState({
    label: item.label,
    unit: item.unit,
    default_method_id: item.default_method_id,
    size_label: item.size_label ?? '',
    external_ref: item.external_ref ?? '',
  });
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  const save = async () => {
    const labelCheck = validateLabel(draft.label);
    const unitCheck = validateUnit(draft.unit);
    const sizeCheck = validateSizeLabel(draft.size_label);
    const extCheck = validateExternalRef(draft.external_ref);
    const firstInvalid = [labelCheck, unitCheck, sizeCheck, extCheck].find((r) => !r.valid);
    if (firstInvalid && !firstInvalid.valid) {
      setError('Check the highlighted field — the save was not sent.');
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      await updateItemType(item.id, {
        label: draft.label,
        unit: draft.unit,
        default_method_id: draft.default_method_id,
        size_label: draft.size_label,
        external_ref: draft.external_ref,
      });
      setEditing(false);
      onSaved();
    } catch (err) {
      setError(friendlyError(err, 'Unable to save. Your changes are kept below.'));
    } finally {
      setIsSaving(false);
    }
  };

  if (!editing) {
    return (
      <li className="flex items-center justify-between gap-3 p-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="truncate text-sm font-medium text-zinc-900">{item.label}</span>
            {!item.is_active && (
              <span className="rounded bg-zinc-100 px-1.5 py-0.5 text-xs text-zinc-500">inactive</span>
            )}
          </div>
          <div className="truncate text-xs text-zinc-500">
            {item.key} · {item.unit}
            {item.size_label ? ` · ${item.size_label}` : ''}
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <button
            type="button"
            onClick={() => setEditing(true)}
            className="rounded px-2 py-1 text-xs font-medium text-zinc-600 hover:bg-zinc-100"
          >
            Edit
          </button>
          {isAdmin && (
            <>
              <button
                type="button"
                title={item.is_active ? 'Deactivate' : 'Reactivate'}
                onClick={onRequestDeactivate}
                className="rounded p-1.5 text-zinc-500 hover:bg-zinc-100"
              >
                {item.is_active ? <PowerOff className="h-4 w-4" /> : <Power className="h-4 w-4" />}
              </button>
              <button
                type="button"
                title="Delete"
                onClick={async () => {
                  try {
                    await deleteItemType(item.id);
                    onDeleted();
                  } catch (err) {
                    setError(friendlyError(err, 'Unable to delete.'));
                  }
                }}
                className="rounded p-1.5 text-zinc-500 hover:bg-red-50 hover:text-red-600"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </>
          )}
        </div>
      </li>
    );
  }

  return (
    <li className="p-3">
      <div className="grid grid-cols-2 gap-2">
        <input
          value={draft.label}
          onChange={(e) => setDraft({...draft, label: e.target.value})}
          placeholder="Label"
          className="col-span-2 rounded border border-zinc-300 px-2 py-1 text-sm"
        />
        <select
          value={draft.unit}
          onChange={(e) => setDraft({...draft, unit: e.target.value as CatalogUnit})}
          className="rounded border border-zinc-300 px-2 py-1 text-sm"
        >
          {UNIT_OPTIONS.map((u) => (
            <option key={u} value={u}>
              {u}
            </option>
          ))}
        </select>
        <select
          value={draft.default_method_id}
          onChange={(e) => setDraft({...draft, default_method_id: Number(e.target.value)})}
          className="rounded border border-zinc-300 px-2 py-1 text-sm"
        >
          <option value={0}>No default method</option>
          {methods.map((m) => (
            <option key={m.id} value={m.id}>
              {m.label}
            </option>
          ))}
        </select>
        <input
          value={draft.size_label}
          onChange={(e) => setDraft({...draft, size_label: e.target.value})}
          placeholder="Size label (grouping only, e.g. 6ft)"
          className="rounded border border-zinc-300 px-2 py-1 text-sm"
        />
        <input
          value={draft.external_ref}
          onChange={(e) => setDraft({...draft, external_ref: e.target.value})}
          placeholder="External ref (booking SKU)"
          className="rounded border border-zinc-300 px-2 py-1 text-sm"
        />
      </div>
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
      <div className="mt-2 flex justify-end gap-2">
        <button
          type="button"
          onClick={() => {
            setEditing(false);
            setError(null);
          }}
          className="rounded px-2 py-1 text-xs text-zinc-500 hover:bg-zinc-100"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={save}
          disabled={isSaving}
          className="flex items-center gap-1 rounded bg-zinc-900 px-2 py-1 text-xs font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
        >
          {isSaving && <Loader2 className="h-3 w-3 animate-spin" />}
          Save
        </button>
      </div>
    </li>
  );
}

function AddItemTypeForm({methods, onCreated}: {methods: CatalogMethod[]; onCreated: () => void}) {
  const [label, setLabel] = useState('');
  const [key, setKey] = useState('');
  const [keyTouched, setKeyTouched] = useState(false);
  const [unit, setUnit] = useState<CatalogUnit>('each');
  const [defaultMethodId, setDefaultMethodId] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  // Key auto-suggested from the label, editable (US-CAT-1-04) — stops
  // suggesting the moment the user types into the key field directly.
  useEffect(() => {
    if (!keyTouched) setKey(normaliseKey(label));
  }, [label, keyTouched]);

  const submit = async () => {
    const keyCheck = validateKey(key);
    const labelCheck = validateLabel(label);
    if (!keyCheck.valid) {
      setError('Fix the key — letters, numbers and hyphens only, 2 to 40 characters.');
      return;
    }
    if (!labelCheck.valid) {
      setError('Give it a name up to 80 characters, with no HTML.');
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      await createItemType({key, label, unit, default_method_id: defaultMethodId || undefined});
      setLabel('');
      setKey('');
      setKeyTouched(false);
      setUnit('each');
      setDefaultMethodId(0);
      onCreated();
    } catch (err) {
      setError(friendlyError(err, 'Unable to create this item.'));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="mt-4 rounded-md border border-dashed border-zinc-300 bg-white p-3">
      <div className="grid grid-cols-2 gap-2">
        <input
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          placeholder="Label, e.g. 6-ft Banquet Table"
          className="col-span-2 rounded border border-zinc-300 px-2 py-1.5 text-sm"
        />
        <input
          value={key}
          onChange={(e) => {
            setKeyTouched(true);
            setKey(e.target.value);
          }}
          placeholder="key-like-this"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm font-mono"
        />
        <select
          value={unit}
          onChange={(e) => setUnit(e.target.value as CatalogUnit)}
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm"
        >
          {UNIT_OPTIONS.map((u) => (
            <option key={u} value={u}>
              {u}
            </option>
          ))}
        </select>
        <select
          value={defaultMethodId}
          onChange={(e) => setDefaultMethodId(Number(e.target.value))}
          className="col-span-2 rounded border border-zinc-300 px-2 py-1.5 text-sm"
        >
          <option value={0}>No default method</option>
          {methods.map((m) => (
            <option key={m.id} value={m.id}>
              {m.label}
            </option>
          ))}
        </select>
      </div>
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
      <button
        type="button"
        onClick={submit}
        disabled={isSaving || !label.trim()}
        className="mt-2 flex items-center gap-1 rounded bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
      >
        {isSaving ? <Loader2 className="h-3 w-3 animate-spin" /> : <Plus className="h-3 w-3" />}
        Add item
      </button>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Methods
// ──────────────────────────────────────────────────────────────────────

function MethodsTab({isAdmin}: {isAdmin: boolean}) {
  const [methods, setMethods] = useState<CatalogMethod[]>([]);
  const [maps, setMaps] = useState<XanoJourneyMap[]>([]);
  const [showInactive, setShowInactive] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [listError, setListError] = useState<string | null>(null);
  const [pendingDeactivate, setPendingDeactivate] = useState<CatalogMethod | null>(null);

  const load = useCallback(() => {
    setIsLoading(true);
    setListError(null);
    Promise.all([listMethods(showInactive), listJourneyMaps()])
      .then(([methodRes, mapList]) => {
        setMethods(methodRes.methods);
        // Atomic maps first (the level a method's sub-journey normally
        // targets), per US-CAT-1-04.
        setMaps([...mapList].sort((a, b) => (a.map_level === 'atomic' ? -1 : 1) - (b.map_level === 'atomic' ? -1 : 1)));
      })
      .catch((err) => setListError(friendlyError(err, 'Unable to load methods.')))
      .finally(() => setIsLoading(false));
  }, [showInactive]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div>
      <ListToolbar showInactive={showInactive} onToggle={setShowInactive} />

      {listError && <ErrorBanner message={listError} />}

      {isLoading ? (
        <LoadingRow />
      ) : (
        <ul className="divide-y divide-zinc-200 rounded-md border border-zinc-200 bg-white">
          {methods.length === 0 && <li className="p-4 text-sm text-zinc-500">No methods yet.</li>}
          {methods.map((method) => (
            <MethodRow
              key={method.id}
              method={method}
              maps={maps}
              isAdmin={isAdmin}
              onSaved={load}
              onRequestDeactivate={() => setPendingDeactivate(method)}
              onDeleted={load}
            />
          ))}
        </ul>
      )}

      <AddMethodForm maps={maps} onCreated={load} />

      {pendingDeactivate && (
        <ConfirmDialog
          title={pendingDeactivate.is_active ? 'Deactivate this method?' : 'Reactivate this method?'}
          body={
            pendingDeactivate.is_active
              ? 'Hidden from new maps; published versions keep it.'
              : 'It becomes available to new maps again.'
          }
          confirmLabel={pendingDeactivate.is_active ? 'Deactivate' : 'Reactivate'}
          onCancel={() => setPendingDeactivate(null)}
          onConfirm={async () => {
            const target = pendingDeactivate;
            setPendingDeactivate(null);
            if (!target) return;
            try {
              if (target.is_active) {
                await deactivateMethod(target.id);
              } else {
                await updateMethod(target.id, {is_active: true});
              }
              load();
            } catch (err) {
              setListError(friendlyError(err, 'Unable to change active status.'));
            }
          }}
        />
      )}
    </div>
  );
}

function MethodRow({
  method,
  maps,
  isAdmin,
  onSaved,
  onRequestDeactivate,
  onDeleted,
}: {
  method: CatalogMethod;
  maps: XanoJourneyMap[];
  isAdmin: boolean;
  onSaved: () => void;
  onRequestDeactivate: () => void;
  onDeleted: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState({label: method.label, sub_journey_map_id: method.sub_journey_map_id});
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  const save = async () => {
    const labelCheck = validateLabel(draft.label);
    if (!labelCheck.valid) {
      setError('Give it a name up to 80 characters, with no HTML.');
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      await updateMethod(method.id, {label: draft.label, sub_journey_map_id: draft.sub_journey_map_id});
      setEditing(false);
      onSaved();
    } catch (err) {
      setError(friendlyError(err, 'Unable to save. Your changes are kept below.'));
    } finally {
      setIsSaving(false);
    }
  };

  const subJourneyTitle = maps.find((m) => m.id === method.sub_journey_map_id)?.title;

  if (!editing) {
    return (
      <li className="flex items-center justify-between gap-3 p-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="truncate text-sm font-medium text-zinc-900">{method.label}</span>
            {!method.is_active && (
              <span className="rounded bg-zinc-100 px-1.5 py-0.5 text-xs text-zinc-500">inactive</span>
            )}
          </div>
          <div className="truncate text-xs text-zinc-500">
            {method.key}
            {method.sub_journey_map_id ? ` · steps: ${subJourneyTitle ?? `map #${method.sub_journey_map_id}`}` : ' · no sub-journey'}
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <button
            type="button"
            onClick={() => setEditing(true)}
            className="rounded px-2 py-1 text-xs font-medium text-zinc-600 hover:bg-zinc-100"
          >
            Edit
          </button>
          {isAdmin && (
            <>
              <button
                type="button"
                title={method.is_active ? 'Deactivate' : 'Reactivate'}
                onClick={onRequestDeactivate}
                className="rounded p-1.5 text-zinc-500 hover:bg-zinc-100"
              >
                {method.is_active ? <PowerOff className="h-4 w-4" /> : <Power className="h-4 w-4" />}
              </button>
              <button
                type="button"
                title="Delete"
                onClick={async () => {
                  try {
                    await deleteMethod(method.id);
                    onDeleted();
                  } catch (err) {
                    setError(friendlyError(err, 'Unable to delete.'));
                  }
                }}
                className="rounded p-1.5 text-zinc-500 hover:bg-red-50 hover:text-red-600"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </>
          )}
        </div>
      </li>
    );
  }

  return (
    <li className="p-3">
      <div className="grid grid-cols-2 gap-2">
        <input
          value={draft.label}
          onChange={(e) => setDraft({...draft, label: e.target.value})}
          placeholder="Label"
          className="col-span-2 rounded border border-zinc-300 px-2 py-1 text-sm"
        />
        <select
          value={draft.sub_journey_map_id}
          onChange={(e) => setDraft({...draft, sub_journey_map_id: Number(e.target.value)})}
          className="col-span-2 rounded border border-zinc-300 px-2 py-1 text-sm"
        >
          <option value={0}>No sub-journey (same steps, different rate)</option>
          {maps.map((m) => (
            <option key={m.id} value={m.id}>
              {m.title}
              {m.map_level === 'atomic' ? '' : ` (${m.map_level ?? 'unset level'})`}
            </option>
          ))}
        </select>
      </div>
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
      <div className="mt-2 flex justify-end gap-2">
        <button
          type="button"
          onClick={() => {
            setEditing(false);
            setError(null);
          }}
          className="rounded px-2 py-1 text-xs text-zinc-500 hover:bg-zinc-100"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={save}
          disabled={isSaving}
          className="flex items-center gap-1 rounded bg-zinc-900 px-2 py-1 text-xs font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
        >
          {isSaving && <Loader2 className="h-3 w-3 animate-spin" />}
          Save
        </button>
      </div>
    </li>
  );
}

function AddMethodForm({maps, onCreated}: {maps: XanoJourneyMap[]; onCreated: () => void}) {
  const [label, setLabel] = useState('');
  const [key, setKey] = useState('');
  const [keyTouched, setKeyTouched] = useState(false);
  const [subJourneyMapId, setSubJourneyMapId] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    if (!keyTouched) setKey(normaliseKey(label));
  }, [label, keyTouched]);

  const submit = async () => {
    const keyCheck = validateKey(key);
    const labelCheck = validateLabel(label);
    if (!keyCheck.valid) {
      setError('Fix the key — letters, numbers and hyphens only, 2 to 40 characters.');
      return;
    }
    if (!labelCheck.valid) {
      setError('Give it a name up to 80 characters, with no HTML.');
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      await createMethod({key, label, sub_journey_map_id: subJourneyMapId || undefined});
      setLabel('');
      setKey('');
      setKeyTouched(false);
      setSubJourneyMapId(0);
      onCreated();
    } catch (err) {
      setError(friendlyError(err, 'Unable to create this method.'));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="mt-4 rounded-md border border-dashed border-zinc-300 bg-white p-3">
      <div className="grid grid-cols-2 gap-2">
        <input
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          placeholder="Label, e.g. Hard goods"
          className="col-span-2 rounded border border-zinc-300 px-2 py-1.5 text-sm"
        />
        <input
          value={key}
          onChange={(e) => {
            setKeyTouched(true);
            setKey(e.target.value);
          }}
          placeholder="key-like-this"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm font-mono"
        />
        <select
          value={subJourneyMapId}
          onChange={(e) => setSubJourneyMapId(Number(e.target.value))}
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm"
        >
          <option value={0}>No sub-journey</option>
          {maps.map((m) => (
            <option key={m.id} value={m.id}>
              {m.title}
            </option>
          ))}
        </select>
      </div>
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
      <button
        type="button"
        onClick={submit}
        disabled={isSaving || !label.trim()}
        className="mt-2 flex items-center gap-1 rounded bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
      >
        {isSaving ? <Loader2 className="h-3 w-3 animate-spin" /> : <Plus className="h-3 w-3" />}
        Add method
      </button>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Shared bits
// ──────────────────────────────────────────────────────────────────────

function ListToolbar({showInactive, onToggle}: {showInactive: boolean; onToggle: (v: boolean) => void}) {
  return (
    <label className="flex items-center gap-2 text-xs text-zinc-500">
      <input type="checkbox" checked={showInactive} onChange={(e) => onToggle(e.target.checked)} />
      Show deactivated
    </label>
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

function LoadingRow() {
  return (
    <div className="flex items-center gap-2 p-4 text-sm text-zinc-500">
      <Loader2 className="h-4 w-4 animate-spin" /> Loading…
    </div>
  );
}
