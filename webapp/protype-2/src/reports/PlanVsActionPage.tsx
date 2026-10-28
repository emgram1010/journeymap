// RPT-1 — Reports → Plan vs Action.
//
// WHY THIS IS A PAGE AND NOT A PANEL. This report used to live inside
// the planner's Jobs modal, in the expanded block of one job: to read
// it you opened the planner, opened Jobs, found the job and expanded
// it, and then saw a four-line table in a 2.5mm-tall box. The question
// it answers — "did the work take what the plan said it would?" — is
// not a question about one job you already had open. It is the question
// you arrive with. So it is its own place, reachable in two clicks from
// anywhere, with room to actually read the numbers.
//
// READ-ONLY, like the endpoint behind it. Nobody reports variance by
// hand (VAR-1's first sentence); every figure here is derived on the
// fly from the activity log, the pinned version and the published
// snapshot. Nothing on this page writes anything.
//
// The planner's Jobs modal keeps "What the performer reported" (the
// activity feed) — that one IS about a job you already have open.
import {useCallback, useEffect, useMemo, useState} from 'react';
import {TrendingUp, Loader2, AlertCircle} from 'lucide-react';
import {
  listWorkspaces,
  listWorkItems,
  getWorkItemVariance,
  type TaskVarianceRow,
  type WorkspaceListEntry,
} from '../planner/plannerApi';
import {formatMinutes, formatGap, gapTone, summariseJob} from '../planner/varianceDisplay';
import {logEvent} from '../ops/logEvent';
import {firstJobToShow, reportJobOptions, type JobOption} from './reportsModel';

const TONE_CLASS: Record<string, string> = {
  over: 'text-amber-700',
  under: 'text-sky-700',
  on_track: 'text-emerald-700',
  unknown: 'text-zinc-400',
};

export default function PlanVsActionPage() {
  const [plans, setPlans] = useState<WorkspaceListEntry[]>([]);
  const [planId, setPlanId] = useState<number | null>(null);
  const [jobs, setJobs] = useState<JobOption[]>([]);
  const [jobId, setJobId] = useState<number | null>(null);
  const [rows, setRows] = useState<TaskVarianceRow[]>([]);

  const [isLoadingPlans, setIsLoadingPlans] = useState(true);
  const [isLoadingJobs, setIsLoadingJobs] = useState(false);
  const [isLoadingReport, setIsLoadingReport] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Bumped by "Try again". Both reads below depend on it, so one button
  // retries whichever of the three actually failed — re-running the plan
  // load alone would not re-fetch a report whose job id never changed.
  const [reloadKey, setReloadKey] = useState(0);

  // Nothing here fails silently (OBS-1): a read that fell over is an
  // event, not just a sentence on screen the founder has to be looking
  // at to ever know about.
  const reportFailure = (step: string, err: unknown, entityId: number | null) => {
    void logEvent({
      feature: 'RPT-1',
      step,
      outcome: 'failure',
      severity: 'warn',
      message: err instanceof Error ? err.message : String(err),
      entityType: entityId == null ? null : 'work_item',
      entityId,
    });
  };

  const loadPlans = useCallback(async () => {
    setIsLoadingPlans(true);
    setError(null);
    try {
      const data = await listWorkspaces();
      const live = data.workspaces.filter((w) => !w.workspace.is_archived);
      setPlans(live);
      setPlanId((prev) => (prev != null && live.some((w) => w.workspace.id === prev) ? prev : live[0]?.workspace.id ?? null));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't load your plans.");
      reportFailure('plans_load', err, null);
    } finally {
      setIsLoadingPlans(false);
    }
  }, []);

  useEffect(() => {
    void loadPlans();
  }, [loadPlans]);

  // Switching plans CLEARS first. Leaving the previous plan's job list and
  // its numbers on screen under the new plan's name shows one plan's work
  // as another's — the same mistake the Jobs modal had to be fixed for.
  useEffect(() => {
    if (planId == null) return;
    let current = true;
    setIsLoadingJobs(true);
    setError(null);
    setJobs([]);
    setJobId(null);
    setRows([]);
    void (async () => {
      try {
        const data = await listWorkItems(planId);
        if (!current) return;
        const options = reportJobOptions(data.work_items);
        setJobs(options);
        setJobId(firstJobToShow(options));
      } catch (err) {
        if (!current) return;
        setError(err instanceof Error ? err.message : "Couldn't load this plan's jobs.");
        reportFailure('jobs_load', err, null);
      } finally {
        if (current) setIsLoadingJobs(false);
      }
    })();
    return () => {
      current = false;
    };
  }, [planId, reloadKey]);

  useEffect(() => {
    if (jobId == null) return;
    let current = true;
    setIsLoadingReport(true);
    setError(null);
    setRows([]);
    void (async () => {
      try {
        const data = await getWorkItemVariance(jobId);
        if (!current) return;
        setRows(data.tasks);
      } catch (err) {
        if (!current) return;
        setError(err instanceof Error ? err.message : "Couldn't load what came back for this job.");
        reportFailure('variance_load', err, jobId);
      } finally {
        if (current) setIsLoadingReport(false);
      }
    })();
    return () => {
      current = false;
    };
  }, [jobId, reloadKey]);

  const job = useMemo(() => jobs.find((j) => j.id === jobId) ?? null, [jobs, jobId]);
  const outliers = rows.filter((r) => r.is_outlier).length;

  return (
    <div className="mx-auto max-w-4xl px-6 py-8">
      <header className="mb-5">
        <h1 className="flex items-center gap-2 text-lg font-semibold text-zinc-900">
          <TrendingUp className="h-5 w-5 text-zinc-500" />
          Plan vs Action
        </h1>
        <p className="mt-1 text-sm text-zinc-500">
          What the plan agreed, against what Execution actually recorded. Every figure is worked out from the
          activity log each time you open this — nobody types a variance in by hand.
        </p>
      </header>

      {/* ── Pickers ────────────────────────────────────────────────── */}
      <div className="mb-5 flex flex-col gap-3 rounded-lg border border-zinc-200 bg-white p-4 sm:flex-row sm:items-end">
        <label className="flex-1 min-w-0">
          <span className="block text-xs font-medium text-zinc-700">Plan</span>
          <select
            data-testid="pva-plan-select"
            value={planId ?? ''}
            disabled={isLoadingPlans || plans.length === 0}
            onChange={(e) => setPlanId(e.target.value === '' ? null : Number(e.target.value))}
            className="mt-1 w-full rounded-md border border-zinc-300 bg-white px-2.5 py-2 text-sm text-zinc-900 disabled:bg-zinc-50 disabled:text-zinc-400"
          >
            {plans.length === 0 && <option value="">{isLoadingPlans ? 'Loading…' : 'No plans yet'}</option>}
            {plans.map(({workspace}) => (
              <option key={workspace.id} value={workspace.id}>
                {workspace.name}
              </option>
            ))}
          </select>
        </label>

        <label className="flex-1 min-w-0">
          <span className="block text-xs font-medium text-zinc-700">Job</span>
          <select
            data-testid="pva-job-select"
            value={jobId ?? ''}
            disabled={isLoadingJobs || jobs.length === 0}
            onChange={(e) => setJobId(e.target.value === '' ? null : Number(e.target.value))}
            className="mt-1 w-full rounded-md border border-zinc-300 bg-white px-2.5 py-2 text-sm text-zinc-900 disabled:bg-zinc-50 disabled:text-zinc-400"
          >
            {jobs.length === 0 && <option value="">{isLoadingJobs ? 'Loading…' : 'No jobs in this plan'}</option>}
            {jobs.map((o) => (
              <option key={o.id} value={o.id}>
                #{o.id} · {o.title} — {o.statusLabel}, {o.stepSummary}
              </option>
            ))}
          </select>
        </label>
      </div>

      {error && (
        <div role="alert" data-testid="pva-error" className="mb-4 flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 px-3 py-3 text-sm text-red-800">
          <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
          <div className="min-w-0">
            <p>{error}</p>
            <button
              type="button"
              data-testid="pva-retry"
              onClick={() => {
                setReloadKey((k) => k + 1);
                void loadPlans();
              }}
              className="mt-1.5 min-h-[32px] text-sm font-medium underline"
            >
              Try again
            </button>
          </div>
        </div>
      )}

      {/* ── The report ─────────────────────────────────────────────── */}
      {jobId == null ? (
        <p className="rounded-lg border border-dashed border-zinc-300 px-4 py-8 text-center text-sm text-zinc-500">
          {isLoadingPlans || isLoadingJobs
            ? 'Loading…'
            : plans.length === 0
              ? 'Make a plan in the Planner and start a job from one of its maps — its numbers appear here.'
              : 'This plan has no jobs yet. Start one from the Planner’s Jobs screen.'}
        </p>
      ) : (
        <section data-testid="pva-report" className="rounded-lg border border-zinc-200 bg-white">
          <div className="border-b border-zinc-200 px-4 py-3">
            <p className="text-sm font-medium text-zinc-900">
              {job ? `#${job.id} · ${job.title}` : `#${jobId}`}
            </p>
            <p className="mt-0.5 text-xs text-zinc-500" data-testid="pva-summary">
              {isLoadingReport ? 'Loading…' : summariseJob(rows)}
              {!isLoadingReport && outliers > 0 && (
                <span className="text-amber-700"> · {outliers} step{outliers === 1 ? '' : 's'} well over plan</span>
              )}
            </p>
          </div>

          {isLoadingReport ? (
            <p className="flex items-center gap-2 px-4 py-6 text-sm text-zinc-400">
              <Loader2 className="h-4 w-4 animate-spin" />
              Working out the numbers…
            </p>
          ) : rows.length === 0 ? (
            <p className="px-4 py-6 text-sm text-zinc-500">
              No steps to compare yet — nothing has been recorded against this job.
            </p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-zinc-100 text-left text-xs text-zinc-500">
                  <th scope="col" className="px-4 py-2 font-medium">Stage</th>
                  <th scope="col" className="px-4 py-2 font-medium">Who</th>
                  <th scope="col" className="px-4 py-2 text-right font-medium">Planned</th>
                  <th scope="col" className="px-4 py-2 text-right font-medium">Actual</th>
                  <th scope="col" className="px-4 py-2 text-right font-medium">Difference</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.work_task_id} data-testid="pva-row" className="border-b border-zinc-50 last:border-0">
                    <td className="px-4 py-2 text-zinc-800">
                      {row.stage_key}
                      {row.is_outlier && (
                        <span className="ml-1.5 rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-medium text-amber-800">
                          Well over
                        </span>
                      )}
                      {row.warnings.length > 0 && (
                        <span className="mt-0.5 block text-[11px] text-zinc-400">{row.warnings.join(' · ')}</span>
                      )}
                    </td>
                    <td className="px-4 py-2 text-zinc-500">{row.lens_key}</td>
                    <td className="px-4 py-2 text-right font-mono text-zinc-600">{formatMinutes(row.expected_minutes)}</td>
                    <td className="px-4 py-2 text-right font-mono text-zinc-600">{formatMinutes(row.actual_minutes)}</td>
                    <td className={`px-4 py-2 text-right font-medium ${TONE_CLASS[gapTone(row.expected_gap_minutes, row.expected_gap_pct)]}`}>
                      {formatGap(row.expected_gap_minutes, row.expected_gap_pct)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}
    </div>
  );
}
