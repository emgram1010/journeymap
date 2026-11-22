// DEMAND-1 story 01 (decision D-11) — the ADD-ONLY rule for a day that is
// already live. The frontend twin of `planner_ops/live_add_attempt` and
// `live/canonical_items`.
//
// A live day is frozen so the team can trust it. Adding a same-day job
// must therefore never touch what is already there: every frozen block
// is copied UNCHANGED and in the same order, and the new job's blocks go
// after the last one. `isAddOnly` is the proof the server checks before
// it writes: the new day's canonical text must START WITH the old day's
// canonical text, byte for byte.
import {canonicalizePublicationV3, type PublicationItemV3} from './liveModel';

/** One block as the live plan (or a frozen snapshot) describes it. */
export interface LiveItem extends Omit<PublicationItemV3, 'time_window' | 'start_override'> {
  item_ref: string;
  work_item_id?: number;
  assignee_has_login?: boolean;
  status?: string;
  // Old snapshots (before time windows and manual starts) have neither key.
  time_window?: PublicationItemV3['time_window'];
  start_override?: string;
}

export type AddProblem = 'NO_ASSIGNEE' | 'NO_LOGIN' | 'NEEDS_INFO';

export interface AppendResult {
  /** The whole new day: frozen blocks first, unchanged, then the added ones. */
  items: LiveItem[];
  /** Only the blocks this add contributed, with their new order numbers. */
  added: LiveItem[];
  addedMinutes: number;
  /** Why the add must be refused; empty = fine. */
  problems: AddProblem[];
}

const asV3 = (items: ReadonlyArray<LiveItem>): PublicationItemV3[] =>
  items.map((i) => ({...i, time_window: i.time_window ?? null, start_override: i.start_override ?? ''}));

/** The canonical text of a list of frozen blocks (always the v3 line shape). */
export function canonicalItems(items: ReadonlyArray<LiveItem>): string {
  return canonicalizePublicationV3(asV3(items));
}

/**
 * Put one job's blocks at the end of a frozen day.
 * `frozen` is the current snapshot; `live` is the plan as it stands now.
 * A live block joins only when it belongs to `workItemId` and the frozen
 * day does not already have it — so running this twice adds nothing.
 */
export function appendToLiveDay(frozen: ReadonlyArray<LiveItem>, live: ReadonlyArray<LiveItem>, workItemId: number): AppendResult {
  const known = new Set(frozen.map((i) => i.item_ref));
  let seq = frozen.reduce((max, i) => Math.max(max, i.seq), 0);
  const added: LiveItem[] = [];
  const problems = new Set<AddProblem>();
  for (const item of live) {
    if (item.work_item_id !== workItemId || known.has(item.item_ref)) continue;
    if (!item.assignee_agent_id) problems.add('NO_ASSIGNEE');
    else if (item.assignee_has_login === false) problems.add('NO_LOGIN');
    if (item.status === 'needs_info') problems.add('NEEDS_INFO');
    seq += 1;
    added.push({...item, seq});
  }
  return {
    items: [...frozen, ...added],
    added,
    addedMinutes: added.reduce((sum, i) => sum + (i.scheduled_minutes ?? 0), 0),
    problems: [...problems],
  };
}

/** True when `after` is `before` plus blocks at the end, and nothing else. */
export function isAddOnly(before: ReadonlyArray<LiveItem>, after: ReadonlyArray<LiveItem>): boolean {
  if (after.length < before.length) return false;
  return canonicalItems(after).startsWith(canonicalItems(before));
}
