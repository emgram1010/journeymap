// EXC-1 (US-EXC-1-05/06) — "Send to…": the one way to say "this part of
// the job is leaving the happy path". Used on a performer's step screen
// (one step) and in the planner's job detail (pick the step), so both
// read the same targets (GET work_item/{id}/links → send_options) and
// post to the same endpoint (610).
//
// THE PARENT KEEPS GOING. "This step is stuck until it's resolved" is
// off by default (D-1); turning it on asks LOG-1's engine to block the
// step, and a refusal there does not undo the send.
//
// THE CONFIRM BUTTON SITS IN A FIXED FOOTER, never at the end of the
// scrolling content: a sheet with one stepper per item has unbounded
// length, and ITEM-1 shipped a Save button no person could press because
// it scrolled under the fold (E2E-EXC-1-06 hit-tests it).
//
// ONE REQUEST ID PER OPENED SHEET, reused on every retry. The endpoint
// refuses a repeat as E-EXC-013 ("already sent — job #N"), so a send whose
// response was lost (a phone timing out on a ~4 s request) can't make a
// second child job when the person taps Send again; the panel treats that
// refusal as the success it reports.
//
// A refusal keeps everything typed — reason, note, counts — and shows the
// server's own sentence (CLAUDE.md UI rule).
import {useCallback, useEffect, useMemo, useState} from 'react';
import {Minus, Plus, Send, X} from 'lucide-react';
import {getWorkItemLines, getWorkItemLinks, raiseException, type JobChildLink, type JobParentLink, type JobSendOption} from '../planner/plannerApi';
import {newCorrelationId} from '../ops/correlationId';
import {progressShortLabel} from './jobProgress';
import JobPeekSheet from './JobPeekSheet';
import {
  REASON_CODES,
  REASON_LABELS,
  buildExceptionRequest,
  clampCount,
  emptySheet,
  isAlreadySent,
  optionsForStep,
  sentToast,
  validateSheet,
  type SheetLine,
  type SheetState,
} from './exceptionSheet';

type Props = {
  workItemId: number;
  /** Performer: the step being worked. Planner: omit, and the panel offers every step that can send. */
  workTaskId?: number;
  variant: 'performer' | 'planner';
  /** Called after a successful send (e.g. to reload the job or the step). */
  onSent?: () => void;
  /**
   * EXC-2 (US-EXC-2-03) — surfaces this job's parent, once loaded, so the
   * caller can show its own "Came from" chip without a second
   * `getWorkItemLinks` call (this panel already makes one).
   */
  onLinksLoaded?: (parent: JobParentLink | null) => void;
  /**
   * EXC-2 (US-EXC-2-04) — when supplied, tapping a sent chip calls this
   * instead of the panel opening its own `JobPeekSheet` (the planner
   * decides whether to scroll to an existing row or open the peek view;
   * this panel must not know about the job list).
   */
  onOpenJob?: (workItemId: number) => void;
};

export default function ExceptionSendPanel({workItemId, workTaskId, variant, onSent, onLinksLoaded, onOpenJob}: Props) {
  const [options, setOptions] = useState<JobSendOption[]>([]);
  const [children, setChildren] = useState<JobChildLink[]>([]);
  const [lines, setLines] = useState<SheetLine[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const [stepId, setStepId] = useState<number | null>(workTaskId ?? null);
  const [sheet, setSheet] = useState<SheetState | null>(null);
  const [sending, setSending] = useState(false);
  const [sheetError, setSheetError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [requestId, setRequestId] = useState<string>('');
  const [peekId, setPeekId] = useState<number | null>(null);

  const load = useCallback(async () => {
    setLoadError(null);
    try {
      const [links, lineData] = await Promise.all([getWorkItemLinks(workItemId), getWorkItemLines(workItemId)]);
      setOptions(links.send_options ?? []);
      setChildren(links.children ?? []);
      setLines((lineData.lines ?? []).map((l) => ({item_type_id: l.item_type_id, label: l.item_label || l.item_key, quantity: l.quantity})));
      onLinksLoaded?.(links.parent ?? null);
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : "Couldn't load where this work can be sent.");
    } finally {
      setLoaded(true);
    }
  }, [workItemId, onLinksLoaded]);

  const openJob = useCallback((id: number) => (onOpenJob ? onOpenJob(id) : setPeekId(id)), [onOpenJob]);

  useEffect(() => {
    void load();
  }, [load]);

  const stepsWithOptions = useMemo(() => {
    const seen = new Map<number, string>();
    for (const o of options) if (!seen.has(o.work_task_id)) seen.set(o.work_task_id, o.stage_label);
    return [...seen.entries()].map(([id, label]) => ({id, label}));
  }, [options]);

  const activeStep = workTaskId ?? stepId ?? stepsWithOptions[0]?.id ?? null;
  const stepOptions = useMemo(() => (activeStep == null ? [] : optionsForStep(options, activeStep)), [options, activeStep]);
  const stepStage = stepOptions[0]?.stage_key ?? null;
  const sentFromHere = children.filter((c) => c.via === 'exception' && (variant === 'planner' || c.stage_key === stepStage));

  if (!loaded) return null;
  if (loadError) return <p className="text-xs text-red-600">{loadError}</p>;
  if (stepsWithOptions.length === 0 || (variant === 'performer' && stepOptions.length === 0)) {
    return variant === 'planner' ? (
      <p className="text-[10px] text-neutral-500">This job's map doesn't send work anywhere (no exception links in its version).</p>
    ) : null;
  }

  const published = stepOptions.filter((o) => o.published);
  const buttonLabel = published.length === 1 ? `Send to ${published[0].target_map_title}` : 'Send to…';

  const openSheet = (forStep: number | null) => {
    const opts = forStep == null ? [] : optionsForStep(options, forStep);
    setStepId(forStep);
    setSheet(emptySheet(opts, lines));
    setRequestId(newCorrelationId());
    setSheetError(null);
    setToast(null);
    setOpen(true);
  };

  const submit = async () => {
    if (!sheet || activeStep == null) return;
    const problem = validateSheet(sheet, lines, stepOptions);
    if (problem) {
      setSheetError(problem.message);
      return;
    }
    if (sheet.targetMapId == null) {
      setSheetError('Pick where this work goes.');
      return;
    }
    setSending(true);
    setSheetError(null);
    try {
      const result = await raiseException(activeStep, buildExceptionRequest(sheet, requestId || newCorrelationId()));
      const target = stepOptions.find((o) => o.target_map_id === sheet.targetMapId)?.target_map_title ?? 'the linked map';
      const moved = result.child.lines.map((l) => ({
        label: lines.find((x) => x.item_type_id === l.item_type_id)?.label ?? l.item_key,
        quantity: l.quantity,
      }));
      let text = sentToast(target, result.child.work_item_id, moved);
      if (sheet.blockParent && !result.parent_blocked) text += ` — this step was not blocked: ${result.block_refusal}`;
      if (result.followup_failed) text += ' — saved, but some follow-up updates did not finish; support can see which on the Health page.';
      setToast(text);
      setOpen(false);
      await load();
      onSent?.();
    } catch (err) {
      const message = err instanceof Error ? err.message : "That didn't send. Try again.";
      if (isAlreadySent(message)) {
        // An earlier tap already went through; its response was lost.
        setToast(message);
        setOpen(false);
        await load();
        onSent?.();
        return;
      }
      // Keep the sheet open with everything typed; show the server's sentence.
      setSheetError(message);
    } finally {
      setSending(false);
    }
  };

  const isPerformer = variant === 'performer';
  const btnBase = isPerformer
    ? 'min-h-[44px] w-full rounded-lg border border-amber-300 bg-amber-50 px-4 text-base font-medium text-amber-900'
    : 'px-2 py-1 text-[11px] font-medium text-amber-800 bg-amber-50 border border-amber-200 rounded hover:bg-amber-100';

  return (
    <div className={isPerformer ? 'space-y-2' : 'flex flex-col gap-1.5'} data-testid="exception-panel">
      {toast && (
        <p role="status" data-testid="exception-toast" className={isPerformer ? 'text-sm text-emerald-700' : 'text-[11px] text-emerald-700'}>
          {toast}
        </p>
      )}

      {sentFromHere.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {sentFromHere.map((c) => {
            const n = c.moved_lines.reduce((sum, l) => sum + l.quantity, 0);
            return (
              <button
                key={c.work_item_id}
                type="button"
                data-testid="exception-chip"
                aria-label={`Open sent job #${c.work_item_id}`}
                title={`${c.title} — ${REASON_LABELS[c.reason_code as keyof typeof REASON_LABELS] ?? c.reason_code}`}
                onClick={() => openJob(c.work_item_id)}
                className="rounded-full border border-amber-200 bg-amber-50 px-2 py-0.5 text-[11px] text-amber-800"
              >
                {n > 0 ? `${n} → #${c.work_item_id}` : `→ #${c.work_item_id}`}
                {variant === 'planner' && c.stage_label ? ` · ${c.stage_label}` : ''}
                {c.progress ? ` · ${progressShortLabel(c.progress)}` : ''}
              </button>
            );
          })}
        </div>
      )}

      {variant === 'planner' && stepsWithOptions.length > 1 ? (
        <div className="flex flex-wrap gap-1.5">
          {stepsWithOptions.map((s) => (
            <button key={s.id} type="button" data-testid="exception-send-button" onClick={() => openSheet(s.id)} className={btnBase}>
              Send from {s.label}…
            </button>
          ))}
        </div>
      ) : (
        <button type="button" data-testid="exception-send-button" onClick={() => openSheet(activeStep)} className={btnBase}>
          <Send className="inline w-3.5 h-3.5 mr-1 -mt-0.5" />
          {buttonLabel}
        </button>
      )}

      {open && sheet && (
        <div
          className="fixed inset-0 z-50 flex flex-col bg-white sm:inset-auto sm:right-4 sm:bottom-4 sm:top-4 sm:w-[420px] sm:rounded-xl sm:border sm:border-zinc-200 sm:shadow-2xl"
          role="dialog"
          aria-modal="true"
          aria-label="Send work to a linked map"
          data-testid="exception-sheet"
        >
          <header className="flex shrink-0 items-center justify-between border-b border-zinc-200 px-4 py-3">
            <div className="min-w-0">
              <p className="text-base font-semibold text-zinc-900">This part is leaving the happy path</p>
              <p className="text-xs text-zinc-500">From {stepOptions[0]?.stage_label}. The rest of the job keeps going.</p>
            </div>
            <button type="button" aria-label="Close" onClick={() => setOpen(false)} className="w-11 h-11 -mr-2 flex items-center justify-center text-zinc-500">
              <X className="w-5 h-5" />
            </button>
          </header>

          <div className="flex-1 overflow-y-auto px-4 py-4 space-y-5">
            <section>
              <p className="mb-2 text-sm font-medium text-zinc-700">Send to</p>
              <div className="space-y-2">
                {stepOptions.map((o) => (
                  <label
                    key={o.target_map_id}
                    className={`flex min-h-[44px] items-center gap-3 rounded-lg border px-3 py-2 text-sm ${
                      o.published ? 'border-zinc-300 text-zinc-800' : 'border-zinc-200 text-zinc-400'
                    }`}
                  >
                    <input
                      type="radio"
                      name="exception-target"
                      disabled={!o.published}
                      checked={sheet.targetMapId === o.target_map_id}
                      onChange={() => setSheet({...sheet, targetMapId: o.target_map_id})}
                    />
                    <span className="min-w-0 flex-1">{o.target_map_title}</span>
                    {!o.published && <span className="text-xs">not published yet</span>}
                  </label>
                ))}
              </div>
            </section>

            <section>
              <p className="mb-2 text-sm font-medium text-zinc-700">Why?</p>
              <div className="grid grid-cols-2 gap-2">
                {REASON_CODES.map((code) => (
                  <button
                    key={code}
                    type="button"
                    data-testid={`exception-reason-${code}`}
                    aria-pressed={sheet.reasonCode === code}
                    onClick={() => setSheet({...sheet, reasonCode: code})}
                    className={`min-h-[44px] rounded-lg border px-3 py-2 text-sm ${
                      sheet.reasonCode === code ? 'border-zinc-900 bg-zinc-900 text-white' : 'border-zinc-300 bg-white text-zinc-700'
                    }`}
                  >
                    {REASON_LABELS[code]}
                  </button>
                ))}
              </div>
            </section>

            {lines.length > 0 && (
              <section>
                <p className="mb-1 text-sm font-medium text-zinc-700">How many are going?</p>
                <p className="mb-2 text-xs text-zinc-500">Leave at 0 to keep them on this job.</p>
                <ul className="space-y-2">
                  {lines.map((line) => {
                    const n = sheet.counts[line.item_type_id] ?? 0;
                    const set = (value: number) =>
                      setSheet({...sheet, counts: {...sheet.counts, [line.item_type_id]: clampCount(value, line.quantity)}});
                    return (
                      <li key={line.item_type_id} className="flex items-center gap-2" data-testid="exception-line">
                        <span className="min-w-0 flex-1 text-sm text-zinc-800">
                          {line.label} <span className="text-zinc-400">of {line.quantity}</span>
                        </span>
                        <button type="button" aria-label={`Fewer ${line.label}`} onClick={() => set(n - 1)} className="w-11 h-11 rounded-lg border border-zinc-300 flex items-center justify-center">
                          <Minus className="w-4 h-4" />
                        </button>
                        <input
                          type="number"
                          inputMode="numeric"
                          min={0}
                          max={line.quantity}
                          value={n}
                          aria-label={`${line.label} to send`}
                          onChange={(e) => set(Number(e.target.value))}
                          className="h-11 w-16 rounded-lg border border-zinc-300 text-center text-base"
                        />
                        <button type="button" aria-label={`More ${line.label}`} onClick={() => set(n + 1)} className="w-11 h-11 rounded-lg border border-zinc-300 flex items-center justify-center">
                          <Plus className="w-4 h-4" />
                        </button>
                        <button type="button" onClick={() => set(line.quantity)} className="min-h-[44px] px-2 text-xs text-zinc-600">
                          All
                        </button>
                      </li>
                    );
                  })}
                </ul>
              </section>
            )}

            <section>
              <label className="mb-1 block text-sm font-medium text-zinc-700" htmlFor="exception-note">
                Note (optional)
              </label>
              <textarea
                id="exception-note"
                value={sheet.note}
                onChange={(e) => setSheet({...sheet, note: e.target.value})}
                rows={3}
                maxLength={600}
                placeholder="What happened?"
                className="w-full rounded-lg border border-zinc-300 p-2 text-base text-zinc-900"
              />
            </section>

            <label className="flex min-h-[44px] items-center gap-3 text-sm text-zinc-700">
              <input
                type="checkbox"
                checked={sheet.blockParent}
                onChange={(e) => setSheet({...sheet, blockParent: e.target.checked})}
                data-testid="exception-block-toggle"
              />
              This step is stuck until it's resolved
            </label>

            {sheetError && (
              <p role="alert" data-testid="exception-error" className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                {sheetError}
              </p>
            )}
          </div>

          {/* Fixed footer — never scrolls out of reach (E2E-EXC-1-06). */}
          <footer className="shrink-0 border-t border-zinc-200 bg-white px-4 py-3 flex gap-2">
            <button type="button" onClick={() => setOpen(false)} className="min-h-[44px] flex-1 rounded-lg border border-zinc-300 text-base text-zinc-700">
              Cancel
            </button>
            <button
              type="button"
              data-testid="exception-confirm"
              onClick={() => void submit()}
              disabled={sending}
              className="min-h-[44px] flex-[2] rounded-lg bg-zinc-900 text-base font-medium text-white disabled:opacity-50"
            >
              {sending ? 'Sending…' : 'Send'}
            </button>
          </footer>
        </div>
      )}

      {/* Only when the caller didn't take ownership via onOpenJob (US-EXC-2-04's planner wiring). */}
      {!onOpenJob && <JobPeekSheet workItemId={peekId ?? 0} open={peekId != null} onClose={() => setPeekId(null)} onOpenJob={setPeekId} />}
    </div>
  );
}
