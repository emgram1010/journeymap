// ITEM-1 (US-ITEM-1-01/02/03) — Thin client over the four new
// journey_map/* endpoints. Same group as every other map-editor call
// (xano.ts's default getXanoBaseUrl()), so no baseUrl override is
// needed here, unlike catalogApi.ts's own catalog group.
import {xanoRequest} from '../xano';
import type {NormalizedItemsCellLine} from './itemsCellValidation';

function newCorrelationId(): string {
  return `item-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export interface ItemsRowLens {
  id: number;
  journey_map: number;
  key: string;
  label: string;
  actor_type: string;
  template_key: string;
  display_order: number;
}

export interface ItemsRowCell {
  id: number;
  journey_map: number;
  stage: number;
  lens: number;
  actor_fields: {scales_with: string; lines: NormalizedItemsCellLine[]};
}

export interface CreateItemsRowResult {
  lens: ItemsRowLens;
  cells: ItemsRowCell[];
  journey_map_updated_at: string;
}

export const createItemsRow = (journeyMapId: number) =>
  xanoRequest<CreateItemsRowResult>(`/journey_map/${journeyMapId}/items-row`, {
    method: 'POST',
    body: {correlation_id: newCorrelationId()},
  });

export const deleteItemsRow = (journeyMapId: number) =>
  xanoRequest<{deleted: boolean; removed_cells: number; removed_links: number}>(
    `/journey_map/${journeyMapId}/items-row`,
    {method: 'DELETE'},
  );

export interface ItemsRowItem {
  id: number;
  journey_lens: number;
  item_type_id: number;
  sort_order: number;
}

export const setItemsRowItems = (journeyMapId: number, itemTypeIds: number[]) =>
  xanoRequest<{items: ItemsRowItem[]; removed_count: number; touched_cells: number}>(
    `/journey_map/${journeyMapId}/items-row/items`,
    {
      method: 'PUT',
      body: {item_type_ids: itemTypeIds, correlation_id: newCorrelationId()},
    },
  );

export interface ChosenItemDetail {
  item_type_id: number;
  key: string;
  label: string;
  unit: string;
  default_method_id: number;
  is_active: boolean;
}

/** The map's CURRENT chosen-item set, joined with item_type for display. */
export const getItemsRowItems = (journeyMapId: number) =>
  xanoRequest<{items_lens_id: number | null; items: ChosenItemDetail[]}>(
    `/journey_map/${journeyMapId}/items-row/items`,
  );

export const saveItemsCell = (
  journeyMapId: number,
  journeyCellId: number,
  input: {scales_with: string; lines: Array<{item_key: string; method_key: string; minutes_per_unit?: number | null}>},
) =>
  xanoRequest<{cell: ItemsRowCell; links_added: number; links_removed: number}>(
    `/journey_map/${journeyMapId}/items-cell/${journeyCellId}`,
    {
      method: 'PATCH',
      body: {...input, correlation_id: newCorrelationId()},
    },
  );
