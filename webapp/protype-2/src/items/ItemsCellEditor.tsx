// ITEM-1 (US-ITEM-1-04) — The Items cell editor: scaling choice, and
// (for per_unit/per_flagged_unit) a line per item×method with minutes.
// Rendered in App.tsx's cell detail panel in place of the generic
// actor-fields editor, branched on selectedCellLens.templateKey ===
// 'items-v1'.
//
// Rejected saves keep the user's typing (D- rule, same as every other
// cell editor in this app) — the draft state is local and is only
// cleared by a SUCCESSFUL save's follow-up prop update, never by the
// rejection path.
//
// TWO WAYS TO SAVE, ONE IMPLEMENTATION (bugfix, 2026-10-25): this
// editor's own Save button and the panel's "Save & Close" both run
// `runSave` below. Before the fix only the first one existed, it sat
// below the fold of the panel's scroll box (19 of its 32 pixels were
// clipped, and a click on its centre landed on the "Link to map"
// label underneath), so in practice people clicked "Save & Close" --
// which ran the GENERIC cell persist path and never saw this draft at
// all. The typing was dropped with no error. The Save button is now
// sticky so it cannot be clipped again, and App.tsx calls
// `saveIfChanged()` through the ref before it closes the panel.
import {forwardRef, useEffect, useImperativeHandle, useRef, useState} from 'react';
import {validateItemsCell, itemsCellDraftChanged, type NormalizedItemsCellLine} from './itemsCellValidation';
import type {ChosenItemDetail} from './itemsApi';

export interface ItemsMethodOption {
  id: number;
  key: string;
  label: string;
  sub_journey_map_id: number;
}

export interface ItemsCellEditorProps {
  scalesWith: string;
  lines: NormalizedItemsCellLine[];
  chosenItems: ChosenItemDetail[];
  activeMethods: ItemsMethodOption[];
  disabled?: boolean;
  onSave: (input: {
    scales_with: string;
    lines: Array<{item_key: string; method_key: string; minutes_per_unit: number | null}>;
  }) => Promise<void>;
}

const SCALES_WITH_OPTIONS: Array<{value: string; label: string}> = [
  {value: 'per_order', label: 'per order'},
  {value: 'per_unit', label: 'per unit'},
  {value: 'per_flagged_unit', label: 'per flagged unit'},
];

type DraftLine = {item_key: string; method_key: string; minutes_per_unit: number | null};

export interface ItemsCellEditorHandle {
  /**
   * Commits the draft if it differs from what the server last confirmed.
   * Returns false when the save was refused, so the caller leaves the panel
   * open with the typing and the message intact (CLAUDE.md UI rule).
   * Returns true when there was nothing to save.
   */
  saveIfChanged: () => Promise<boolean>;
}

export const ItemsCellEditor = forwardRef<ItemsCellEditorHandle, ItemsCellEditorProps>(function ItemsCellEditor(
  {scalesWith, lines, chosenItems, activeMethods, disabled, onSave}: ItemsCellEditorProps,
  ref,
) {
  const [draftScalesWith, setDraftScalesWith] = useState(scalesWith || 'per_order');
  const [draftLines, setDraftLines] = useState<DraftLine[]>(lines);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const errorRef = useRef<HTMLParagraphElement | null>(null);

  // Only resync from props when the CELL itself changes underneath us
  // (a different cell selected) — never after our own save, so a
  // rejected save's typing survives. scalesWith/lines are the cell's
  // server-confirmed state; keying this effect on them is safe because
  // a successful save always updates them to match what we just sent.
  useEffect(() => {
    setDraftScalesWith(scalesWith || 'per_order');
    setDraftLines(lines);
    setError(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scalesWith, lines]);

  const allowedItemKeys = new Set(chosenItems.map((i) => i.key));
  const activeMethodKeys = new Set(activeMethods.map((m) => m.key));

  const handleScalesWithChange = (next: string) => {
    setDraftScalesWith(next);
    setError(null);
    if ((next === 'per_unit' || next === 'per_flagged_unit') && draftLines.length === 0 && chosenItems.length > 0) {
      // US-ITEM-1-04: pre-fill one line per chosen item with its default method.
      setDraftLines(
        chosenItems.map((item) => {
          const defaultMethod = activeMethods.find((m) => m.id === item.default_method_id);
          return {
            item_key: item.key,
            method_key: defaultMethod?.key ?? activeMethods[0]?.key ?? '',
            minutes_per_unit: null,
          };
        }),
      );
    }
  };

  const updateLine = (index: number, patch: Partial<DraftLine>) => {
    setDraftLines((prev) => prev.map((l, i) => (i === index ? {...l, ...patch} : l)));
  };

  const addLine = () => {
    setDraftLines((prev) => [
      ...prev,
      {item_key: chosenItems[0]?.key ?? '', method_key: activeMethods[0]?.key ?? '', minutes_per_unit: null},
    ]);
  };

  const removeLine = (index: number) => {
    setDraftLines((prev) => prev.filter((_, i) => i !== index));
  };

  const runSave = async (): Promise<boolean> => {
    const validated = validateItemsCell({
      scalesWith: draftScalesWith,
      lines: draftLines,
      allowedItemKeys,
      activeMethodKeys,
    });
    if (!validated.ok) {
      setError(validated.message);
      return false;
    }
    setError(null);
    setSaving(true);
    try {
      await onSave({scales_with: draftScalesWith, lines: validated.normalizedLines});
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to save.');
      return false;
    } finally {
      setSaving(false);
    }
  };

  const handleSave = async () => {
    await runSave();
  };

  // "Save & Close" (and the panel's X, which saves too) reach the draft
  // through this. A locked cell has nothing to commit, and an untouched one
  // must not fire a request just because it was opened and closed.
  useImperativeHandle(
    ref,
    () => ({
      saveIfChanged: async () => {
        if (disabled) return true;
        const changed = itemsCellDraftChanged(
          {scalesWith: scalesWith || 'per_order', lines},
          {scalesWith: draftScalesWith, lines: draftLines},
        );
        if (!changed) return true;
        return runSave();
      },
    }),
    // runSave reads the draft through the closure, so the handle has to be
    // rebuilt whenever the draft moves -- otherwise Save & Close would
    // commit a stale one.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [disabled, scalesWith, lines, draftScalesWith, draftLines, allowedItemKeys, activeMethodKeys, onSave],
  );

  // A refusal that arrives from "Save & Close" can land on a message that is
  // scrolled out of the panel, which reads as "nothing happened" -- the exact
  // failure this fix is about. Bring it into view.
  useEffect(() => {
    if (error) errorRef.current?.scrollIntoView({block: 'nearest'});
  }, [error]);

  const hasChosenItems = chosenItems.length > 0;

  return (
    <div className="space-y-3">
      <div>
        <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Time scales with</label>
        <div className="space-y-1.5">
          {SCALES_WITH_OPTIONS.map((opt) => (
            <label key={opt.value} className="flex items-center gap-2 text-xs text-zinc-700">
              <input
                type="radio"
                name="items-scales-with"
                value={opt.value}
                checked={draftScalesWith === opt.value}
                disabled={disabled}
                onChange={() => handleScalesWithChange(opt.value)}
              />
              {opt.label}
            </label>
          ))}
        </div>
      </div>

      {draftScalesWith !== 'per_order' && !hasChosenItems && (
        <p className="text-[11px] text-amber-700 bg-amber-50 border border-amber-100 rounded p-2">
          No items chosen for this map yet. Use "Choose items" on the Items row header first.
        </p>
      )}

      {draftScalesWith !== 'per_order' && hasChosenItems && (
        <div className="space-y-2">
          <div className="grid grid-cols-[1fr_1fr_64px_20px] gap-1.5 text-[9px] font-bold text-zinc-400 uppercase tracking-wider px-0.5">
            <span>Item</span>
            <span>Method</span>
            <span>Min/unit</span>
            <span />
          </div>
          {draftLines.map((line, idx) => {
            const method = activeMethods.find((m) => m.key === line.method_key);
            return (
              <div key={idx} className="grid grid-cols-[1fr_1fr_64px_20px] gap-1.5 items-center">
                <select
                  className="text-xs p-1.5 bg-white border border-zinc-200 rounded min-w-0"
                  value={line.item_key}
                  disabled={disabled}
                  onChange={(e) => updateLine(idx, {item_key: e.target.value})}
                >
                  {chosenItems.map((i) => (
                    <option key={i.key} value={i.key}>
                      {i.label}
                    </option>
                  ))}
                </select>
                <div className="flex items-center gap-1 min-w-0">
                  <select
                    className="text-xs p-1.5 bg-white border border-zinc-200 rounded flex-1 min-w-0"
                    value={line.method_key}
                    disabled={disabled}
                    onChange={(e) => updateLine(idx, {method_key: e.target.value})}
                  >
                    {activeMethods.map((m) => (
                      <option key={m.key} value={m.key}>
                        {m.label}
                      </option>
                    ))}
                  </select>
                  {method && method.sub_journey_map_id !== 0 && (
                    <span className="text-[10px] text-indigo-500 shrink-0" title="This method has a sub-journey">
                      ↗ steps
                    </span>
                  )}
                </div>
                <input
                  type="number"
                  min={0}
                  max={1440}
                  step={0.01}
                  className={`text-xs p-1.5 border rounded w-full ${
                    line.minutes_per_unit == null ? 'border-amber-300 bg-amber-50' : 'border-zinc-200 bg-white'
                  }`}
                  value={line.minutes_per_unit ?? ''}
                  disabled={disabled}
                  placeholder="—"
                  onChange={(e) => {
                    const raw = e.target.value;
                    updateLine(idx, {minutes_per_unit: raw.trim() === '' ? null : Number(raw)});
                  }}
                />
                <button
                  type="button"
                  className="text-zinc-400 hover:text-rose-600 text-xs"
                  onClick={() => removeLine(idx)}
                  disabled={disabled}
                  title="Remove this line"
                >
                  ✕
                </button>
              </div>
            );
          })}
          <button
            type="button"
            className="text-[11px] text-indigo-600 hover:text-indigo-800 font-medium disabled:opacity-40"
            onClick={addLine}
            disabled={disabled}
          >
            + add a second method for an item
          </button>
        </div>
      )}

      {error && (
        <p ref={errorRef} className="text-[11px] text-rose-600">
          {error}
        </p>
      )}

      {/* Sticky, so a long item list can never push this below the fold of
          the panel's scroll box again. -mx-3/px-3 lets the white backing
          span the full width as content scrolls underneath it. */}
      <div className="sticky bottom-0 -mx-3 px-3 pt-2 pb-1 bg-white">
        <button
          type="button"
          className="w-full py-2 rounded bg-zinc-900 text-white text-xs font-semibold disabled:opacity-50"
          disabled={disabled || saving}
          onClick={() => void handleSave()}
        >
          {saving ? 'Saving…' : 'Save'}
        </button>
      </div>
    </div>
  );
});
