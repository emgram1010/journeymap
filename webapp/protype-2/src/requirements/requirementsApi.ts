// REQ-1 — thin client over the requirement endpoints. Three Xano groups are involved, so the base
// URL is chosen per call: the account's LIST lives in the catalog group, a map's step needs in the
// journey-map group (the default base of xanoRequest). A person's holdings and the plan-person links
// live in the planner group and are in planner/plannerApi.ts. Reuses xanoRequest (auth header,
// correlation id, XanoHttpError with `serverMessage`).
import {xanoRequest, getXanoCatalogBaseUrl} from '../xano';
import type {Strength} from './requirementModel';

const catalog = () => getXanoCatalogBaseUrl();

const correlationId = () => `req-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

export interface Requirement {
  id: number;
  name: string;
  description: string;
  is_active: boolean;
  used_by_steps: number;
  held_by_people: number;
  in_versions: number;
}

export interface RequirementMatch {
  id: number;
  name: string;
  is_active: boolean;
}

export type AddAnswer = {
  /** created | exists (the same name already there) | similar (near matches, nothing created yet) */
  outcome: 'created' | 'exists' | 'similar';
  requirement: {id: number; name: string; is_active: boolean} | null;
  matches: RequirementMatch[];
};

export const listRequirements = (includeArchived = false) =>
  xanoRequest<{requirements: Requirement[]; limit: number}>(`/requirement${includeArchived ? '?include_archived=true' : ''}`, {baseUrl: catalog()});

export const addRequirement = (input: {name: string; description?: string; confirm_similar?: boolean}) =>
  xanoRequest<AddAnswer>('/requirement', {method: 'POST', body: {...input, correlation_id: correlationId()}, baseUrl: catalog()});

export const renameRequirement = (id: number, input: {name?: string; description?: string}) =>
  xanoRequest<{requirement: Requirement}>(`/requirement/${id}`, {method: 'PATCH', body: {...input, correlation_id: correlationId()}, baseUrl: catalog()});

export const archiveRequirement = (id: number, isArchived: boolean) =>
  xanoRequest<{requirement: Requirement}>(`/requirement/${id}/archive`, {method: 'POST', body: {is_archived: isArchived, correlation_id: correlationId()}, baseUrl: catalog()});

export const deleteRequirement = (id: number) =>
  xanoRequest<{deleted_requirement_id: number}>(`/requirement/${id}`, {method: 'DELETE', body: {correlation_id: correlationId()}, baseUrl: catalog()});

export interface Holder {
  agent_profile_id: number;
  name: string;
  held_until: string;
  held: boolean;
  ends_soon: boolean;
  days_left: number | null;
}

export const listHolders = (requirementId: number, onDate?: string) =>
  xanoRequest<{holders: Holder[]; on_date: string}>(`/requirement/${requirementId}/holders${onDate ? `?on_date=${onDate}` : ''}`, {baseUrl: catalog()});

// ── a map's steps (journey-map group) ────────────────────────────────────────────────────────────
export interface StepNeed {
  journey_cell_id: number;
  stage_key: string;
  lens_key: string;
  requirement_id: number;
  name: string;
  archived: boolean;
  strength: Strength;
  holders_now: number;
}

export const listMapNeeds = (mapId: number) => xanoRequest<{needs: StepNeed[]; on_date: string}>(`/journey_map/${mapId}/requirement`);

export const setStepNeed = (cellId: number, requirementId: number, strength: Strength) =>
  xanoRequest<{result: 'added' | 'changed' | 'same'}>(`/journey_cell/${cellId}/requirement`, {
    method: 'POST',
    body: {requirement_id: requirementId, strength, correlation_id: correlationId()},
  });

export const removeStepNeed = (cellId: number, requirementId: number) =>
  xanoRequest<{removed: boolean}>(`/journey_cell/${cellId}/requirement/${requirementId}`, {method: 'DELETE', body: {correlation_id: correlationId()}});

export interface RowApplyAnswer {
  steps_in_row: number;
  added: number;
  changed: number;
  already_there: number;
  refused: {journey_cell_id: number; code: string}[];
  steps_with_it_now: number;
}

export const applyNeedToRow = (mapId: number, lensId: number, requirementId: number, strength: Strength) =>
  xanoRequest<RowApplyAnswer>(`/journey_map/${mapId}/row-requirement`, {
    method: 'POST',
    body: {journey_lens_id: lensId, requirement_id: requirementId, strength, correlation_id: correlationId()},
  });
