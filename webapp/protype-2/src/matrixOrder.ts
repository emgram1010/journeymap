// ORD-1 (US-ORD-1-05) — pure ordering helpers behind the matrix's seam `+`
// and move arrows. No DOM, no network: the server is the only thing that
// writes an order (journey/apply_*_order), and it re-validates every list it
// is sent. These helpers only decide what to ask for.

export type MoveDirection = -1 | 1;

/**
 * The new order after moving `id` one place in `dir`, or `null` when there is
 * nowhere to go (already first/last, or the id is unknown). A null means the
 * arrow is disabled and no request should be sent.
 */
export function moveOneStep<T>(ids: readonly T[], id: T, dir: MoveDirection): T[] | null {
  const from = ids.indexOf(id);
  if (from < 0) return null;
  const to = from + dir;
  if (to < 0 || to >= ids.length) return null;
  const next = [...ids];
  [next[from], next[to]] = [next[to], next[from]];
  return next;
}

/**
 * The `after_stage_id` / `after_lens_id` for the seam at `seamIndex`, where
 * seam 0 is before the first item and seam `ids.length` is after the last.
 * N items give N+1 seams, each mapping to exactly one position:
 *   - leading seam  -> 0 (insert first)
 *   - inner seam    -> the id of the item to its left
 *   - trailing seam -> undefined (plain append, identical to the old add button)
 */
export function anchorForSeam(ids: readonly number[], seamIndex: number): number | undefined {
  if (seamIndex <= 0) return 0;
  if (seamIndex >= ids.length) return undefined;
  return ids[seamIndex - 1];
}

/** Tooltip for a seam, so the + says where the new item will land. */
export function seamTitle(noun: 'column' | 'row', seamIndex: number, count: number): string {
  if (seamIndex <= 0) return `Insert a ${noun} at the start`;
  if (seamIndex >= count) return `Insert a ${noun} at the end`;
  return `Insert a ${noun} here`;
}
