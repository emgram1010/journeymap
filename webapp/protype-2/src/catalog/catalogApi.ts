// CAT-1 (US-CAT-1-04) — Thin client over the catalog/* endpoints.
// Reuses the existing xanoRequest helper (auth header, correlation id,
// XanoHttpError on failure) rather than a parallel fetch mechanism.
import {xanoRequest, getXanoCatalogBaseUrl} from '../xano';
import type {ItemType, CatalogMethod} from './catalogTypes';

const baseUrl = () => getXanoCatalogBaseUrl();

function newCorrelationId(): string {
  // Matches the shape used elsewhere in this app (a plain random id is
  // enough — the server never trusts this for anything but echoing back
  // as "Reference").
  return `cat-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export interface ListItemTypesResult {
  items: ItemType[];
}

export interface ListMethodsResult {
  methods: CatalogMethod[];
}

export const listItemTypes = (includeInactive = false) =>
  xanoRequest<ListItemTypesResult>(`/item-type${includeInactive ? '?include_inactive=true' : ''}`, {baseUrl: baseUrl()});

export const createItemType = (input: {
  key: string;
  label: string;
  unit?: string;
  default_method_id?: number;
  size_label?: string;
  external_ref?: string;
}) =>
  xanoRequest<{item_type: ItemType}>('/item-type', {
    method: 'POST',
    body: {...input, correlation_id: newCorrelationId()},
    baseUrl: baseUrl(),
  });

export const updateItemType = (
  id: number,
  input: Partial<{
    label: string;
    unit: string;
    default_method_id: number;
    size_label: string;
    external_ref: string;
    is_active: boolean;
  }>,
) =>
  xanoRequest<{item_type: ItemType}>(`/item-type/${id}`, {
    method: 'PATCH',
    body: {...input, correlation_id: newCorrelationId()},
    baseUrl: baseUrl(),
  });

export const deactivateItemType = (id: number) =>
  xanoRequest<{item_type: ItemType}>(`/item-type/${id}/deactivate`, {
    method: 'POST',
    body: {correlation_id: newCorrelationId()},
    baseUrl: baseUrl(),
  });

// No body on DELETE, matching every other delete call already in this
// app (removeJourneyStage, deleteJourneyMap, ...) — untested precedent
// otherwise, and the backend's correlation_id input is optional anyway.
export const deleteItemType = (id: number) =>
  xanoRequest<{deleted: boolean; item_type_id: number}>(`/item-type/${id}`, {method: 'DELETE', baseUrl: baseUrl()});

export const listMethods = (includeInactive = false) =>
  xanoRequest<ListMethodsResult>(`/method${includeInactive ? '?include_inactive=true' : ''}`, {baseUrl: baseUrl()});

export const createMethod = (input: {key: string; label: string; sub_journey_map_id?: number}) =>
  xanoRequest<{method: CatalogMethod}>('/method', {
    method: 'POST',
    body: {...input, correlation_id: newCorrelationId()},
    baseUrl: baseUrl(),
  });

export const updateMethod = (
  id: number,
  input: Partial<{label: string; sub_journey_map_id: number; is_active: boolean}>,
) =>
  xanoRequest<{method: CatalogMethod}>(`/method/${id}`, {
    method: 'PATCH',
    body: {...input, correlation_id: newCorrelationId()},
    baseUrl: baseUrl(),
  });

export const deactivateMethod = (id: number) =>
  xanoRequest<{method: CatalogMethod}>(`/method/${id}/deactivate`, {
    method: 'POST',
    body: {correlation_id: newCorrelationId()},
    baseUrl: baseUrl(),
  });

export const deleteMethod = (id: number) =>
  xanoRequest<{deleted: boolean; method_id: number}>(`/method/${id}`, {method: 'DELETE', baseUrl: baseUrl()});
