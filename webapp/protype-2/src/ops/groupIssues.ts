// OBS-1 (US-OBS-1-06, grouping) — Frontend mirror of the backend's
// ops/group_issues.xs grouping logic, kept for display (e.g. re-grouping
// a bundle's events client-side) and so the algorithm itself is unit
// tested. The backend is the source of truth for the Health page's issue
// list (GET /ops/issues); this function must produce the same grouping
// for the same input.
import {fingerprint} from './fingerprint';

export interface OpsEvent {
  feature: string | null;
  step: string | null;
  error_code?: string | null;
  severity?: string | null;
  created_at: string;
  message?: string | null;
}

export interface GroupedIssue {
  fingerprint: string;
  feature: string | null;
  step: string | null;
  error_code: string | null;
  severity: string;
  count: number;
  first_seen: string;
  last_seen: string;
  latest_message: string | null;
}

/**
 * Groups events (expected to already be filtered to failure/rejected
 * outcomes by the caller) into issues, in first-seen order. Assumes the
 * input is sorted ascending by created_at, same as the backend's query.
 */
export function groupIssues(events: OpsEvent[]): GroupedIssue[] {
  const byFingerprint = new Map<string, GroupedIssue>();
  const order: string[] = [];

  for (const event of events) {
    const fp = fingerprint({feature: event.feature, step: event.step, errorCode: event.error_code});
    const existing = byFingerprint.get(fp);

    if (!existing) {
      byFingerprint.set(fp, {
        fingerprint: fp,
        feature: event.feature,
        step: event.step,
        error_code: event.error_code ?? null,
        severity: event.severity ?? 'error',
        count: 1,
        first_seen: event.created_at,
        last_seen: event.created_at,
        latest_message: event.message ?? null,
      });
      order.push(fp);
    } else {
      existing.count += 1;
      existing.last_seen = event.created_at;
      existing.latest_message = event.message ?? existing.latest_message;
    }
  }

  return order.map((fp) => byFingerprint.get(fp)!);
}
