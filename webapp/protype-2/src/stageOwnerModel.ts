import type {ActorType, Lens} from './types';

/**
 * STAGE-1 (US-STAGE-1-02) — frontend mirror of functions/resolve_stage_owner.xs.
 * Resolves a primary_actor_lens text key to a lens in the same map.
 * Pure; never throws. An empty/null key resolves to "no owner" (not an error).
 */
export function resolveOwner(
  key: string | null | undefined,
  lenses: Pick<Lens, 'key' | 'xanoId'>[],
): {resolved: true; ownerLensId: number | null} | {resolved: false; reason: string} {
  if (key == null || key === '') {
    return {resolved: true, ownerLensId: null};
  }
  const match = lenses.find((l) => l.key === key);
  if (match && match.xanoId != null) {
    return {resolved: true, ownerLensId: match.xanoId};
  }
  return {resolved: false, reason: `no lens in this map matches key '${key}'`};
}

const PLANNED_WORK_DEFAULT_TYPES: ActorType[] = ['internal', 'ai_agent'];

/**
 * STAGE-1 (US-STAGE-1-06) — frontend mirror of functions/does_planned_work.xs.
 * An explicit override always wins; otherwise the default comes from actor_type.
 */
export function doesPlannedWork(
  actorType: ActorType | null | undefined,
  override: boolean | null | undefined,
): boolean {
  if (override != null) return override;
  return actorType != null && PLANNED_WORK_DEFAULT_TYPES.includes(actorType);
}
