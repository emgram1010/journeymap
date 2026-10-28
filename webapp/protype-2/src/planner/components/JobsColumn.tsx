// BOARD-1 (US-BOARD-1-01/02) — The Jobs column: every card of work
// still waiting for a day, beside the day board, grouped under its job.
//
// This is the reference design's "Jobs (28)" list with the dispatcher
// clutter deliberately left out (D-2): rows carry the job's words —
// title, role, steps, minutes — never a code, and every badge carries
// words. The map stayed in the reference; the day's ordered list is our
// route.
//
// DRAG IS AN ENHANCEMENT, NOT THE ONLY PATH (D-4). A card is draggable
// onto a day column, and the same card has a "Place…" button that does
// the identical thing by click — keyboard and touch are not locked out,
// and an E2E test can always hit the button.
//
// The column owns its own 559 fetch and re-pulls when `reloadNonce`
// changes — PlannerApp bumps it after every board mutation, so a card
// scheduled from anywhere leaves this list without a manual refresh.
import {useEffect, useState} from 'react';
import {Briefcase, CalendarPlus, ChevronDown, ChevronRight, GripVertical, Plus, AlertTriangle} from 'lucide-react';
import type {Agent, Timeline} from '../types';
import {listBacklogWork, type BacklogCard} from '../plannerApi';
import {formatMinutes} from '../varianceDisplay';
import {groupCardsByJob, waitingJobsCount} from '../boardModel';
import {EstimateBadge} from './EstimateBadge';
import JobPeekSheet from '../../exceptions/JobPeekSheet';

/** The drag payload a day column looks for. One shape, defined once. */
export const JOB_CARD_DRAG_TYPE = 'job-card';

export interface JobCardDragPayload {
  type: typeof JOB_CARD_DRAG_TYPE;
  workItemId: number;
  lensKey: string;
  cardKey: string;
}

interface JobsColumnProps {
  workspaceId: string | null;
  agents: Agent[];
  timelines: Timeline[];
  planningWindowStart: string;
  /** Bumped by PlannerApp after any board mutation; the column refetches. */
  reloadNonce: number;
  /** Open the Jobs modal — on one job's detail, or on nothing (new job). */
  onOpenJobs: (focusJobId?: number) => void;
  /** PlannerApp owns the schedule rule (ensure the day, 583, refresh). True = placed. */
  onPlaceCard: (card: BacklogCard, agentId: string, day: string) => Promise<boolean>;
}

export function JobsColumn({
  workspaceId,
  agents,
  timelines,
  planningWindowStart,
  reloadNonce,
  onOpenJobs,
  onPlaceCard,
}: JobsColumnProps) {
  const [backlog, setBacklog] = useState<BacklogCard[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandedCard, setExpandedCard] = useState<string | null>(null);
  const [placingFor, setPlacingFor] = useState<string | null>(null);
  const [placeAgentId, setPlaceAgentId] = useState<string>('');
  const [placeDay, setPlaceDay] = useState<string>('');
  const [isPlacing, setIsPlacing] = useState(false);
  // EXC chips open the shared read-only job view (D-2 of EXC-2), never a rebuild of it.
  const [peekId, setPeekId] = useState<number | null>(null);

  useEffect(() => {
    if (!workspaceId) {
      setBacklog([]);
      return;
    }
    let current = true;
    setIsLoading(true);
    setError(null);
    listBacklogWork(Number(workspaceId))
      .then((data) => {
        if (current) setBacklog(data.backlog);
      })
      .catch((err) => {
        if (current) setError(err instanceof Error ? err.message : "Couldn't load the waiting work.");
      })
      .finally(() => {
        if (current) setIsLoading(false);
      });
    return () => {
      current = false;
    };
  }, [workspaceId, reloadNonce]);

  const groups = groupCardsByJob(backlog);
  const jobCount = waitingJobsCount(backlog);

  const openPlaceForm = (cardKey: string) => {
    setPlacingFor((prev) => (prev === cardKey ? null : cardKey));
    setPlaceAgentId((prev) => prev || agents[0]?.id || '');
    setPlaceDay((prev) => prev || planningWindowStart || new Date().toISOString().slice(0, 10));
  };

  const handlePlace = async (card: BacklogCard) => {
    if (!placeAgentId || !placeDay) return;
    setIsPlacing(true);
    const ok = await onPlaceCard(card, placeAgentId, placeDay);
    setIsPlacing(false);
    if (ok) {
      setPlacingFor(null);
      setExpandedCard(null);
    }
  };

  const dayHasTimeline = (agentId: string, date: string) =>
    timelines.some((t) => t.agentId === agentId && t.plannedDate === date);
  const agentName = (id: string) => agents.find((a) => a.id === id)?.name ?? '';

  return (
    <aside
      id="jobs-column"
      aria-label="Jobs with work waiting for a day"
      className="w-72 shrink-0 h-full flex flex-col border-r border-neutral-200 bg-neutral-50/40"
    >
      <div className="h-11 px-3 border-b border-neutral-200 flex items-center justify-between shrink-0 bg-neutral-50/60">
        <p className="flex items-center gap-1.5 text-xs font-semibold text-neutral-900" data-testid="jobs-column-count">
          <Briefcase className="w-3.5 h-3.5 text-neutral-500" />
          Jobs ({jobCount})
        </p>
        <button
          type="button"
          data-testid="jobs-column-new-job"
          onClick={() => onOpenJobs()}
          className="flex items-center gap-1 px-2 py-1 text-[11px] font-medium text-neutral-700 border border-neutral-200 rounded bg-white hover:bg-neutral-100"
        >
          <Plus className="w-3 h-3" />
          New job
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-2 space-y-2">
        {isLoading && backlog.length === 0 && <p className="px-1 py-2 text-[11px] text-neutral-400">Loading…</p>}
        {error && (
          <p role="alert" className="px-2 py-2 text-[11px] text-red-700 bg-red-50 border border-red-200 rounded">
            {error}
          </p>
        )}
        {!isLoading && !error && groups.length === 0 && (
          <p className="px-2 py-4 text-[11px] text-neutral-500">
            Nothing is waiting for a day. Start a job from a map with “New job” and its work appears here.
          </p>
        )}

        {groups.map((group) => (
          <section key={group.workItemId} data-testid="jobs-column-job" className="rounded-md border border-neutral-200 bg-white">
            <button
              type="button"
              data-testid="jobs-column-job-title"
              onClick={() => onOpenJobs(group.workItemId)}
              title="Opens this job's detail (lines, exceptions, activity)"
              className="w-full px-2.5 py-1.5 text-left text-xs font-medium text-neutral-900 truncate hover:bg-neutral-50 rounded-t-md"
            >
              {group.jobTitle}
            </button>

            <ul className="divide-y divide-neutral-100 border-t border-neutral-100">
              {group.cards.map((card) => {
                const isExpanded = expandedCard === card.card_key;
                const isPlacingThis = placingFor === card.card_key;
                const stepWord = card.step_count === 1 ? 'step' : 'steps';
                return (
                  <li key={card.card_key} data-testid="jobs-column-card" className="px-2 py-1.5 flex flex-col gap-1.5">
                    <div
                      draggable
                      data-testid="jobs-column-card-handle"
                      onDragStart={(e) => {
                        const payload: JobCardDragPayload = {
                          type: JOB_CARD_DRAG_TYPE,
                          workItemId: card.work_item_id,
                          lensKey: card.lens_key,
                          cardKey: card.card_key,
                        };
                        const str = JSON.stringify(payload);
                        e.dataTransfer.setData('application/json', str);
                        e.dataTransfer.setData('text/plain', str);
                        e.dataTransfer.effectAllowed = 'move';
                      }}
                      className="flex items-start gap-1.5 cursor-grab active:cursor-grabbing"
                      title="Drag onto someone's day, or use Place…"
                    >
                      <GripVertical className="w-3.5 h-3.5 mt-0.5 shrink-0 text-neutral-300" />
                      <div className="min-w-0 flex-1">
                        <p className="text-[11px] text-neutral-800 truncate flex items-center gap-1">
                          {card.lens_label || card.lens_key} · {card.step_count} {stepWord} · {formatMinutes(card.expected_minutes)}
                          <EstimateBadge status={card.estimate_status} />
                        </p>
                        {card.step_count > 1 && (
                          <p className="text-[10px] text-neutral-400 truncate">
                            {card.first_stage_label} → {card.last_stage_label}
                          </p>
                        )}
                        {((card.parent_work_item_id ?? 0) > 0 || (card.child_count ?? 0) > 0) && (
                          <p className="flex flex-wrap gap-1 mt-0.5">
                            {(card.parent_work_item_id ?? 0) > 0 && (
                              <button
                                type="button"
                                data-testid="jobs-column-parent-chip"
                                onClick={() => setPeekId(card.parent_work_item_id!)}
                                className="rounded-full border border-amber-200 bg-amber-50 px-1.5 text-[10px] text-amber-800 hover:bg-amber-100"
                              >
                                from #{card.parent_work_item_id}
                              </button>
                            )}
                            {(card.child_count ?? 0) > 0 && (
                              <button
                                type="button"
                                data-testid="jobs-column-children-chip"
                                onClick={() => setPeekId(card.work_item_id)}
                                className="rounded-full border border-amber-200 bg-amber-50 px-1.5 text-[10px] text-amber-800 hover:bg-amber-100"
                              >
                                {card.child_count} sent on
                              </button>
                            )}
                          </p>
                        )}
                      </div>
                      <div className="shrink-0 flex items-center gap-0.5">
                        <button
                          type="button"
                          onClick={() => setExpandedCard(isExpanded ? null : card.card_key)}
                          aria-expanded={isExpanded}
                          title="Show this card's steps"
                          className="p-1 text-neutral-400 hover:text-neutral-800 rounded"
                        >
                          {isExpanded ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
                        </button>
                        <button
                          type="button"
                          data-testid="jobs-column-place"
                          onClick={() => openPlaceForm(card.card_key)}
                          className="flex items-center gap-1 px-1.5 py-1 text-[10px] font-medium text-neutral-700 border border-neutral-200 rounded hover:bg-neutral-50"
                        >
                          <CalendarPlus className="w-3 h-3" />
                          Place…
                        </button>
                      </div>
                    </div>

                    {/* The card's steps, from the job's PINNED version — what was agreed. */}
                    {isExpanded && (
                      <ol className="border border-neutral-200 rounded-md divide-y divide-neutral-100 bg-neutral-50/60">
                        {card.steps.map((step, index) => (
                          <li key={step.work_task_id} className="px-2 py-1 flex items-start justify-between gap-2">
                            <div className="min-w-0">
                              <p className="text-[10px] text-neutral-800 truncate">
                                {index + 1}. {step.stage_label || step.stage_key}
                              </p>
                              {step.task && <p className="text-[10px] text-neutral-500">{step.task}</p>}
                            </div>
                            <span className="shrink-0 text-[10px] text-neutral-500 font-mono flex items-center gap-1">
                              {formatMinutes(step.expected_minutes)}
                              <EstimateBadge status={step.estimate_status} source={step.estimate_source} />
                            </span>
                          </li>
                        ))}
                      </ol>
                    )}

                    {/* The click path (D-4) — identical rule to the drag, same handler upstream. */}
                    {isPlacingThis && (
                      <div className="flex flex-wrap items-end gap-1.5 bg-neutral-50 border border-neutral-200 rounded-md px-2 py-1.5">
                        <label className="flex flex-col gap-0.5">
                          <span className="text-[10px] text-neutral-600">Who</span>
                          <select
                            value={placeAgentId}
                            onChange={(e) => setPlaceAgentId(e.target.value)}
                            className="text-[11px] px-1.5 py-1 border border-neutral-200 rounded bg-white max-w-[110px]"
                          >
                            {agents.length === 0 && <option value="">No agents in this plan</option>}
                            {agents.map((a) => (
                              <option key={a.id} value={a.id}>{a.name}</option>
                            ))}
                          </select>
                        </label>
                        <label className="flex flex-col gap-0.5">
                          <span className="text-[10px] text-neutral-600">Day</span>
                          <input
                            type="date"
                            value={placeDay}
                            onChange={(e) => setPlaceDay(e.target.value)}
                            className="text-[11px] px-1.5 py-1 border border-neutral-200 rounded font-mono bg-white"
                          />
                        </label>
                        <button
                          type="button"
                          data-testid="jobs-column-place-confirm"
                          onClick={() => void handlePlace(card)}
                          disabled={isPlacing || agents.length === 0 || !placeAgentId || !placeDay}
                          className="px-2.5 py-1.5 bg-neutral-900 text-white rounded text-[11px] font-semibold hover:bg-neutral-800 disabled:opacity-60"
                        >
                          {isPlacing ? 'Placing…' : 'Place'}
                        </button>
                        <span className="text-[10px] text-neutral-500 basis-full">
                          All {card.step_count} {stepWord} go onto that day as one card.
                        </span>
                        {placeAgentId && placeDay && !dayHasTimeline(placeAgentId, placeDay) && (
                          <span className="text-[10px] text-neutral-500 basis-full">
                            {agentName(placeAgentId)} has no day on {placeDay} yet — it will be created.
                          </span>
                        )}
                        {placeAgentId && !agents.find((a) => a.id === placeAgentId)?.userId && (
                          <span className="text-[10px] text-amber-700 basis-full flex items-center gap-1">
                            <AlertTriangle className="w-3 h-3 shrink-0" />
                            {agentName(placeAgentId)} has no login linked — they won't see this in Execution.
                          </span>
                        )}
                      </div>
                    )}
                  </li>
                );
              })}
            </ul>
          </section>
        ))}
      </div>

      <JobPeekSheet workItemId={peekId ?? 0} open={peekId != null} onClose={() => setPeekId(null)} onOpenJob={setPeekId} />
    </aside>
  );
}
