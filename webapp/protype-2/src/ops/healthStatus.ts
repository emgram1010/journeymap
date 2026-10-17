// OBS-1 (US-OBS-1-05, US-OBS-1-07) — Turns a heartbeat age and an open
// issue count into the Health page's status tile color. A heartbeat
// older than 15 minutes means something is badly wrong (the heartbeat
// task itself may be down), so it always wins over the issue count.
export type HealthStatusLevel = 'green' | 'amber' | 'red';

export const HEARTBEAT_STALE_MS = 15 * 60 * 1000;

export interface HealthStatusResult {
  level: HealthStatusLevel;
  reason: string;
}

/**
 * @param heartbeatAgeMs - milliseconds since the last successful
 *   heartbeat event, or null when no heartbeat has ever been seen.
 * @param openIssuesCount - number of distinct grouped issues currently open.
 */
export function healthStatus(heartbeatAgeMs: number | null, openIssuesCount: number): HealthStatusResult {
  if (heartbeatAgeMs === null) {
    return {level: 'red', reason: 'No heartbeat has ever been recorded.'};
  }

  if (heartbeatAgeMs > HEARTBEAT_STALE_MS) {
    return {level: 'red', reason: 'No heartbeat in the last 15 minutes.'};
  }

  if (openIssuesCount > 0) {
    return {level: 'amber', reason: `${openIssuesCount} open issue${openIssuesCount === 1 ? '' : 's'}.`};
  }

  return {level: 'green', reason: 'Everything looks normal.'};
}
