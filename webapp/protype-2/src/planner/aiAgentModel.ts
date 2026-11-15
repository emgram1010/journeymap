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
 */
export function agentUserIdToSave(
  kind: 'person' | 'ai',
  pickedUserId: string | undefined,
  linkCopilot: boolean,
  copilot: CopilotInfo | null | undefined,
): number {
  const copilotId = copilot && copilot.has_copilot ? copilot.user_id || 0 : 0;
  if (kind === 'ai') return linkCopilot ? copilotId : 0;
  const picked = pickedUserId ? Number(pickedUserId) : 0;
  if (!picked || Number.isNaN(picked)) return 0;
  return copilotId !== 0 && picked === copilotId ? 0 : picked;
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
