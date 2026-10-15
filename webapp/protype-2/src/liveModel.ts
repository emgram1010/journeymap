// LIVE-1 (US-LIVE-1-02, -04) — What stops a timeline being published,
// what gets frozen when it is, and how a later planner change is
// described.
//
// NOT TO BE CONFUSED WITH "PUBLISH VERSION" (PUB-1), which freezes a
// journey map. This is **publish to live**: freezing one agent's day
// so the person doing the work sees a fixed list, even while the
// planner keeps moving things around afterwards.
//
// The canonicalisation below deliberately follows the same shape as
// `versionHash.ts`: an explicit hand-built string, never
// `JSON.stringify`. The hash has to match between this module and the
// Xano side, and JSON encoders disagree about key order, whitespace
// and unicode escaping.

import {escapeField} from './versionHash';

export type BlockerCode = 'EMPTY' | 'NO_ASSIGNEE' | 'NEEDS_INFO' | 'NO_LOGIN';

export interface PublishableItem {
  /** The planner_task id — stable within this timeline. */
  planner_task_id: number;
  /** Effective assignee after the timeline's own agent is applied; 0 = nobody. */
  assignee_agent_id: number;
  /** Whether that agent has a linked login (P3A-1's planner_agent.user_id). */
  assignee_has_login: boolean;
  /** The agent's name, for the blocker message. */
  assignee_name?: string | null;
  /** planner_task.status — `needs_info` blocks publishing. */
  status: 'planned' | 'needs_info';
  seq: number;
  planned_start: string | null;
  scheduled_minutes: number;
  expected_minutes: number | null;
  work_task_ids: number[];
  stage_label?: string | null;
  lens_label?: string | null;
  title?: string | null;
}

export interface Blocker {
  code: BlockerCode;
  count: number;
  /** Names or references the message can quote. */
  detail: string[];
}

/**
 * Everything standing between this timeline and its performer.
 *
 * ALL BLOCKERS ARE RETURNED AT ONCE, not just the first. Someone
 * fixing a day wants the whole list — telling them about one missing
 * assignee, then one more after they fix it, is the slowest possible
 * way to publish a day.
 *
 * An EMPTY timeline returns only that: the other checks would all be
 * vacuously clean and listing them would be noise.
 */
export function publishBlockers(items: ReadonlyArray<PublishableItem>): Blocker[] {
  if (items.length === 0) {
    return [{code: 'EMPTY', count: 0, detail: []}];
  }

  const blockers: Blocker[] = [];

  const unassigned = items.filter((i) => !i.assignee_agent_id);
  if (unassigned.length > 0) {
    blockers.push({
      code: 'NO_ASSIGNEE',
      count: unassigned.length,
      detail: unassigned.map((i) => String(i.planner_task_id)),
    });
  }

  const needsInfo = items.filter((i) => i.status === 'needs_info');
  if (needsInfo.length > 0) {
    blockers.push({
      code: 'NEEDS_INFO',
      count: needsInfo.length,
      detail: needsInfo.map((i) => String(i.planner_task_id)),
    });
  }

  // Only meaningful for items that HAVE an assignee — an unassigned
  // item is already reported above, and saying "nobody has a login"
  // about it would be a second complaint about the same problem.
  const noLogin = items.filter((i) => i.assignee_agent_id !== 0 && !i.assignee_has_login);
  if (noLogin.length > 0) {
    const names = [...new Set(noLogin.map((i) => i.assignee_name ?? String(i.assignee_agent_id)))];
    blockers.push({code: 'NO_LOGIN', count: noLogin.length, detail: names});
  }

  return blockers;
}

/** Plain-language text for a blocker, as the planner should read it. */
export function blockerMessage(b: Blocker): string {
  switch (b.code) {
    case 'EMPTY':
      return "There's nothing on this timeline to publish.";
    case 'NO_ASSIGNEE':
      return `${b.count} ${b.count === 1 ? 'step doesn’t' : 'steps don’t'} have a person assigned.`;
    case 'NEEDS_INFO':
      return `${b.count} ${b.count === 1 ? 'step is' : 'steps are'} marked 'needs info'. Complete them first.`;
    case 'NO_LOGIN':
      return `${b.detail.join(', ')} ${b.detail.length === 1 ? "doesn't have a login" : "don't have logins"} yet, so they can't see their work.`;
  }
}

/**
 * The canonical string a publication's `snapshot_hash` is taken from.
 *
 * Order is the timeline's own order (`seq`), and every field is
 * escaped the same way `versionHash.ts` escapes — so a pipe or a
 * newline inside a label cannot forge a field boundary.
 *
 * `item_ref` is what log events point at (review finding F5). It is
 * derived from the planner task id and frozen here, so a log row
 * stays attached to the published item even after the planner task is
 * moved or removed.
 */
export function canonicalizePublication(items: ReadonlyArray<PublishableItem>): string {
  let out = 'publication|v1\n';
  for (const i of [...items].sort((a, b) => a.seq - b.seq)) {
    out +=
      `item|${escapeField(itemRef(i))}` +
      `|${i.seq}` +
      `|${escapeField(i.planned_start)}` +
      `|${i.scheduled_minutes}` +
      `|${i.expected_minutes ?? ''}` +
      `|${i.assignee_agent_id}` +
      `|${escapeField(i.stage_label)}` +
      `|${escapeField(i.lens_label)}` +
      `|${i.work_task_ids.slice().sort((a, b) => a - b).join(',')}` +
      `\n`;
  }
  return out;
}

/** The stable reference a log event points at, never the planner task directly. */
export function itemRef(item: {planner_task_id: number}): string {
  return `pt-${item.planner_task_id}`;
}

export type ChangeType = 'moved' | 'added' | 'removed' | 'duration_changed' | 'reassigned';

export interface PlanChange {
  change_type: ChangeType;
  item_ref: string;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
}

/**
 * What the planner changed after publishing.
 *
 * Compares the published snapshot's items against the timeline as it
 * stands now. The performer never sees any of this (D-23) — it exists
 * so that plan-vs-actual stays honest: without it, a day that was
 * quietly rearranged after publishing would look like it had always
 * been planned that way.
 *
 * A single item can produce more than one change (moved AND
 * reassigned), and each is recorded separately so a report can count
 * reassignments without untangling them from moves.
 */
export function diffPlan(
  before: ReadonlyArray<PublishableItem>,
  after: ReadonlyArray<PublishableItem>,
): PlanChange[] {
  const changes: PlanChange[] = [];
  const beforeByRef = new Map(before.map((i) => [itemRef(i), i]));
  const afterByRef = new Map(after.map((i) => [itemRef(i), i]));

  for (const [ref, b] of beforeByRef) {
    const a = afterByRef.get(ref);
    if (!a) {
      changes.push({change_type: 'removed', item_ref: ref, before: snap(b), after: null});
      continue;
    }
    if (a.seq !== b.seq) {
      changes.push({change_type: 'moved', item_ref: ref, before: {seq: b.seq}, after: {seq: a.seq}});
    }
    if (a.scheduled_minutes !== b.scheduled_minutes) {
      changes.push({
        change_type: 'duration_changed',
        item_ref: ref,
        before: {scheduled_minutes: b.scheduled_minutes},
        after: {scheduled_minutes: a.scheduled_minutes},
      });
    }
    if (a.assignee_agent_id !== b.assignee_agent_id) {
      changes.push({
        change_type: 'reassigned',
        item_ref: ref,
        before: {assignee_agent_id: b.assignee_agent_id},
        after: {assignee_agent_id: a.assignee_agent_id},
      });
    }
  }

  for (const [ref, a] of afterByRef) {
    if (!beforeByRef.has(ref)) {
      changes.push({change_type: 'added', item_ref: ref, before: null, after: snap(a)});
    }
  }

  return changes;
}

function snap(i: PublishableItem): Record<string, unknown> {
  return {
    seq: i.seq,
    scheduled_minutes: i.scheduled_minutes,
    assignee_agent_id: i.assignee_agent_id,
    planned_start: i.planned_start,
  };
}
