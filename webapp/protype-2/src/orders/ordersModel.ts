// Orders — shared shapes and pure rules for the "Outside products" and
// "Incoming orders" tabs. No network and no React in here, so every rule
// can be unit-tested on its own (ordersModel.test.ts, UT-ORD-01…).

/** A product as an outside order system names it, and what it is linked to here. */
export interface ExternalRef {
  ref_id: number;
  source_system: string;
  external_id: string;
  external_name: string;
  /** 0 = not linked to a catalog item. */
  item_type_id: number;
  /** True for things that are not work, such as fees and deposits. */
  not_an_item: boolean;
  seen_count: number;
  last_seen_at: number | string | null;
}

export interface OrderRoute {
  route_id: number;
  source_system: string;
  /** "" = any fulfilment type. */
  match_fulfilment: string;
  workspace_id: number;
  journey_map_id: number;
  is_enabled: boolean;
  has_key: boolean;
}

export type OrderOutcome = 'no_route' | 'held' | 'failed' | 'refused';

export interface OrderNeedingPerson {
  order_inbox_id: number;
  source_system: string;
  order_number: string;
  external_id: string;
  outcome: OrderOutcome | string;
  detail: string;
  received_at: number | string | null;
}

export type OrderFlag = 'order_changed' | 'order_cancelled';

export interface FlaggedJob {
  work_item_id: number;
  source_system: string;
  order_number: string;
  order_flag: OrderFlag | string;
  starts_on: string | null;
}

export interface OrderCounts {
  created: number;
  updated: number;
  duplicate: number;
  flagged: number;
  no_route: number;
  held: number;
  refused: number;
  failed: number;
}

export interface PlanMap {
  workspace_id: number;
  journey_map_id: number;
}

export interface OrderSetup {
  routes: OrderRoute[];
  needs_person: OrderNeedingPerson[];
  flagged: FlaggedJob[];
  last_24_hours: OrderCounts;
  plans: {id: number; name: string}[];
  plan_maps: PlanMap[];
}

export type RefStatus = 'Linked' | 'Not an item' | 'Needs linking';

/** The products nobody has dealt with yet: no item, and not marked "not an item". */
export function toLink(refs: ExternalRef[]): ExternalRef[] {
  return refs.filter((r) => !r.item_type_id && !r.not_an_item);
}

export function refStatus(ref: Pick<ExternalRef, 'item_type_id' | 'not_an_item'>): RefStatus {
  if (ref.not_an_item) return 'Not an item';
  if (ref.item_type_id) return 'Linked';
  return 'Needs linking';
}

/**
 * Why an order-system name cannot be used, or null when it is fine.
 * 2 to 40 lower-case letters, digits or hyphens, starting with a letter or digit.
 */
export function sourceNameProblem(name: string): string | null {
  const value = name.trim();
  if (value === '') return 'Give the order system a name.';
  if (value.length < 2) return 'The name needs at least 2 characters.';
  if (value.length > 40) return 'The name can be 40 characters at most.';
  if (!/^[a-z0-9-]+$/.test(value)) return 'Use lower-case letters, numbers and hyphens only.';
  if (value.startsWith('-')) return 'The name must start with a letter or a number.';
  return null;
}

/** The map ids one plan uses, in the order given, with no repeats. */
export function mapsForPlan(planId: number, planMaps: PlanMap[]): number[] {
  const ids: number[] = [];
  for (const pm of planMaps) {
    if (pm.workspace_id === planId && !ids.includes(pm.journey_map_id)) ids.push(pm.journey_map_id);
  }
  return ids;
}

const OUTCOME_LABELS: Record<string, string> = {
  no_route: 'No routing rule matched',
  held: 'Held while AI is paused',
  failed: 'Could not be added',
  refused: 'Refused',
  created: 'Added as a new job',
  updated: 'Updated the existing job',
  duplicate: 'Already received',
  flagged: 'Flagged for a check',
};

/** What happened to an order, in plain words. */
export function outcomeLabel(outcome: string): string {
  return OUTCOME_LABELS[outcome] ?? 'Needs a look';
}

const FLAG_LABELS: Record<string, string> = {
  order_changed: 'Order changed after work started',
  order_cancelled: 'Order cancelled',
};

/** Why a job needs checking, in plain words. */
export function flagLabel(flag: string): string {
  return FLAG_LABELS[flag] ?? 'Needs a check';
}
