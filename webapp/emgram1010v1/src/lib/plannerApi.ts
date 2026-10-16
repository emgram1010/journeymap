// PLN-9 (US-PLN-9-02) — The real backend calls this app makes, in the
// shapes the actual endpoints return (verified against the live
// workspace, not assumed from a spec). `plannerAdapter.ts` maps these
// into the existing frontend types (`src/types.ts`), which this epic
// deliberately keeps unchanged where possible.
import {performRequest} from './performApi';

// ── Workspaces (plans) ──────────────────────────────────────────────────

export interface RawWorkspace {
  id: number;
  name: string;
  created_at: number;
  planning_window_start: string;
  planning_window_end: string;
  input_tokens_per_minute: number;
  output_tokens_per_minute: number;
  is_archived: boolean;
  plan_template_id: number;
}

export interface WorkspaceListEntry {
  workspace: RawWorkspace;
  counts: {agent_count: number; timeline_count: number; task_count: number; backlog_count: number};
}

export const listWorkspaces = () => performRequest<{workspaces: WorkspaceListEntry[]}>('/workspace');

// ── Agents ───────────────────────────────────────────────────────────────

export interface RawAgent {
  id: number;
  workspace_id: number;
  name: string;
  kind: 'person' | 'ai';
  color: string;
  daily_capacity_hours: number;
  is_visible: boolean;
  model_id: number;
  user_id: number;
  is_active: boolean;
}

export const listAgents = (workspaceId: number) =>
  performRequest<{agents: {agents: Array<{agent: RawAgent; model: unknown}>}}>(`/workspace/${workspaceId}/agent`);

export const createAgent = (
  workspaceId: number,
  body: {name: string; kind: 'person' | 'ai'; color?: string; daily_capacity_hours?: number; model_id?: number},
) => performRequest<{agent: RawAgent}>(`/workspace/${workspaceId}/agent`, {method: 'POST', body});

export const updateAgent = (
  agentId: number,
  body: Partial<{name: string; kind: 'person' | 'ai'; color: string; daily_capacity_hours: number; model_id: number; is_visible: boolean; user_id: number}>,
) => performRequest<{agent: RawAgent}>(`/agent/${agentId}`, {method: 'PATCH', body});

/** PLN-5 (US-PLN-5-03) — "show all"/"hide all" in one call, every agent in the plan. */
export const setWorkspaceAgentVisibility = (workspaceId: number, visible: boolean) =>
  performRequest<{agents: RawAgent[]}>(`/workspace/${workspaceId}/agent/visibility`, {method: 'POST', body: {visible}});

// ── Timelines ────────────────────────────────────────────────────────────

export interface RawTimeline {
  id: number;
  workspace_id: number;
  agent_id: number;
  agent_name: string | null;
  label: string;
  planned_date: string;
  start_time: string;
  status: 'draft' | 'published';
  task_count: number;
  total_minutes: number;
  out_of_window: boolean;
}

export const listTimelines = (workspaceId: number, dateFrom?: string, dateTo?: string) => {
  const qs = new URLSearchParams();
  if (dateFrom) qs.set('date_from', dateFrom);
  if (dateTo) qs.set('date_to', dateTo);
  const suffix = qs.toString() ? `?${qs.toString()}` : '';
  return performRequest<{timelines: RawTimeline[]}>(`/workspace/${workspaceId}/timeline${suffix}`);
};

/** PLN-6 — idempotent: an existing (agent_id, planned_date) row is returned as `created: false`, never duplicated. */
export const createTimeline = (workspaceId: number, agentId: number, plannedDate: string, startTime?: string) =>
  performRequest<{timeline: RawTimeline; created: boolean; out_of_window: boolean}>(`/workspace/${workspaceId}/timeline`, {
    method: 'POST',
    body: {agent_id: agentId, planned_date: plannedDate, ...(startTime ? {start_time: startTime} : {})},
  });

/** PLN-6 — start_time, or moving to another agent/date. Refuses (does not merge) if the target cell is already taken. */
export const updateTimeline = (
  timelineId: number,
  body: Partial<{agent_id: number; planned_date: string; start_time: string}>,
) => performRequest<{timeline: RawTimeline}>(`/timeline/${timelineId}`, {method: 'PATCH', body});

/** LIVE-1 — freezes this day for the performer. Throws with every blocker's message if the day isn't ready. */
export const publishTimeline = (timelineId: number) =>
  performRequest<{publication: {id: number; timeline_id: number; item_count: number}; published_at: number}>(
    `/timeline/${timelineId}/publish`,
    {method: 'POST'},
  );

/** PLN-7 — exact permutation of this timeline's own task ids; a partial or foreign id is refused and nothing is written. */
export const reorderTimeline = (timelineId: number, taskIds: number[]) =>
  performRequest<{tasks: RawTask[]}>(`/timeline/${timelineId}/reorder`, {method: 'POST', body: {task_ids: taskIds}});

// ── Tasks (one timeline, or the backlog when timelineId is 0/omitted) ────

export interface RawTask {
  id: number;
  workspace_id: number;
  timeline_id: number;
  seq: number;
  title: string | null;
  duration_minutes: number;
  notes: string;
  status: 'planned' | 'needs_info';
  needs_info_reason: string;
  tweak_reason: string;
  assignee_agent_id: number;
  /** "HH:MM", or null for a backlog task — never stored, always derived server-side (planner_task's own header comment explains why). */
  planned_start: string | null;
  effective_assignee: {agent_id: number; name: string | null};
}

export const listTasks = (workspaceId: number, timelineId?: number) => {
  const qs = timelineId ? `?timeline_id=${timelineId}` : '';
  return performRequest<{timeline_id: number; is_backlog: boolean; tasks: RawTask[]}>(`/workspace/${workspaceId}/task${qs}`);
};

/** PLN-7 — omit `timeline_id` for the backlog. Appended at the end; the container is resequenced server-side. */
export const createTask = (
  workspaceId: number,
  body: {title: string; duration_minutes?: number; notes?: string; timeline_id?: number; assignee_agent_id?: number},
) => performRequest<{task_id: number; container: RawTask[]}>(`/workspace/${workspaceId}/task`, {method: 'POST', body});

/** PLN-7 — a task's own fields only. Never moves it — see placeTask. */
export const updateTask = (
  taskId: number,
  body: Partial<{title: string; duration_minutes: number; notes: string; assignee_agent_id: number; status: 'planned' | 'needs_info'; needs_info_reason: string}>,
) => performRequest<{task: RawTask; container: RawTask[]}>(`/task/${taskId}`, {method: 'PATCH', body});

/** PLN-7 — the only thing allowed to move a task: another timeline, or the backlog when `timeline_id` is omitted/0. */
export const placeTask = (taskId: number, body: {timeline_id?: number; index?: number}) =>
  performRequest<{moved: {source_timeline_id: number; clamped_index: number}; destination_tasks: RawTask[]}>(`/task/${taskId}/place`, {
    method: 'POST',
    body,
  });

// ── The whole plan in one request (PLN-8) ───────────────────────────────
//
// Built specifically so this app's `loadStoredData()`-shaped load
// doesn't become a waterfall of requests — its own header comment says
// so. One call replaces listAgents + listTimelines + one listTasks per
// container. Prefer this for the primary load; the narrower calls
// above stay useful for a single mutation's own follow-up refetch.

export interface RawPlannerSettings {
  currency_symbol: string;
  human_hourly_rate: number;
}

export interface RawModel {
  id: number;
  account_id: number;
  model_key: string;
  label: string;
  input_per_1m: number;
  output_per_1m: number;
  is_custom: boolean;
}

export interface BoardResponse {
  workspace: RawWorkspace;
  agents: RawAgent[];
  timelines: RawTimeline[];
  tasks: RawTask[];
  settings: RawPlannerSettings;
  models: RawModel[];
}

export const getBoard = (workspaceId: number) => performRequest<BoardResponse>(`/workspace/${workspaceId}/board`);
