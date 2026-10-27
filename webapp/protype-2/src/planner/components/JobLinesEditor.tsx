// EST-1 (US-EST-1-06) — "What's in this order": the counts that turn
// a flat map into a real per-stage estimate. Lives inside a job's
// expanded row in JobsModal.
//
// ONLY SHOWN WHEN THE MAP HAS AN ITEMS ROW. A map with no Items row
// can't take lines at all (E-EST-004), so this component renders
// nothing for one — JobsModal decides that from the job's estimate
// (`has_items_row`), not this component.
//
// FROZEN ONCE WORK HAS STARTED: the server is the one source of truth
// for that (E-EST-007). Opus review fix (finding #8c, 2026-10-25):
// read `frozen` straight from the GET response on load, not only after
// a failed save — the earlier version only ever learned a job was
// frozen by trying to save and getting refused.
//
// REJECTED SAVES KEEP TYPING (CLAUDE.md UI rule): a failed PUT leaves
// `draftLines` exactly as the user left it — only a SUCCESSFUL save
// replaces the draft, from the server's own normalized response.
//
// THE ITEM PICKER READS `available_items` FROM THIS JOB'S OWN GET
// (finding #8a, 2026-10-25), not the account's whole catalog
// (`listCatalogItemTypes`). The server already sources this from the
// pinned version's `stage_rate` — the generic catalog list could
// offer an item this map was never priced for, which E-EST-003 would
// then refuse at save time with no warning beforehand.
import {useEffect, useState} from 'react';
import {Plus, Trash2, AlertTriangle} from 'lucide-react';
import {getWorkItemLines, putWorkItemLines, type WorkItemLine, type JobEstimate, type AvailableItem} from '../plannerApi';

interface DraftLine {
  item_type_id: number;
  quantity: string;
}

interface JobLinesEditorProps {
  workItemId: number;
  /** Called after a successful save so the caller can repaint the card/backlog without a second fetch. */
  onEstimateChanged: (estimate: JobEstimate) => void;
}

export function JobLinesEditor({workItemId, onEstimateChanged}: JobLinesEditorProps) {
  const [lines, setLines] = useState<WorkItemLine[]>([]);
  const [estimate, setEstimate] = useState<JobEstimate | null>(null);
  const [availableItems, setAvailableItems] = useState<AvailableItem[]>([]);
  const [draft, setDraft] = useState<DraftLine[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isFrozen, setIsFrozen] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setError(null);
    getWorkItemLines(workItemId)
      .then((result) => {
        if (cancelled) return;
        setLines(result.lines);
        setEstimate(result.estimate);
        setAvailableItems(result.available_items.filter((i) => i.is_active));
        setDraft(result.lines.map((l) => ({item_type_id: l.item_type_id, quantity: String(l.quantity)})));
        setIsFrozen(result.frozen);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Could not load this order\'s items.');
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [workItemId]);

  const addLine = () => {
    const picked = new Set(draft.map((d) => d.item_type_id));
    const next = availableItems.find((i) => !picked.has(i.item_type_id));
    if (!next) return;
    setDraft((prev) => [...prev, {item_type_id: next.item_type_id, quantity: '1'}]);
  };

  const removeLine = (index: number) => {
    setDraft((prev) => prev.filter((_, i) => i !== index));
  };

  const updateLine = (index: number, patch: Partial<DraftLine>) => {
    setDraft((prev) => prev.map((d, i) => (i === index ? {...d, ...patch} : d)));
  };

  const handleSave = async () => {
    setIsSaving(true);
    setError(null);
    setIsFrozen(false);
    try {
      const payload = draft
        .filter((d) => d.item_type_id > 0)
        .map((d) => ({item_type_id: d.item_type_id, quantity: Number(d.quantity) || 0}));
      const result = await putWorkItemLines(workItemId, payload);
      onEstimateChanged(result.estimate);
      const refreshed = await getWorkItemLines(workItemId);
      setLines(refreshed.lines);
      setEstimate(refreshed.estimate);
      setDraft(refreshed.lines.map((l) => ({item_type_id: l.item_type_id, quantity: String(l.quantity)})));
    } catch (err) {
      // Rejected save: draft is left exactly as typed (CLAUDE.md UI rule).
      const message = err instanceof Error ? err.message : 'That order\'s items could not be saved.';
      setError(message);
      if (message.includes('E-EST-007')) setIsFrozen(true);
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) {
    return <p className="text-[11px] text-neutral-400">Loading items…</p>;
  }

  // This work type doesn't track items (no Items row on its map) —
  // E-EST-004 would refuse a PUT anyway, so there is nothing to edit.
  if (estimate && !estimate.has_items_row) {
    return null;
  }

  return (
    <div className="flex flex-col gap-2">
      <p className="text-[11px] font-semibold text-neutral-800">What's in this order</p>

      {error && (
        <p className="text-[10px] text-red-600 flex items-center gap-1">
          <AlertTriangle className="w-3 h-3 shrink-0" />
          {error}
        </p>
      )}

      {isFrozen && (
        <p className="text-[10px] text-neutral-500">
          Work has started on this order, so its items are locked. Create a new order for extra items.
        </p>
      )}

      {availableItems.length === 0 && (
        <p className="text-[10px] text-neutral-500">
          This map's items aren't on this order's catalog yet — add them in Settings → Items, then publish a new
          version.
        </p>
      )}

      {draft.length === 0 ? (
        <p className="text-[10px] text-neutral-500">No items yet.</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {draft.map((d, index) => {
            const item = availableItems.find((i) => i.item_type_id === d.item_type_id);
            const savedLine = lines.find((l) => l.item_type_id === d.item_type_id);
            const isMissing = estimate?.missing.some((m) => m.quantity_key === savedLine?.item_key) ?? false;
            // EST-1 Opus review fix (finding #8b, 2026-10-25): the server
            // rejects a repeated item with E-EST-006 ("change its
            // quantity instead") — the picker should not let a second
            // line even offer an item already chosen by another line.
            const pickedElsewhere = new Set(draft.filter((_, i) => i !== index).map((other) => other.item_type_id));
            return (
              <li key={`${d.item_type_id}-${index}`} className="flex items-center gap-1.5 text-[11px]">
                <select
                  value={d.item_type_id}
                  disabled={isFrozen}
                  onChange={(e) => updateLine(index, {item_type_id: Number(e.target.value)})}
                  className="flex-1 min-w-0 border border-neutral-200 rounded px-1.5 py-1 text-[11px] disabled:opacity-60"
                >
                  <option value={0} disabled>
                    Choose an item…
                  </option>
                  {availableItems.map((i) => (
                    <option key={i.item_type_id} value={i.item_type_id} disabled={pickedElsewhere.has(i.item_type_id)}>
                      {i.label} ({i.unit})
                    </option>
                  ))}
                  {!item && d.item_type_id > 0 && <option value={d.item_type_id}>Item #{d.item_type_id}</option>}
                </select>
                <input
                  type="number"
                  min={1}
                  max={9999}
                  value={d.quantity}
                  disabled={isFrozen}
                  onChange={(e) => updateLine(index, {quantity: e.target.value})}
                  className="w-16 border border-neutral-200 rounded px-1.5 py-1 text-[11px] disabled:opacity-60"
                />
                {isMissing && (
                  <span className="text-amber-700 shrink-0" title="No rate for this item on at least one stage">
                    no rate
                  </span>
                )}
                <button
                  type="button"
                  onClick={() => removeLine(index)}
                  disabled={isFrozen}
                  className="shrink-0 p-1 text-neutral-400 hover:text-red-700 disabled:opacity-40"
                  aria-label="Remove item"
                >
                  <Trash2 className="w-3 h-3" />
                </button>
              </li>
            );
          })}
        </ul>
      )}

      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={addLine}
          disabled={isFrozen || availableItems.length === 0 || draft.length >= availableItems.length}
          className="flex items-center gap-1 px-2 py-1 text-[11px] font-medium text-neutral-700 border border-neutral-200 rounded hover:bg-neutral-50 disabled:opacity-40"
        >
          <Plus className="w-3 h-3" />
          Add item
        </button>
        <button
          type="button"
          onClick={() => void handleSave()}
          disabled={isFrozen || isSaving}
          className="px-2 py-1 text-[11px] font-semibold text-white bg-neutral-900 rounded hover:bg-neutral-800 disabled:opacity-60"
        >
          {isSaving ? 'Saving…' : 'Save'}
        </button>
      </div>

      {estimate && (
        <p className="text-[10px] text-neutral-500">
          Total: {estimate.total_minutes} min
          {!estimate.complete && estimate.reasons.includes('no_lines') && ' · add at least one item'}
          {!estimate.complete && !estimate.reasons.includes('no_lines') && ' · estimate incomplete — some items have no rate yet'}
        </p>
      )}
    </div>
  );
}
