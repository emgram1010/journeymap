// ITEM-1 (US-ITEM-1-03) — Pure, client-side mirror of
// functions/items/validate_items_cell.xs. The server is always the
// real gate (it re-checks everything); this exists so the UI can show
// the friendly message immediately, without a round trip, and so the
// rule can be unit-tested without a live backend.
//
// Kept intentionally dumb about WHERE allowedItemKeys/activeMethodKeys
// come from — the caller (ItemsCellEditor) is responsible for fetching
// the map's chosen-item set and the account's active methods and
// passing them in as plain key sets. That keeps this function pure and
// synchronous, like every other *Validation.ts file in this project.

export type ScalesWith = 'per_order' | 'per_unit' | 'per_flagged_unit';

export interface ItemsCellLineInput {
  item_key: string;
  method_key: string;
  minutes_per_unit?: number | null;
}

export interface NormalizedItemsCellLine {
  item_key: string;
  method_key: string;
  minutes_per_unit: number | null;
}

export interface ValidateItemsCellInput {
  scalesWith: string;
  lines: readonly ItemsCellLineInput[];
  /** Keys from this map's own journey_lens_item set (US-ITEM-1-02), active items only. */
  allowedItemKeys: ReadonlySet<string>;
  /** Active method keys in the account. */
  activeMethodKeys: ReadonlySet<string>;
}

export interface ValidateItemsCellResult {
  ok: boolean;
  code: string;
  message: string;
  normalizedLines: NormalizedItemsCellLine[];
  droppedLinesWarn: boolean;
}

const SCALES_WITH_VALUES: ReadonlySet<string> = new Set(['per_order', 'per_unit', 'per_flagged_unit']);

/** Mirrors the backend's manual round-half-up + epsilon compare (no |round filter there either). */
function hasAtMostTwoDecimals(value: number): boolean {
  const scaled = value * 100;
  const scaledRounded = Math.floor(scaled + 0.5);
  const diff = scaled - scaledRounded;
  return diff > -0.01 && diff < 0.01;
}

export function validateItemsCell(input: ValidateItemsCellInput): ValidateItemsCellResult {
  // Defensive against a non-string runtime value reaching here (e.g. from
  // an untyped API response) -- the junk corpus exercises exactly this,
  // same spirit as catalogValidation.ts's own junk-input testing.
  const rawScalesWith = typeof input.scalesWith === 'string' ? input.scalesWith : String(input.scalesWith ?? '');
  const scalesWith = rawScalesWith.trim().toLowerCase();
  const normalizedLines: NormalizedItemsCellLine[] = [];
  let droppedLinesWarn = false;

  if (!SCALES_WITH_VALUES.has(scalesWith)) {
    return {
      ok: false,
      code: 'E-ITM-003',
      message: 'Choose per order, per unit or per flagged unit. (E-ITM-003)',
      normalizedLines: [],
      droppedLinesWarn: false,
    };
  }

  if (scalesWith === 'per_order') {
    if (input.lines.length > 0) droppedLinesWarn = true;
    return {ok: true, code: '', message: '', normalizedLines: [], droppedLinesWarn};
  }

  const seenPairs = new Set<string>();

  for (const line of input.lines) {
    if (!input.allowedItemKeys.has(line.item_key)) {
      return {
        ok: false,
        code: 'E-ITM-002',
        message: "Add that item to this map's item list first. (E-ITM-002)",
        normalizedLines: [],
        droppedLinesWarn: false,
      };
    }

    if (!input.activeMethodKeys.has(line.method_key)) {
      return {
        ok: false,
        code: 'E-ITM-005',
        message: 'Pick a method from your catalog. (E-ITM-005)',
        normalizedLines: [],
        droppedLinesWarn: false,
      };
    }

    const hasMinutes = line.minutes_per_unit != null;
    if (hasMinutes) {
      const minutes = line.minutes_per_unit as number;
      const inRange = minutes >= 0 && minutes <= 1440;
      if (!inRange || !hasAtMostTwoDecimals(minutes)) {
        return {
          ok: false,
          code: 'E-ITM-004',
          message: 'Enter minutes for one item, like 2.5, or leave it empty for now. (E-ITM-004)',
          normalizedLines: [],
          droppedLinesWarn: false,
        };
      }
    }

    const pairKey = `${line.item_key}::${line.method_key}`;
    if (seenPairs.has(pairKey)) {
      return {
        ok: false,
        code: 'E-ITM-006',
        message: 'That item already has a line for that method here. (E-ITM-006)',
        normalizedLines: [],
        droppedLinesWarn: false,
      };
    }
    seenPairs.add(pairKey);

    normalizedLines.push({
      item_key: line.item_key,
      method_key: line.method_key,
      minutes_per_unit: hasMinutes ? (line.minutes_per_unit as number) : null,
    });
  }

  return {ok: true, code: '', message: '', normalizedLines, droppedLinesWarn};
}

/**
 * ITEM-1 bugfix (2026-10-25) — has the Items cell draft moved away from what
 * the server last confirmed?
 *
 * Why this exists: the Items cell keeps its draft inside ItemsCellEditor, so
 * the panel's generic "Save & Close" path (persistCellChanges) never saw it
 * and silently threw the typing away. Save & Close now commits the draft
 * first, and it needs a cheap, pure "is there anything to commit" test so a
 * plain open-and-close of an untouched cell fires no request.
 *
 * Compared by value and in order: a reordered pair of lines IS a change, the
 * server stores the array as given. minutes_per_unit is compared with its
 * null/undefined collapsed, because the editor writes null for an empty box
 * while a stored line that was never priced can arrive as either.
 */
export function itemsCellDraftChanged(
  saved: {scalesWith: string; lines: readonly ItemsCellLineInput[]},
  draft: {scalesWith: string; lines: readonly ItemsCellLineInput[]},
): boolean {
  if (saved.scalesWith !== draft.scalesWith) return true;
  if (saved.lines.length !== draft.lines.length) return true;

  for (let i = 0; i < saved.lines.length; i += 1) {
    const a = saved.lines[i];
    const b = draft.lines[i];
    if (a.item_key !== b.item_key) return true;
    if (a.method_key !== b.method_key) return true;
    if ((a.minutes_per_unit ?? null) !== (b.minutes_per_unit ?? null)) return true;
  }

  return false;
}
