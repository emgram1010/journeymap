// PLN-9 (US-PLN-9-02) — Maps the real backend's shapes onto this app's
// EXISTING frontend types (`src/types.ts`), which this epic
// deliberately leaves unchanged wherever the two already agree — the
// whole UI (components, planningLogic.ts) keeps working unmodified.
//
// Every id becomes a string here — the frontend has always used
// string ids (it used to generate its own with `crypto.randomUUID()`
// for localStorage rows); the backend's are real numeric database ids.
// Nothing compares an id to a number anywhere in the existing code, so
// this is a safe, one-direction conversion at the boundary.
//
// `0` AS A SENTINEL BECOMES `null`/`undefined` HERE, matching the
// frontend's own conventions (`Task.timelineId: string | null`,
// `Agent.modelId?: string`) — the backend can't store a real null for
// an int column (no real nullable FKs in this workspace, see
// CLAUDE.md), so it uses `0`; the frontend was written assuming a
// real optional/null. This boundary is where that gets reconciled.
import type {Agent, AppSettings, ModelPricing, Task, Timeline, Workspace} from './types';
import type {BoardResponse, LinkedStep, RawAgent, RawModel, RawTask, RawTimeline, RawWorkspace, WorkspaceListEntry} from './plannerApi';

export function adaptWorkspace(entry: WorkspaceListEntry): Workspace {
  const w: RawWorkspace = entry.workspace;
  return {
    id: String(w.id),
    name: w.name,
    createdAt: new Date(w.created_at).toISOString(),
    planningWindowStart: w.planning_window_start,
    planningWindowEnd: w.planning_window_end,
    inputTokensPerMinute: w.input_tokens_per_minute,
    outputTokensPerMinute: w.output_tokens_per_minute,
  };
}

export function adaptAgent(raw: RawAgent): Agent {
  return {
    id: String(raw.id),
    workspaceId: String(raw.workspace_id),
    name: raw.name,
    kind: raw.kind,
    color: raw.color,
    dailyCapacityHours: raw.daily_capacity_hours,
    isVisible: raw.is_visible,
    modelId: raw.model_id !== 0 ? String(raw.model_id) : undefined,
    userId: raw.user_id !== 0 ? String(raw.user_id) : undefined,
  };
}

export function adaptTimeline(raw: RawTimeline): Timeline {
  return {
    id: String(raw.id),
    workspaceId: String(raw.workspace_id),
    agentId: String(raw.agent_id),
    name: raw.label,
    plannedDate: raw.planned_date,
    assignee: raw.agent_name ?? '',
    status: raw.status,
    startTime: raw.start_time,
  };
}

export function adaptModel(raw: RawModel): ModelPricing {
  return {
    id: String(raw.id),
    label: raw.label,
    inputPer1M: raw.input_per_1m,
    outputPer1M: raw.output_per_1m,
    isCustom: raw.is_custom,
  };
}

/** `currencySymbol` defaults to "$" when blank — matches the backend's own documented default. */
export function adaptSettings(board: BoardResponse): AppSettings {
  return {
    currencySymbol: board.settings.currency_symbol || '$',
    humanHourlyRate: board.settings.human_hourly_rate,
    models: board.models.map(adaptModel),
  };
}

/** Everything one workspace's board needs, already converted to this app's own types. */
export function adaptBoard(board: BoardResponse) {
  // GAP-FIX W1 — keyed by planner_task id so a linked slot can be given
  // the text it was always meant to show.
  const stepsByTask = new Map<number, LinkedStep>();
  for (const step of board.linked_steps ?? []) stepsByTask.set(step.planner_task_id, step);

  return {
    agents: board.agents.map(adaptAgent),
    timelines: board.timelines.map(adaptTimeline),
    tasks: board.tasks.map((t) => adaptTask(t, stepsByTask.get(t.id))),
    settings: adaptSettings(board),
  };
}

export function adaptTask(raw: RawTask, step?: LinkedStep): Task {
  // A linked slot stores no title of its own (see Task.jobStepTitle).
  // The fallback chain ends at the stage key so a card is never blank,
  // even if a version somehow has no text for that cell.
  const linkedTitle = step ? step.step_title || `${step.job_title ?? 'Job'} — ${step.stage_key}` : null;
  return {
    id: String(raw.id),
    workspaceId: String(raw.workspace_id),
    timelineId: raw.timeline_id !== 0 ? String(raw.timeline_id) : null,
    title: raw.title || linkedTitle || '',
    seq: raw.seq,
    planned_start: raw.planned_start ?? '',
    duration: raw.duration_minutes,
    assignee: raw.effective_assignee.name ?? undefined,
    notes: raw.notes,
    status: raw.status,
    needsInfoReason: raw.needs_info_reason || undefined,
    ...(step
      ? {
          jobTitle: step.job_title ?? undefined,
          jobStepTitle: step.step_title ?? undefined,
          jobDoneWhen: step.done_when ?? undefined,
          workTaskId: String(step.work_task_id),
          workItemId: String(step.work_item_id),
        }
      : {}),
  };
}
