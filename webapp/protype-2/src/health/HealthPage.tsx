// OBS-1 (US-OBS-1-07) — The Health page. Admin-only (enforced server-side
// by every ops/* endpoint, and by AdminRoute client-side in main.tsx).
// Written for a product manager, not an engineer: plain language, no
// code, no stack traces. Acknowledge is deferred (US-OBS-1-06); every
// issue found in the window is shown.
import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
  getOpsBundle,
  getOpsHealth,
  getOpsIssues,
  getOpsEstimates,
  getOpsExceptions,
  type OpsExceptionsResponse,
  type OpsHealthResponse,
  type OpsIssue,
  type OpsEstimateJobRow,
} from '../xano';
import {healthStatus, type HealthStatusLevel} from '../ops/healthStatus';

const STATUS_COLORS: Record<HealthStatusLevel, string> = {
  green: 'bg-emerald-100 text-emerald-800 border-emerald-300',
  amber: 'bg-amber-100 text-amber-800 border-amber-300',
  red: 'bg-red-100 text-red-800 border-red-300',
};

const STATUS_LABELS: Record<HealthStatusLevel, string> = {
  green: 'All good',
  amber: 'Needs attention',
  red: 'Something is wrong',
};

const OWNER_LABELS: Record<string, string> = {
  user: 'The user can fix this themselves',
  product_manager: 'You can fix this',
  engineer: 'Needs an engineer or the AI',
};

function minutesAgo(iso: string | null): number | null {
  if (!iso) return null;
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return null;
  return Math.round((Date.now() - then) / 60000);
}

async function copyBundleToClipboard(issue: OpsIssue) {
  if (!issue.sample_correlation_id) return false;
  try {
    const bundle = await getOpsBundle({correlationId: issue.sample_correlation_id});
    const text = JSON.stringify(bundle, null, 2);
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

import {openChildSentence, reasonWords} from '../exceptions/healthText';

export default function HealthPage() {
  const [health, setHealth] = useState<OpsHealthResponse | null>(null);
  const [issues, setIssues] = useState<OpsIssue[]>([]);
  const [estimateJobs, setEstimateJobs] = useState<OpsEstimateJobRow[]>([]);
  // EXC-1 (US-EXC-1-07) — additive; never blanks the rest of the page.
  const [exceptions, setExceptions] = useState<OpsExceptionsResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [copiedFingerprint, setCopiedFingerprint] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [healthData, issuesData, estimatesData, exceptionsData] = await Promise.all([
        getOpsHealth(),
        getOpsIssues(),
        // EST-1's own panel; a failure here should never blank the rest
        // of the page — it's additive, not load-bearing.
        getOpsEstimates().catch(() => ({since: '', count: 0, jobs: []})),
        getOpsExceptions().catch(() => null),
      ]);
      setHealth(healthData);
      setIssues(issuesData.issues);
      setEstimateJobs(estimatesData.jobs);
      setExceptions(exceptionsData);
    } catch (e) {
      setError('We could not load the Health page right now. Try reloading.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const status = useMemo(() => {
    if (!health) return null;
    const ageMs = health.last_heartbeat_at ? Date.now() - new Date(health.last_heartbeat_at).getTime() : null;
    return healthStatus(ageMs, health.open_issues_count);
  }, [health]);

  const handleCopy = async (issue: OpsIssue) => {
    const ok = await copyBundleToClipboard(issue);
    setCopiedFingerprint(ok ? issue.fingerprint : null);
    if (ok) setTimeout(() => setCopiedFingerprint(null), 2000);
  };

  if (loading) {
    return <div className="p-8 text-sm text-zinc-500">Checking system health…</div>;
  }

  if (error) {
    return <div className="p-8 text-sm text-red-700">{error}</div>;
  }

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-6">
      <h1 className="text-xl font-semibold text-zinc-900">System health</h1>

      {status && (
        <div className={`rounded-lg border px-4 py-3 ${STATUS_COLORS[status.level]}`}>
          <div className="font-medium">{STATUS_LABELS[status.level]}</div>
          <div className="text-sm">{status.reason}</div>
        </div>
      )}

      {health && (
        <div className="grid grid-cols-3 gap-4 text-sm">
          <div className="rounded border border-zinc-200 p-3">
            <div className="text-zinc-500">Failures in the last 24 hours</div>
            <div className="text-2xl font-semibold text-zinc-900">{health.failures_24h}</div>
          </div>
          <div className="rounded border border-zinc-200 p-3">
            <div className="text-zinc-500">Open issues</div>
            <div className="text-2xl font-semibold text-zinc-900">{health.open_issues_count}</div>
          </div>
          <div className="rounded border border-zinc-200 p-3">
            <div className="text-zinc-500">Last heartbeat</div>
            <div className="text-2xl font-semibold text-zinc-900">
              {health.last_heartbeat_at ? `${minutesAgo(health.last_heartbeat_at)} min ago` : 'Never'}
            </div>
          </div>
        </div>
      )}

      <div>
        <h2 className="text-sm font-medium text-zinc-700 mb-2">Estimates</h2>
        {estimateJobs.length === 0 ? (
          <div className="text-sm text-zinc-500">No open order has an incomplete estimate.</div>
        ) : (
          <ul className="space-y-3">
            {estimateJobs.map((row) => (
              <li key={row.work_item_id} className="rounded-lg border border-amber-200 bg-amber-50 p-4">
                <div className="font-medium text-zinc-900">{row.job_title ?? `Order #${row.work_item_id}`}</div>
                <div className="text-sm text-zinc-700 mt-1">
                  {row.reasons.includes('no_lines')
                    ? "No items have been added to this order yet."
                    : row.missing
                        .map((m) => `No rate for ${m.quantity_key} at ${m.stage_key}`)
                        .join('; ')}
                  {' '}(map {row.map_title || 'untitled'}
                  {row.version_no != null ? ` v${row.version_no}` : ''}).
                </div>
                <div className="text-xs text-zinc-500 mt-1">
                  Fix: add the item to the map's Items row and publish a new version; new jobs will pick it up.
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>

      {/* EXC-1 (US-EXC-1-07) — work that left the happy path */}
      <div data-testid="health-exceptions">
        <h2 className="text-sm font-medium text-zinc-700 mb-2">Exceptions</h2>
        {!exceptions ? (
          <div className="text-sm text-zinc-500">Couldn't load exceptions right now.</div>
        ) : (
          <div className="space-y-4">
            {(exceptions.needs_attention.parent_cancelled.length > 0 ||
              exceptions.needs_attention.unpublished_targets.length > 0 ||
              exceptions.needs_attention.recent_rejections.length > 0) && (
              <div className="rounded-lg border border-red-200 bg-red-50 p-4 space-y-2" data-testid="health-exceptions-attention">
                <div className="font-medium text-red-900">Needs attention</div>
                {exceptions.needs_attention.parent_cancelled.map((r) => (
                  <div key={`pc-${r.exception_id}`} className="text-sm text-red-800">
                    Order #{r.parent_work_item_id} was cancelled, but the work it sent to {r.target_map_title} (#{r.child_work_item_id}) is still open.
                    Decide whether to finish or cancel #{r.child_work_item_id}.
                  </div>
                ))}
                {exceptions.needs_attention.unpublished_targets.map((t) => (
                  <div key={`up-${t.source_map_id}-${t.target_map_id}`} className="text-sm text-red-800">
                    {t.source_map_title} sends work to {t.target_map_title}, which has never been published — nobody can send work there yet. Publish {t.target_map_title}.
                  </div>
                ))}
                {exceptions.needs_attention.recent_rejections.length > 0 && (
                  <div className="text-sm text-red-800">
                    Refused sends in the last 7 days:{' '}
                    {exceptions.needs_attention.recent_rejections.map((r) => `${r.error_code} × ${r.count}`).join(', ')}. Look a code up in the catalog for what it means.
                  </div>
                )}
              </div>
            )}

            {exceptions.open_children.length === 0 ? (
              <div className="text-sm text-zinc-500">No work is waiting on a linked map.</div>
            ) : (
              <ul className="space-y-2">
                {exceptions.open_children.map((r) => (
                  <li key={r.exception_id} className="rounded-lg border border-amber-200 bg-amber-50 p-3" data-testid="health-exception-row">
                    <div className="text-sm text-zinc-900">{openChildSentence(r)}</div>
                    <div className="text-xs text-zinc-600 mt-0.5">
                      Why: {reasonWords(r.reason_code)}
                      {r.note ? ` — “${r.note}”` : ''}
                    </div>
                  </li>
                ))}
              </ul>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
              <div className="rounded-lg border border-zinc-200 p-3">
                <div className="text-zinc-500 mb-1">Last 30 days, by stage</div>
                {exceptions.by_stage.length === 0 ? (
                  <div className="text-zinc-400">None.</div>
                ) : (
                  exceptions.by_stage.map((s) => (
                    <div key={s.stage_label} className="flex justify-between">
                      <span>{s.stage_label}</span>
                      <span className="font-medium">{s.count}</span>
                    </div>
                  ))
                )}
              </div>
              <div className="rounded-lg border border-zinc-200 p-3">
                <div className="text-zinc-500 mb-1">Last 30 days, by reason</div>
                {exceptions.by_reason.map((r) => (
                  <div key={r.reason_code} className="flex justify-between">
                    <span>{reasonWords(r.reason_code)}</span>
                    <span className="font-medium">{r.count}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>

      <div>
        <h2 className="text-sm font-medium text-zinc-700 mb-2">Open issues</h2>
        {issues.length === 0 ? (
          <div className="text-sm text-zinc-500">No open issues. Nothing to do here.</div>
        ) : (
          <ul className="space-y-3">
            {issues.map((issue) => (
              <li key={issue.fingerprint} className="rounded-lg border border-zinc-200 p-4">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <div className="font-medium text-zinc-900">{issue.user_message ?? issue.latest_message ?? 'An error occurred.'}</div>
                    <div className="text-xs text-zinc-500 mt-1">
                      Happened {issue.count} time{issue.count === 1 ? '' : 's'} · first seen{' '}
                      {new Date(issue.first_seen).toLocaleString()} · last seen {new Date(issue.last_seen).toLocaleString()}
                    </div>
                    <div className="text-sm text-zinc-700 mt-2">{OWNER_LABELS[issue.owner] ?? 'Needs review'}</div>
                    {issue.fix_hint && <div className="text-sm text-zinc-600 mt-1">Suggested fix: {issue.fix_hint}</div>}
                  </div>
                  <button
                    type="button"
                    onClick={() => void handleCopy(issue)}
                    className="shrink-0 text-xs px-3 py-1.5 rounded border border-zinc-300 text-zinc-700 hover:bg-zinc-50"
                  >
                    {copiedFingerprint === issue.fingerprint ? 'Copied!' : 'Copy diagnostic bundle'}
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
