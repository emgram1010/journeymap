// AIM-1 — AI members: the pure rules the screen can know before the round trip.
//
// Everything here is a COURTESY. The server (functions/aim/*) checks every rule again and is
// the only authority. No React and no network in this file, so it runs under node:test.

export type AiAction = 'read' | 'draft_map' | 'draft_plan' | 'own_work';

/** The four things an AI member can be allowed to do, in the order the form shows them. */
export const AI_ACTIONS: readonly AiAction[] = ['read', 'draft_map', 'draft_plan', 'own_work'] as const;

export const AI_ACTION_LABELS: Record<AiAction, string> = {
  read: 'Read maps and plans',
  draft_map: 'Edit draft maps',
  draft_plan: 'Draft plans',
  own_work: 'Record its own work',
};

/** Plain words for an action key. An unknown key is shown as it is rather than hidden. */
export function actionLabel(action: string): string {
  return (AI_ACTION_LABELS as Record<string, string>)[action] ?? action;
}

/** "Read maps and plans, Draft plans", or "Nothing yet" for an empty or missing list. */
export function actionsSummary(actions: readonly string[] | null | undefined): string {
  const list = actions ?? [];
  return list.length === 0 ? 'Nothing yet' : list.map(actionLabel).join(', ');
}

export interface AiToken {
  token_id: number;
  label: string;
  scope_actions: string[] | null;
  created_at: number | string | null;
  created_by_user_id: number | null;
  last_used_at: number | string | null;
  expires_at: number | string | null;
  revoked: boolean;
  live: boolean;
}

export interface AiMember {
  user_id: number;
  name: string;
  manager_user_id: number;
  manager_name: string;
  needs_manager: boolean;
  purpose: string;
  allowed_actions: string[] | null;
  plan_ids: number[] | null;
  is_paused: boolean;
  paused_reason: string;
  writes_per_hour: number;
  writes_per_day: number;
  tokens: AiToken[] | null;
  calls_today: number;
  writes_today: number;
  refused_last_7_days: number;
}

export interface AiPlan {
  id: number;
  name: string;
}

export interface AiOverview {
  all_paused: boolean;
  grantable: string[] | null;
  members: AiMember[] | null;
  plans: AiPlan[] | null;
}

/** The slice of a Manage-users row this file needs. `TeamMember` fits it as it is. */
export interface AimPerson {
  id: number;
  name: string;
  email: string;
  role: string;
  is_active: boolean;
  is_owner: boolean;
}

/** What the Edit / "Make a login an AI member" form holds. `manager_user_id: 0` = none picked. */
export interface AiProfileDraft {
  user_id: number;
  manager_user_id: number;
  purpose: string;
  allowed_actions: string[];
  plan_ids: number[];
}

export const PURPOSE_MAX = 200;

/** The first reason this draft cannot be saved, as a sentence, or null when nothing stops it. */
export function profileProblem(draft: AiProfileDraft): string | null {
  if (!(draft.manager_user_id > 0)) return 'Pick a person to be its manager.';
  const purpose = draft.purpose.trim();
  if (purpose === '') return 'Say what this AI member is for.';
  if (purpose.length > PURPOSE_MAX) return `Keep the purpose to ${PURPOSE_MAX} characters or fewer.`;
  if (/[<>]/.test(purpose)) return 'The purpose cannot contain < or >.';
  if (draft.allowed_actions.length === 0) return 'Tick at least one thing it may do.';
  if (draft.manager_user_id === draft.user_id) return 'An AI member cannot be its own manager.';
  return null;
}

/** Logins that can be made an AI member: ordinary members, not the owner, not you, not already AI. */
export function candidateLogins<T extends AimPerson>(
  members: readonly T[] | null | undefined,
  aiUserIds: readonly number[] | null | undefined,
  viewerId: number | null | undefined,
): T[] {
  const ai = new Set(aiUserIds ?? []);
  return (members ?? []).filter((m) => m.role === 'member' && !m.is_owner && m.id !== viewerId && !ai.has(m.id));
}

/** Who can be a manager: switched-on people who are not AI and not the AI member itself. */
export function managerChoices<T extends AimPerson>(
  members: readonly T[] | null | undefined,
  aiUserIds: readonly number[] | null | undefined,
  targetId: number,
): T[] {
  const ai = new Set(aiUserIds ?? []);
  return (members ?? []).filter((m) => m.is_active === true && !ai.has(m.id) && m.id !== targetId);
}

/** A stored time as milliseconds, or null when there is none (0, "" and null all mean "none"). */
export function toMs(value: number | string | null | undefined): number | null {
  if (value == null || value === '' || value === 0) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  const asNumber = Number(value);
  if (Number.isFinite(asNumber)) return asNumber === 0 ? null : asNumber;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

export type TokenState = 'live' | 'revoked' | 'expired';

/** Revoked wins over expired. A token with no expiry time does not expire by the clock. */
export function tokenState(
  token: Pick<AiToken, 'revoked' | 'expires_at'> & {live?: boolean},
  nowMs: number,
): TokenState {
  if (token.revoked === true) return 'revoked';
  const expires = toMs(token.expires_at);
  if (expires != null && expires <= nowMs) return 'expired';
  return 'live';
}

export const TOKEN_STATE_LABELS: Record<TokenState, string> = {
  live: 'Working',
  revoked: 'Cancelled',
  expired: 'Expired',
};

export type MemberStatus = 'Paused for everyone' | 'Switched off' | 'Needs a manager' | 'Working';

export function memberStatus(
  member: Pick<AiMember, 'is_paused' | 'needs_manager'>,
  allPaused: boolean,
): MemberStatus {
  if (allPaused === true) return 'Paused for everyone';
  if (member.is_paused === true) return 'Switched off';
  if (member.needs_manager === true) return 'Needs a manager';
  return 'Working';
}

/** Plan names for a list of ids, in the given order. A plan that is gone shows as "Plan 12". */
export function planNames(
  planIds: readonly number[] | null | undefined,
  plans: readonly AiPlan[] | null | undefined,
): string[] {
  const byId = new Map<number, string>();
  for (const p of plans ?? []) byId.set(p.id, p.name);
  return (planIds ?? []).map((id) => byId.get(id) || `Plan ${id}`);
}

/** "3 calls, 1 change today · 0 refused this week" */
export function todayLine(member: Pick<AiMember, 'calls_today' | 'writes_today' | 'refused_last_7_days'>): string {
  const calls = member.calls_today || 0;
  const writes = member.writes_today || 0;
  const refused = member.refused_last_7_days || 0;
  return `${calls} ${calls === 1 ? 'call' : 'calls'}, ${writes} ${writes === 1 ? 'change' : 'changes'} today · ${refused} refused this week`;
}
