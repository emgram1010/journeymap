// REPEAT-1 (US-REPEAT-1-01) — Preview repeating a plan.
//
// Shows what a repeat would copy and, more important, what it would leave out, before anything
// is written. Every answer comes from the server (repeat/build_plan via previewRepeat); this
// screen only lays it out. Changing the date or unticking a job asks the server again, so the
// counts are always the server's. A refused date keeps what was typed and shows the reason.
//
// Story 06: the same window now makes the plans, for 1 to 8 periods. The dates and names of every
// period come from the server (repeat-periods); each period is then made by its OWN request, so a
// failed period never undoes one already made and the periods after it are not tried. The whole
// action stays hidden behind isRepeatPlanUiEnabled() until the founder switches it on.
import {useCallback, useEffect, useRef, useState} from 'react';
import {X, Repeat, AlertTriangle, Info} from 'lucide-react';
import {previewRepeat, createRepeat, listRepeatPeriods, getRepeatHistory} from '../plannerApi';
import {DEFAULT_CHOICES, setChoice, assignmentsLocked, choicesToRequest, choicesLine, type RepeatChoices} from '../repeatChoicesModel';
import {
  MAX_PERIODS,
  validatePeriodCount,
  runPeriods,
  outcomeCounts,
  outcomeLine,
  repeatedFromText,
  repeatedToLine,
  type PeriodOutcome,
  type RepeatedFrom,
  type RepeatedTo,
} from '../repeatPeriodsModel';
import {
  canTick,
  capList,
  groupJobs,
  peopleLeftOff,
  reasonText,
  summaryLines,
  toggleSkip,
  validateStartDate,
  type RepeatJob,
  type RepeatPreview,
} from '../repeatPreviewModel';

interface RepeatPlanModalProps {
  isOpen: boolean;
  workspaceId: number;
  onClose: () => void;
  /** Called after plans were made, so the plan list can be reloaded. */
  onPlansChanged?: () => void;
  /** Open one of the plans (made, or already there). */
  onOpenPlan?: (workspaceId: number) => void;
}

const LIST_CAP = 8;

// A server message is shown as is; a raw transport error ("Planner POST /x failed (500): …") never is.
const errorMessage = (err: unknown, fallback = "Couldn't load the preview. Try again."): string => {
  const msg = (err as {message?: unknown})?.message;
  if (typeof msg !== 'string' || msg.trim() === '') return fallback;
  return /^Planner (GET|POST|PATCH|PUT|DELETE) /.test(msg) ? fallback : msg;
};

const CREATE_FAILED = "The plans couldn't be made. Nothing was saved. Try again.";

// A list the planner ticks is never capped: a job hidden under "and N more" could not be unticked.
function JobList({title, jobs, tone, children, uncapped = false}: {title: string; jobs: RepeatJob[]; tone: 'neutral' | 'amber'; children?: (job: RepeatJob) => React.ReactNode; uncapped?: boolean}) {
  if (jobs.length === 0) return null;
  const {shown, more} = uncapped ? {shown: jobs, more: 0} : capList(jobs, LIST_CAP);
  return (
    <section className={`border rounded-md p-3 ${tone === 'amber' ? 'border-amber-200 bg-amber-50/40' : 'border-neutral-200'}`}>
      <h3 className="text-xs font-semibold text-neutral-900 mb-2">
        {title} <span className="text-neutral-500 font-normal">({jobs.length})</span>
      </h3>
      <ul className="flex flex-col gap-1.5">
        {shown.map(job => (
          <li key={job.id} className="text-xs text-neutral-800 flex items-start gap-2 min-w-0">
            {children ? children(job) : null}
            <span className="min-w-0">
              <span className="break-words">{job.title}</span>
              {job.reason !== '' && job.reason !== 'left_out' && (
                <span className="block text-[11px] text-neutral-500">{reasonText(job.reason)}</span>
              )}
            </span>
          </li>
        ))}
      </ul>
      {more > 0 && <p className="text-[11px] text-neutral-500 mt-1.5">and {more} more</p>}
    </section>
  );
}

export function RepeatPlanModal({isOpen, workspaceId, onClose, onPlansChanged, onOpenPlan}: RepeatPlanModalProps) {
  const [preview, setPreview] = useState<RepeatPreview | null>(null);
  const [startDate, setStartDate] = useState('');
  const [skipIds, setSkipIds] = useState<number[]>([]);
  // REPEAT-2 — what comes along: people, jobs, assignments. All ticked unless the planner unticks one.
  const [choices, setChoices] = useState<RepeatChoices>(DEFAULT_CHOICES);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestNo = useRef(0);
  const [periods, setPeriods] = useState(1);
  const [running, setRunning] = useState(false);
  const [outcomes, setOutcomes] = useState<PeriodOutcome[] | null>(null);
  const [history, setHistory] = useState<{from: RepeatedFrom | null; to: RepeatedTo[]} | null>(null);
  // One run at a time: a synchronous guard (a state flag only applies after a re-render), and a run
  // number so a run that outlived its window (closed, reopened, another plan) can't write over a newer one.
  const inFlight = useRef(false);
  const runNo = useRef(0);

  const loadHistory = useCallback(() => {
    getRepeatHistory(workspaceId)
      .then(h => setHistory({from: h.repeated_from, to: h.repeated_to}))
      .catch(() => setHistory(null)); // a failed read only hides the section
  }, [workspaceId]);

  const load = useCallback(async (start: string, skip: number[], carry: RepeatChoices) => {
    const mine = ++requestNo.current;
    setLoading(true);
    setError(null);
    try {
      const data = await previewRepeat(workspaceId, {start_date: start, skip_job_ids: skip, ...choicesToRequest(carry)});
      if (mine !== requestNo.current) return; // a newer request has started; drop this answer
      setPreview(data);
      if (start === '') setStartDate(data.offer.start_date);
    } catch (err) {
      if (mine !== requestNo.current) return;
      setError(errorMessage(err));
    } finally {
      if (mine === requestNo.current) setLoading(false);
    }
  }, [workspaceId]);

  useEffect(() => {
    if (!isOpen) return;
    setPreview(null);
    setStartDate('');
    setSkipIds([]);
    setChoices(DEFAULT_CHOICES);
    setPeriods(1);
    setOutcomes(null);
    // A run still going (the window can't be closed while one is) keeps its own state; nothing to reset.
    if (!inFlight.current) setRunning(false);
    void load('', [], DEFAULT_CHOICES);
    // Where this plan came from and what was made from it.
    setHistory(null);
    loadHistory();
  }, [isOpen, workspaceId, load, loadHistory]);

  if (!isOpen) return null;

  // The window can't be closed while plans are being made: a closed window can't show what happened.
  const close = () => {
    if (inFlight.current) return;
    onClose();
  };

  const onDateChange = (value: string) => {
    setOutcomes(null);
    setStartDate(value); // keep the typing even when it is refused
    if (!preview) return;
    const check = validateStartDate(value, preview.source.start_date, preview.source.end_date);
    if (check.ok === false) {
      setError(`${check.message} (${check.code})`);
      return;
    }
    void load(value, skipIds, choices);
  };

  const onCreate = async () => {
    const check = validatePeriodCount(periods);
    if (check.ok === false) {
      setError(`${check.message} (${check.code})`);
      return;
    }
    if (inFlight.current) return;
    inFlight.current = true;
    const mine = ++runNo.current;
    setRunning(true);
    setError(null);
    setOutcomes(null);
    try {
      const list = await listRepeatPeriods(workspaceId, {start_date: startDate, periods});
      const correlationId = `repeat-${workspaceId}-${Date.now()}`;
      // Every period is made from THIS plan (workspaceId), never from the copy before it.
      const result = await runPeriods(list.periods, p =>
        createRepeat(workspaceId, {start_date: p.start_date, name: p.name, skip_job_ids: skipIds, correlation_id: correlationId, ...choicesToRequest(choices)}),
      );
      if (mine !== runNo.current) return;
      setOutcomes(result);
      if (result.some(o => o.status === 'created')) {
        onPlansChanged?.();
        loadHistory();
      }
    } catch (err) {
      // The period list itself was refused (limit, date, overlap): nothing was made.
      if (mine === runNo.current) setError(errorMessage(err, CREATE_FAILED));
    } finally {
      inFlight.current = false;
      if (mine === runNo.current) setRunning(false);
    }
  };

  // After a failed period, Create works again: periods already made answer "already there" and are skipped.
  const canRetry = outcomes !== null && outcomes.some(o => o.status === 'failed');

  const onToggle = (jobId: number) => {
    setOutcomes(null);
    const next = toggleSkip(skipIds, jobId);
    setSkipIds(next);
    void load(startDate, next, choices);
  };

  const onChoice = (key: keyof RepeatChoices, value: boolean) => {
    const next = setChoice(choices, key, value);
    setOutcomes(null);
    setChoices(next);
    void load(startDate, skipIds, next);
  };

  const groups = preview ? groupJobs(preview.jobs) : null;
  const leftOffPeople = preview ? peopleLeftOff(preview.people) : [];

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="repeat-plan-title"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4"
      onClick={close}
    >
      <div
        onClick={e => e.stopPropagation()}
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-2xl flex flex-col max-h-[85vh] overflow-hidden"
      >
        <div className="h-14 px-4 sm:px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
          <div className="flex items-center gap-2 min-w-0">
            <Repeat className="w-4 h-4 text-neutral-700 shrink-0" />
            <h2 id="repeat-plan-title" className="text-sm font-bold text-neutral-900 truncate">
              Repeat this plan{preview ? `: ${preview.source.name}` : ''}
            </h2>
          </div>
          <button type="button" onClick={close} disabled={running} className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50 disabled:opacity-40" aria-label="Close">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-4 sm:p-6 overflow-y-auto flex flex-col gap-4 text-sm">
          <p className="text-[11px] text-neutral-500">
            A repeat makes a new plan with the same people, days and jobs, moved to new dates. This plan is not changed.
            Nothing is created until you confirm.
          </p>

          <section className="border border-neutral-200 rounded-md p-3 flex flex-col gap-2">
            <label className="flex flex-col gap-1 max-w-[220px]">
              <span className="text-[10px] text-neutral-500">New plan starts on</span>
              <input
                id="repeat-start-date"
                type="date"
                value={startDate}
                onChange={e => onDateChange(e.target.value)}
                className="text-xs px-2 py-1.5 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono"
              />
            </label>
            <label className="flex flex-col gap-1 max-w-[220px]">
              <span className="text-[10px] text-neutral-500">How many periods (1 to {MAX_PERIODS})</span>
              <input
                id="repeat-periods"
                type="number"
                min={1}
                max={MAX_PERIODS}
                value={periods}
                disabled={running}
                onChange={e => { setOutcomes(null); setPeriods(Number(e.target.value)); }}
                className="text-xs px-2 py-1.5 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono w-24"
              />
            </label>
            {periods > 1 && (
              <p className="text-[11px] text-neutral-500">
                Each period is as long as this plan and follows the one before it, with no gap. Every period is copied from this plan, not from the copy before it.
              </p>
            )}
            {preview && (
              <p className="text-xs text-neutral-700">
                <span className="font-medium">{preview.offer.name}</span>
                <span className="text-neutral-500"> · {preview.offer.start_date} to {preview.offer.end_date} ({preview.source.length_days} days)</span>
              </p>
            )}
            {preview && !preview.offer.weekdays_align && (
              <p className="text-xs text-amber-800 flex items-start gap-1.5" role="status">
                <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" aria-hidden="true" />
                Weekdays will not line up: work done on a Monday will land on a different day. You can still continue.
              </p>
            )}
            {preview?.source.is_archived && (
              <p className="text-xs text-neutral-600 flex items-start gap-1.5">
                <Info className="w-3.5 h-3.5 mt-0.5 shrink-0" aria-hidden="true" />
                This plan is archived. Repeating it is fine; the new plan will not be archived.
              </p>
            )}
          </section>

          <section className="border border-neutral-200 rounded-md p-3 flex flex-col gap-2" data-testid="repeat-choices">
            <h3 className="text-xs font-semibold text-neutral-900">What comes along</h3>
            <div className="flex flex-wrap gap-x-5 gap-y-1.5 text-xs text-neutral-800">
              <label className="flex items-center gap-1.5">
                <input id="repeat-carry-people" type="checkbox" checked={choices.people} disabled={running} onChange={e => onChoice('people', e.target.checked)} />
                People
              </label>
              <label className="flex items-center gap-1.5">
                <input id="repeat-carry-jobs" type="checkbox" checked={choices.jobs} disabled={running} onChange={e => onChoice('jobs', e.target.checked)} />
                Jobs
              </label>
              <label className={`flex items-center gap-1.5 ${assignmentsLocked(choices) ? 'text-neutral-400' : ''}`}>
                <input
                  id="repeat-carry-assignments"
                  type="checkbox"
                  checked={choices.assignments}
                  disabled={running || assignmentsLocked(choices)}
                  onChange={e => onChoice('assignments', e.target.checked)}
                />
                Assignments (days and scheduled slots)
              </label>
            </div>
            <p className="text-[11px] text-neutral-500">
              {choicesLine(choices)}
              {assignmentsLocked(choices) ? ' Assignments need people.' : ''}
            </p>
          </section>

          {error && (
            <p className="text-xs text-red-700 flex items-start gap-1.5" role="alert">
              <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" aria-hidden="true" />
              {error}
            </p>
          )}

          {running && <p className="text-xs text-neutral-700" role="status">Making the plans, one at a time…</p>}

          {outcomes && (
            <section className="border border-neutral-200 rounded-md p-3" aria-live="polite" data-testid="repeat-outcomes">
              <h3 className="text-xs font-semibold text-neutral-900 mb-1.5">
                {(() => {
                  const c = outcomeCounts(outcomes);
                  return `${c.created} made${c.skipped > 0 ? `, ${c.skipped} already there` : ''}${c.failed > 0 ? `, ${c.failed} failed` : ''}${c.notAttempted > 0 ? `, ${c.notAttempted} not tried` : ''}`;
                })()}
              </h3>
              <ul className="flex flex-col gap-1 text-xs text-neutral-800">
                {outcomes.map(o => (
                  <li key={o.n} className="flex items-start gap-2 min-w-0">
                    <span className={`min-w-0 break-words ${o.status === 'failed' ? 'text-red-700' : ''}`}>{outcomeLine(o)}</span>
                    {o.workspace_id && onOpenPlan && (
                      <button
                        type="button"
                        onClick={() => { onOpenPlan(o.workspace_id as number); onClose(); }}
                        className="shrink-0 underline text-neutral-600 hover:text-neutral-900"
                      >
                        Open
                      </button>
                    )}
                  </li>
                ))}
              </ul>
            </section>
          )}

          {history && (history.from || history.to.length > 0) && (
            <section className="border border-neutral-200 rounded-md p-3" data-testid="repeat-history">
              <h3 className="text-xs font-semibold text-neutral-900 mb-1.5">History</h3>
              {history.from && (
                <p className="text-xs text-neutral-800 mb-1.5">
                  {repeatedFromText(history.from)}
                  {history.from.exists && onOpenPlan && (
                    <button
                      type="button"
                      onClick={() => { onOpenPlan(history.from!.workspace_id); onClose(); }}
                      className="ml-2 underline text-neutral-600 hover:text-neutral-900"
                    >
                      Open
                    </button>
                  )}
                </p>
              )}
              {history.to.length > 0 && (
                <>
                  <p className="text-[11px] text-neutral-500 mb-1">Plans repeated from this one</p>
                  <ul className="flex flex-col gap-1 text-xs text-neutral-800">
                    {history.to.map(t => (
                      <li key={t.workspace_id} className="flex items-start gap-2 min-w-0">
                        <span className="min-w-0 break-words">{repeatedToLine(t)}</span>
                        {onOpenPlan && (
                          <button
                            type="button"
                            onClick={() => { onOpenPlan(t.workspace_id); onClose(); }}
                            className="shrink-0 underline text-neutral-600 hover:text-neutral-900"
                          >
                            Open
                          </button>
                        )}
                      </li>
                    ))}
                  </ul>
                </>
              )}
            </section>
          )}

          {loading && !preview && <p className="text-xs text-neutral-500">Working out what would be copied…</p>}

          {preview && groups && (
            <>
              <section className="border border-neutral-200 rounded-md p-3" aria-live="polite">
                <h3 className="text-xs font-semibold text-neutral-900 mb-1.5">The new plan will have</h3>
                <ul className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-neutral-800">
                  {summaryLines(preview.counts).map(line => <li key={line}>{line}</li>)}
                </ul>
                {loading && <p className="text-[11px] text-neutral-500 mt-1.5">Updating…</p>}
              </section>

              {choices.people && leftOffPeople.length > 0 && (
                <section className="border border-amber-200 bg-amber-50/40 rounded-md p-3">
                  <h3 className="text-xs font-semibold text-neutral-900 mb-2">People who will be left off ({leftOffPeople.length})</h3>
                  <ul className="flex flex-col gap-1 text-xs text-neutral-800">
                    {leftOffPeople.map(p => (
                      <li key={p.agent_id}>
                        {p.name} <span className="text-neutral-500">· switched off.{p.slots_to_backlog > 0 ? ` ${p.slots_to_backlog} of their slots go to the backlog.` : ''}</span>
                      </li>
                    ))}
                  </ul>
                </section>
              )}

              {choices.jobs && (<>
              <JobList title="Jobs that will repeat" jobs={[...groups.repeat, ...groups.leftOut].sort((a, b) => a.id - b.id)} tone="neutral" uncapped>
                {job => (
                  <input
                    type="checkbox"
                    aria-label={`Repeat ${job.title}`}
                    checked={job.verdict === 'repeat'}
                    disabled={!canTick(job)}
                    onChange={() => onToggle(job.id)}
                    className="mt-0.5 shrink-0"
                  />
                )}
              </JobList>

              {groups.newer.length > 0 && (
                <JobList title="Will use the newer version of their map" jobs={groups.newer} tone="neutral" />
              )}

              <JobList title="Will not repeat" jobs={groups.willNot} tone="amber" />
              <JobList title="Cannot repeat" jobs={groups.cannot} tone="amber" />
              </>)}
            </>
          )}
        </div>

        <div className="px-4 sm:px-6 py-3 border-t border-neutral-200 bg-neutral-50 flex items-center justify-between gap-3 shrink-0">
          <p className="text-[11px] text-neutral-500">This plan is not changed.</p>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={close}
              disabled={running}
              className="px-3 py-1.5 border border-neutral-300 rounded-md text-xs font-semibold text-neutral-800 hover:bg-neutral-100 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              Close
            </button>
            <button
              type="button"
              id="repeat-create-btn"
              disabled={running || loading || !preview || (outcomes !== null && !canRetry)}
              onClick={() => void onCreate()}
              className="px-3 py-1.5 rounded-md text-xs font-semibold text-white bg-neutral-900 hover:bg-neutral-800 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {running ? 'Making…' : periods > 1 ? `Create ${periods} plans` : 'Create plan'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
