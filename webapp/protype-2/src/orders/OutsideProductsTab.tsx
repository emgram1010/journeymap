// Orders — "Outside products" tab: link the product names an order system
// uses to this account's catalog items.
//
// Product names come from OUTSIDE the app, so they are only ever rendered
// as plain text (React escapes them) — never as HTML.
// A rejected save shows the server's own sentence and keeps what was chosen.
import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {AlertCircle, Loader2, Plus} from 'lucide-react';
import {friendlyError} from '../xano';
import {listItemTypes} from '../catalog/catalogApi';
import type {ItemType} from '../catalog/catalogTypes';
import {listExternalRefs, setExternalRef, type SetExternalRefInput} from './ordersApi';
import {toLink, refStatus, sourceNameProblem, type ExternalRef} from './ordersModel';

export default function OutsideProductsTab() {
  const [refs, setRefs] = useState<ExternalRef[]>([]);
  const [items, setItems] = useState<ItemType[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [listError, setListError] = useState<string | null>(null);

  const load = useCallback(() => {
    setListError(null);
    // Deactivated items are loaded too, so a product linked to one still
    // shows that item's name; only active ones are offered for new links.
    Promise.all([listExternalRefs(), listItemTypes(true)])
      .then(([refRes, itemRes]) => {
        setRefs(refRes?.refs ?? []);
        setItems(itemRes?.items ?? []);
      })
      .catch((err) => setListError(friendlyError(err, 'Unable to load outside products.')))
      .finally(() => setIsLoading(false));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const activeItems = useMemo(() => items.filter((i) => i.is_active), [items]);
  const needsLinking = useMemo(() => toLink(refs), [refs]);
  const others = useMemo(() => {
    const pending = new Set(needsLinking.map((r) => r.ref_id));
    return refs.filter((r) => !pending.has(r.ref_id));
  }, [refs, needsLinking]);

  const itemName = useCallback(
    (id: number) => items.find((i) => i.id === id)?.label ?? `Item #${id}`,
    [items],
  );

  return (
    <div>
      <p className="text-sm text-zinc-500">
        Link the products in your order system to your catalog items, so an order gets the right time.
      </p>

      {listError && <ErrorBanner message={listError} />}

      {isLoading ? (
        <div className="flex items-center gap-2 p-4 text-sm text-zinc-500">
          <Loader2 className="h-4 w-4 animate-spin" /> Loading…
        </div>
      ) : refs.length === 0 ? (
        !listError && (
          <p className="mt-4 rounded-md border border-zinc-200 bg-white p-4 text-sm text-zinc-500">
            No outside products yet. They appear here the first time an order arrives.
          </p>
        )
      ) : (
        <>
          <h2 className="mt-5 text-sm font-semibold text-zinc-900">Needs linking ({needsLinking.length})</h2>
          <ul className="mt-2 divide-y divide-zinc-200 rounded-md border border-zinc-200 bg-white">
            {needsLinking.length === 0 && <li className="p-3 text-sm text-zinc-500">Nothing is waiting to be linked.</li>}
            {needsLinking.map((r) => (
              <RefRow key={r.ref_id} refRow={r} activeItems={activeItems} itemName={itemName} onChanged={load} />
            ))}
          </ul>

          {others.length > 0 && (
            <>
              <h2 className="mt-6 text-sm font-semibold text-zinc-900">Already handled ({others.length})</h2>
              <ul className="mt-2 divide-y divide-zinc-200 rounded-md border border-zinc-200 bg-white">
                {others.map((r) => (
                  <RefRow key={r.ref_id} refRow={r} activeItems={activeItems} itemName={itemName} onChanged={load} />
                ))}
              </ul>
            </>
          )}
        </>
      )}

      {!isLoading && <AddProductForm activeItems={activeItems} itemName={itemName} onAdded={load} />}
    </div>
  );
}

/** "This product is already linked to <item>. Move it?" — shown in place, not as a pop-up. */
function MoveConfirm({
  currentItem,
  isSaving,
  onMove,
  onCancel,
}: {
  currentItem: string;
  isSaving: boolean;
  onMove: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="mt-2 flex flex-wrap items-center gap-2 rounded-md border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
      <span>This product is already linked to {currentItem}. Move it?</span>
      <button
        type="button"
        onClick={onMove}
        disabled={isSaving}
        className="rounded bg-zinc-900 px-2 py-1 font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
      >
        Move it
      </button>
      <button type="button" onClick={onCancel} disabled={isSaving} className="rounded px-2 py-1 text-zinc-600 hover:bg-amber-100">
        Keep as is
      </button>
    </div>
  );
}

function RefRow({
  refRow,
  activeItems,
  itemName,
  onChanged,
}: {
  refRow: ExternalRef;
  activeItems: ItemType[];
  itemName: (id: number) => string;
  onChanged: () => void;
}) {
  const [choice, setChoice] = useState(refRow.item_type_id || 0);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  /** Set when the server says the product is linked elsewhere; holds the item it is linked to now. */
  const [moveFrom, setMoveFrom] = useState<number | null>(null);

  // A reload after a save brings the stored link back; follow it.
  useEffect(() => {
    setChoice(refRow.item_type_id || 0);
  }, [refRow.item_type_id]);

  const send = async (input: SetExternalRefInput) => {
    setIsSaving(true);
    setError(null);
    try {
      const res = await setExternalRef({ref_id: refRow.ref_id, ...input});
      if (res?.status === 'move_needed') {
        setMoveFrom(res.current_item_type_id);
        return;
      }
      setMoveFrom(null);
      onChanged();
    } catch (err) {
      // The chosen item stays selected so nothing has to be picked again.
      setError(friendlyError(err, 'Unable to save. Your choice is kept.'));
    } finally {
      setIsSaving(false);
    }
  };

  const status = refStatus(refRow);
  const statusStyle =
    status === 'Needs linking' ? 'bg-amber-100 text-amber-800' : status === 'Linked' ? 'bg-emerald-100 text-emerald-800' : 'bg-zinc-100 text-zinc-600';
  // A product linked to a deactivated item still needs that item in the list to show its current link.
  const linkedIsListed = !refRow.item_type_id || activeItems.some((i) => i.id === refRow.item_type_id);

  return (
    <li className="p-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="truncate text-sm font-medium text-zinc-900">{refRow.external_name || '(no name)'}</span>
            <span className={`shrink-0 rounded px-1.5 py-0.5 text-xs ${statusStyle}`}>{status}</span>
          </div>
          <div className="truncate text-xs text-zinc-500">
            {refRow.source_system} · ID {refRow.external_id} · seen {refRow.seen_count} {refRow.seen_count === 1 ? 'time' : 'times'}
          </div>
        </div>
        <div className="flex shrink-0 flex-wrap items-center gap-1">
          <select
            value={choice}
            onChange={(e) => {
              setChoice(Number(e.target.value));
              setMoveFrom(null);
            }}
            aria-label="Catalog item"
            className="max-w-[12rem] rounded border border-zinc-300 px-2 py-1 text-xs"
          >
            <option value={0}>Choose an item…</option>
            {!linkedIsListed && <option value={refRow.item_type_id}>{itemName(refRow.item_type_id)} (deactivated)</option>}
            {activeItems.map((i) => (
              <option key={i.id} value={i.id}>
                {i.label}
              </option>
            ))}
          </select>
          <button
            type="button"
            onClick={() => send({item_type_id: choice, not_an_item: false})}
            disabled={isSaving || choice === 0}
            className="flex items-center gap-1 rounded bg-zinc-900 px-2 py-1 text-xs font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
          >
            {isSaving && <Loader2 className="h-3 w-3 animate-spin" />}
            Save
          </button>
          <button
            type="button"
            title="For fees and deposits — things that are not work"
            onClick={() => send({item_type_id: 0, not_an_item: true})}
            disabled={isSaving || refRow.not_an_item}
            className="rounded px-2 py-1 text-xs font-medium text-zinc-600 hover:bg-zinc-100 disabled:opacity-40"
          >
            Not an item
          </button>
          <button
            type="button"
            title="Remove the link"
            onClick={() => send({item_type_id: 0, not_an_item: false})}
            disabled={isSaving || status === 'Needs linking'}
            className="rounded px-2 py-1 text-xs font-medium text-zinc-600 hover:bg-zinc-100 disabled:opacity-40"
          >
            Clear
          </button>
        </div>
      </div>
      {moveFrom !== null && (
        <MoveConfirm
          currentItem={itemName(moveFrom)}
          isSaving={isSaving}
          onMove={() => send({item_type_id: choice, not_an_item: false, move: true})}
          onCancel={() => setMoveFrom(null)}
        />
      )}
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
    </li>
  );
}

function AddProductForm({
  activeItems,
  itemName,
  onAdded,
}: {
  activeItems: ItemType[];
  itemName: (id: number) => string;
  onAdded: () => void;
}) {
  const [source, setSource] = useState('');
  const [externalId, setExternalId] = useState('');
  const [name, setName] = useState('');
  const [itemId, setItemId] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [moveFrom, setMoveFrom] = useState<number | null>(null);

  const submit = async (move: boolean) => {
    const sourceProblem = sourceNameProblem(source);
    if (sourceProblem) {
      setError(`Order system: ${sourceProblem}`);
      return;
    }
    if (!externalId.trim()) {
      setError('Enter the product ID your order system uses.');
      return;
    }
    setIsSaving(true);
    setError(null);
    try {
      const res = await setExternalRef({
        source_system: source.trim(),
        external_id: externalId.trim(),
        external_name: name.trim(),
        item_type_id: itemId,
        not_an_item: false,
        ...(move ? {move: true} : {}),
      });
      if (res?.status === 'move_needed') {
        setMoveFrom(res.current_item_type_id);
        return;
      }
      setMoveFrom(null);
      setExternalId('');
      setName('');
      setItemId(0);
      onAdded();
    } catch (err) {
      // Nothing is cleared on failure — what was typed stays in the form.
      setError(friendlyError(err, 'Unable to add this product. What you typed is kept.'));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="mt-6 rounded-md border border-dashed border-zinc-300 bg-white p-3">
      <h2 className="text-sm font-semibold text-zinc-900">Add a product by hand</h2>
      <p className="mt-0.5 text-xs text-zinc-500">Use this to link a product before its first order arrives.</p>
      <div className="mt-2 grid grid-cols-2 gap-2">
        <input
          value={source}
          onChange={(e) => setSource(e.target.value)}
          placeholder="Order system, e.g. my-shop"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm"
        />
        <input
          value={externalId}
          onChange={(e) => setExternalId(e.target.value)}
          placeholder="Product ID in that system"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm"
        />
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Product name"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm"
        />
        <select
          value={itemId}
          onChange={(e) => {
            setItemId(Number(e.target.value));
            setMoveFrom(null);
          }}
          aria-label="Catalog item"
          className="rounded border border-zinc-300 px-2 py-1.5 text-sm"
        >
          <option value={0}>Link later</option>
          {activeItems.map((i) => (
            <option key={i.id} value={i.id}>
              {i.label}
            </option>
          ))}
        </select>
      </div>
      {moveFrom !== null && (
        <MoveConfirm
          currentItem={itemName(moveFrom)}
          isSaving={isSaving}
          onMove={() => submit(true)}
          onCancel={() => setMoveFrom(null)}
        />
      )}
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
      <button
        type="button"
        onClick={() => submit(false)}
        disabled={isSaving || !source.trim() || !externalId.trim()}
        className="mt-2 flex items-center gap-1 rounded bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
      >
        {isSaving ? <Loader2 className="h-3 w-3 animate-spin" /> : <Plus className="h-3 w-3" />}
        Add product
      </button>
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
