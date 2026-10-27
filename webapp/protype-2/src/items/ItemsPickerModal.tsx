// ITEM-1 (US-ITEM-1-02) — "Choose items" picker, opened from the Items
// row header. Lists the ACCOUNT's full active item_type catalog
// (CAT-1's own GET /item-type — a 300-item catalog is exactly the case
// D-2 exists for) with a checkbox per item; Save calls the PUT
// items-row/items endpoint with the full checked set.
import {useEffect, useState} from 'react';
import type {ItemType} from '../catalog/catalogTypes';

export interface ItemsPickerModalProps {
  catalogItems: ItemType[];
  chosenItemTypeIds: number[];
  onSave: (itemTypeIds: number[]) => Promise<void>;
  onClose: () => void;
}

export function ItemsPickerModal({catalogItems, chosenItemTypeIds, onSave, onClose}: ItemsPickerModalProps) {
  const [checked, setChecked] = useState<Set<number>>(new Set(chosenItemTypeIds));
  const [filter, setFilter] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setChecked(new Set(chosenItemTypeIds));
  }, [chosenItemTypeIds]);

  const toggle = (id: number) => {
    setChecked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const visibleItems = catalogItems.filter(
    (item) => filter.trim() === '' || item.label.toLowerCase().includes(filter.trim().toLowerCase()),
  );

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    try {
      await onSave([...checked]);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to save the item list.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-lg bg-white p-5 shadow-xl flex flex-col max-h-[80vh]">
        <h3 className="text-sm font-semibold text-zinc-900">Choose items</h3>
        <p className="mt-1 text-xs text-zinc-500">
          Which items does this map use? Only chosen items show up in the Items cell editor.
        </p>
        <input
          type="text"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Filter items…"
          className="mt-3 w-full p-2 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-300"
        />
        <div className="mt-2 flex-1 overflow-auto border border-zinc-100 rounded divide-y divide-zinc-100">
          {visibleItems.length === 0 && <p className="p-3 text-xs text-zinc-400">No active items in the catalog yet.</p>}
          {visibleItems.map((item) => (
            <label key={item.id} className="flex items-center gap-2 p-2 text-xs text-zinc-700 hover:bg-zinc-50 cursor-pointer">
              <input type="checkbox" checked={checked.has(item.id)} onChange={() => toggle(item.id)} />
              <span className="flex-1">{item.label}</span>
              <span className="text-[10px] text-zinc-400">{item.unit}</span>
            </label>
          ))}
        </div>
        {error && <p className="mt-2 text-[11px] text-rose-600">{error}</p>}
        <div className="mt-4 flex justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            disabled={saving}
            className="rounded-md px-3 py-1.5 text-sm font-medium text-zinc-600 hover:bg-zinc-100"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => void handleSave()}
            disabled={saving}
            className="rounded-md bg-zinc-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
          >
            {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}
