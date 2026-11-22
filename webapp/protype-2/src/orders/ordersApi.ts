// Orders — thin client over the outside-product endpoints (catalog group)
// and the incoming-order endpoints (planner group). Two API groups means
// two base URLs: each call names its own, or it would 404 against the
// journey-map group with no hint why.
import {xanoRequest, getXanoCatalogBaseUrl} from '../xano';
import {getPlannerBaseUrl} from '../perform/performApi';
import type {ExternalRef, OrderSetup} from './ordersModel';

const catalogBase = () => getXanoCatalogBaseUrl();
const plannerBase = () => getPlannerBaseUrl();

/** Where an order system sends its orders. Shown to the admin as instructions. */
export const orderInboundUrl = () => `${plannerBase()}/order-inbound`;

// ── Outside products (catalog group) ─────────────────────────────────────

export interface ExternalRefsResult {
  refs: ExternalRef[];
  to_link: number;
}

export const listExternalRefs = () => xanoRequest<ExternalRefsResult>('/item_external_refs', {baseUrl: catalogBase()});

export interface SetExternalRefInput {
  ref_id?: number;
  source_system?: string;
  external_id?: string;
  external_name?: string;
  item_type_id?: number;
  not_an_item?: boolean;
  /** Send true only after the person confirmed moving a product that is linked elsewhere. */
  move?: boolean;
}

export interface SetExternalRefResult {
  status: 'saved' | 'move_needed';
  ref_id: number;
  item_type_id: number;
  not_an_item: boolean;
  current_item_type_id: number;
}

export const setExternalRef = (input: SetExternalRefInput) =>
  xanoRequest<SetExternalRefResult>('/item_external_ref_set', {method: 'POST', body: {...input}, baseUrl: catalogBase()});

// ── Incoming orders (planner group) ──────────────────────────────────────

export const getOrderSetup = () => xanoRequest<OrderSetup>('/order-setup', {baseUrl: plannerBase()});

const change = <T>(body: Record<string, unknown>) =>
  xanoRequest<T>('/order-setup-change', {method: 'POST', body, baseUrl: plannerBase()});

export interface SaveRouteInput {
  source_system: string;
  match_fulfilment: string;
  workspace_id: number;
  journey_map_id: number;
  route_id?: number;
  disabled?: boolean;
}

export const saveOrderRoute = (input: SaveRouteInput) => change<{status: string}>({action: 'route_save', ...input});

export const deleteOrderRoute = (routeId: number) => change<{status: string}>({action: 'route_delete', route_id: routeId});

/** The key comes back ONCE. The caller shows it and must not store it anywhere. */
export const createOrderKey = (sourceSystem: string) =>
  change<{status: string; order_key: string}>({action: 'key_create', source_system: sourceSystem});

export const clearOrderFlag = (workItemId: number) => change<{status: string}>({action: 'flag_clear', work_item_id: workItemId});

export const retryOrder = (orderInboxId: number) =>
  change<{outcome: string; detail: string}>({action: 'retry', order_inbox_id: orderInboxId});

/** Pick the member whose live day takes same-day orders of one rule. 0 switches it off. */
export const saveLiveMember = (routeId: number, agentId: number) =>
  change<{status: string}>({action: 'live_member_save', route_id: routeId, agent_id: agentId});

/** Try to put one order's job onto its live day. `detail` says what happened, in a sentence. */
export const placeOrderOnLiveDay = (workItemId: number) =>
  change<{status: string; placed: boolean; reason: string; detail: string}>({action: 'place_live', work_item_id: workItemId});
