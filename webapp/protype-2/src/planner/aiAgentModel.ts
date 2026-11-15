/**
 * COP-5 story 06 — the copilot as someone on the plan. Pure rules, no React.
 *
 * A plan column (planner_agent) of kind "ai" becomes THE COPILOT when its login (`user_id`) is the
 * account copilot's own user (COP-1's identity) — there is no second "AI person". The copilot's
 * tasks are found by exactly that link (perform/resolve_agents), the same way a person's are.
 *
 * - Switched off (Manage users) → it is not offered new work, and its column shows a warning.
 * - Its capacity is its own: shown apart from people's hours, never added to them.
 */

export interface CopilotInfo {
  has_copilot: boolean;
  user_id: number;
  name: string;
  is_active: boolean;
}

export interface AgentLike {
  kind: 'person' | 'ai';
  userId?: string;
}

export type AiAgentState = 'person' | 'ai_unlinked' | 'copilot_on' | 'copilot_off';

export const COPILOT_OFF_MESSAGE =
  "The copilot is switched off, so it can't be given new work. An admin can switch it back on in Manage users, or pick someone else.";

/** Is this column linked to the account copilot's own login? Unknown copilot = no. */
export function isCopilotAgent(agent: AgentLike, copilot: CopilotInfo | null | undefined): boolean {
  if (!copilot || !copilot.has_copilot || !copilot.user_id) return false;
  return agent.userId != null && agent.userId !== '' && Number(agent.userId) === copilot.user_id;
}

export function aiAgentState(agent: AgentLike, copilot: CopilotInfo | null | undefined): AiAgentState {
  if (isCopilotAgent(agent, copilot)) return copilot!.is_active ? 'copilot_on' : 'copilot_off';
  return agent.kind === 'ai' ? 'ai_unlinked' : 'person';
}

/** True only when we KNOW it is the copilot and KNOW it is off — never block on a guess. */
export const isSwitchedOffCopilot = (agent: AgentLike, copilot: CopilotInfo | null | undefined): boolean =>
  aiAgentState(agent, copilot) === 'copilot_off';

/**
 * The login to save on a column. A person keeps the login picked for them (never the copilot's).
 * An AI column is either the account copilot (ticked) or nothing — an AI is never a person's login.
 *
 * Returns `null` for "leave the login exactly as it is" — the save must then OMIT `user_id`
 * (endpoint 536 keeps what is stored when the field is not sent). Final Fable review R3/R4/R12:
 * an edit that says nothing about the login must never clear it. That is the case when
 *  - the column was already an AI column and we cannot act on a known copilot (lookup failed, the
 *    account reports none, or it is linked to some other login and the box was not ticked);
 *  - a person column was already linked to the copilot's login (the old way of linking it).
 * `existing` is the column as stored; leave it out (or null) for a new column.
 */
export function agentUserIdToSave(
  kind: 'person' | 'ai',
  pickedUserId: string | undefined,
  linkCopilot: boolean,
  copilot: CopilotInfo | null | undefined,
  existing?: AgentLike | null,
): number | null {
  const copilotId = copilot && copilot.has_copilot ? copilot.user_id || 0 : 0;
  const existingId = existing && existing.userId ? Number(existing.userId) || 0 : 0;
  if (kind === 'ai') {
    if (copilotId !== 0 && linkCopilot) return copilotId;
    // Changing a person into an AI (or a new column): an AI never carries a person's login.
    if (!existing || existing.kind !== 'ai') return 0;
    // Already an AI column. Unticking a known copilot link (or an unlinked column) is a real "nothing".
    if (copilotId !== 0 && (existingId === 0 || existingId === copilotId)) return 0;
    return null;
  }
  const picked = pickedUserId ? Number(pickedUserId) : 0;
  if (!picked || Number.isNaN(picked)) return 0;
  if (copilotId !== 0 && picked === copilotId) {
    return existing && existing.kind === 'person' && existingId === picked ? null : 0;
  }
  return picked;
}

/**
 * The team member a PERSON column takes its name from. The copilot's own login is never that
 * member: a person column linked to it the old way keeps the name it has (review R4).
 */
export function pickedPersonMember<M extends {id: number}>(
  members: M[],
  pickedUserId: string | undefined,
  copilot: CopilotInfo | null | undefined,
): M | undefined {
  if (!pickedUserId) return undefined;
  const copilotId = copilot && copilot.has_copilot ? copilot.user_id || 0 : 0;
  const member = members.find((m) => String(m.id) === String(pickedUserId));
  return member && copilotId !== 0 && member.id === copilotId ? undefined : member;
}

export interface CapacityPart {
  capacityHours: number;
  plannedHours: number;
  openHours: number;
  count: number;
}

const round1 = (n: number) => Math.round(n * 10) / 10;

/** People's hours and AI hours, added up apart ("its capacity is its own"). */
export function splitCapacity(
  rows: {agent: {kind: 'person' | 'ai'}; capacityHours: number; plannedHours: number}[],
): {people: CapacityPart; ai: CapacityPart} {
  const part = (kind: 'person' | 'ai'): CapacityPart => {
    const mine = rows.filter((r) => r.agent.kind === kind);
    const capacity = mine.reduce((s, r) => s + r.capacityHours, 0);
    const planned = mine.reduce((s, r) => s + r.plannedHours, 0);
    return {
      capacityHours: round1(capacity),
      plannedHours: round1(planned),
      openHours: round1(capacity - planned),
      count: mine.length,
    };
  };
  return {people: part('person'), ai: part('ai')};
}
