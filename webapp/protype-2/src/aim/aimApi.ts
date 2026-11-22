// AIM-1 — AI members: the two server calls, typed. Both live in the Members & Accounts group,
// the same base URL the Manage users page already uses.
//
// Only an admin who is a person may call either; the server refuses everyone else.
import {getXanoMembersBaseUrl, xanoRequest} from '../xano';
import type {AiOverview} from './aimModel';

const ACTION_PATH = '/admin/ai_member_action';

function act<T>(body: Record<string, unknown>): Promise<T> {
  return xanoRequest<T>(ACTION_PATH, {method: 'POST', body, baseUrl: getXanoMembersBaseUrl()});
}

/** Everything the AI members section shows. No token or secret is ever in this answer. */
export function getAiMembers(): Promise<AiOverview> {
  return xanoRequest<AiOverview>('/admin/ai_members', {baseUrl: getXanoMembersBaseUrl()});
}

export interface SaveAiMemberInput {
  user_id: number;
  manager_user_id: number;
  purpose: string;
  allowed_actions: string[];
  plan_ids: number[];
  /** Left out = the server's standard limit. Send the current value when editing, to keep it. */
  writes_per_hour?: number;
  writes_per_day?: number;
}

/** Make a login an AI member, or change an AI member's job. */
export function saveAiMember(input: SaveAiMemberInput): Promise<unknown> {
  const body: Record<string, unknown> = {
    action: 'save',
    user_id: input.user_id,
    manager_user_id: input.manager_user_id,
    purpose: input.purpose,
    allowed_actions: input.allowed_actions,
    plan_ids: input.plan_ids,
  };
  if (input.writes_per_hour != null && input.writes_per_hour > 0) body.writes_per_hour = input.writes_per_hour;
  if (input.writes_per_day != null && input.writes_per_day > 0) body.writes_per_day = input.writes_per_day;
  return act(body);
}

/** Switch an AI member off or back on. Switching off also cancels every access token it has. */
export function switchAiMember(userId: number, turnOn: boolean): Promise<{is_on: boolean; tokens_revoked: number}> {
  return act({action: 'switch', user_id: userId, turn_on: turnOn});
}

export interface CreatedAiToken {
  token_id: number;
  /** Returned ONCE, here. Never store it. */
  token: string;
  label: string;
  expires_in_days: number;
}

export function createAiToken(userId: number, label: string, scopeActions?: string[]): Promise<CreatedAiToken> {
  const body: Record<string, unknown> = {action: 'token_create', user_id: userId, label};
  if (scopeActions && scopeActions.length > 0) body.scope_actions = scopeActions;
  return act<CreatedAiToken>(body);
}

export function revokeAiToken(tokenId: number): Promise<unknown> {
  return act({action: 'token_revoke', token_id: tokenId});
}

/** Pause (or un-pause) every AI member in the account at once. */
export function pauseAllAi(paused: boolean): Promise<{is_paused: boolean}> {
  return act({action: 'pause_all', paused});
}
