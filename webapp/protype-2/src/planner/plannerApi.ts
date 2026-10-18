// PLN-9 (US-PLN-9-02) — The real backend calls this app makes, in the
// shapes the actual endpoints return (verified against the live
// workspace, not assumed from a spec). `plannerAdapter.ts` maps these
// into the existing frontend types (`src/types.ts`), which this epic
// deliberately keeps unchanged where possible.
import {performRequest, getJourneyMapBaseUrl, getAccountsBaseUrl} from '../perform/performApi';

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

/**
 * Phase-3's plain create, no template — reinstated in the UI on the
 * founder's request (2026-10-17) as an explicit "start from scratch"
 * option, alongside "New Plan from Template". The endpoint never
 * stopped existing or working (FT-PLAN-1-09 confirms it); only the
 * frontend path to it had been removed when PLN-9 wired templates in.
 * No maps, no agents, no template — add those by hand once inside it.
 */
export const createWorkspace = (body: {name: string; planning_window_start: string; planning_window_end: string}) =>
  performRequest<{workspace: RawWorkspace; counts: WorkspaceListEntry['counts']}>('/workspace', {method: 'POST', body});

/**
 * PLN-3 — rename a plan, move its planning window, or change its token
 * throughput. Wired during PLN-9's Opus review pass: the Workspace
 * Settings modal had a literal "Save settings" button that only ever
 * wrote to React state, so a planner could move their planning window,
 * watch the header update, and lose it on the next refresh — with no
 * error, which is exactly what CLAUDE.md's "never fail silently" rule
 * exists to prevent. The window is not cosmetic either: it drives
 * out-of-window publish blocking and the schedule grid's visible dates.
 */
export const updateWorkspace = (
  workspaceId: number,
  body: Partial<{name: string; planning_window_start: string; planning_window_end: string; input_tokens_per_minute: number; output_tokens_per_minute: number}>,
) => performRequest<{workspace: RawWorkspace}>(`/workspace/${workspaceId}`, {method: 'PATCH', body});

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

/**
 * PLN-5 (US-PLN-5-04) — remove an agent from the plan. Pushed
 * 2026-10-16 on the founder's approval of the two non-destructive
 * deletes. NO TASK IS LOST: their days' tasks go back to the backlog
 * and any override pointing at them is cleared.
 *
 * Refuses (E-P3A-002) if the agent has recorded work — a published day
 * or any logged activity — because a frozen publication and the
 * activity log both still point at them.
 */
export const deleteAgent = (agentId: number) =>
  performRequest<{deleted_agent_id: number; timelines_removed: number; tasks_returned: number; assignments_cleared: number}>(
    `/agent/${agentId}`,
    {method: 'DELETE'},
  );

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

/**
 * PLN-6 (US-PLN-6-05) — delete one day. The day goes, the work stays:
 * its tasks return to the backlog, keeping their order. Refuses
 * (E-P3A-003) for a PUBLISHED day, whose frozen publication and log
 * events still reference it.
 */
export const deleteTimeline = (timelineId: number) =>
  performRequest<{deleted_timeline_id: number; tasks_returned: number; moved_ids: number[]}>(`/timeline/${timelineId}`, {
    method: 'DELETE',
  });

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
  /** GAP-FIX W1 — the real text behind each scheduled job step. Optional so an older server still parses. */
  linked_steps?: LinkedStep[];
  settings: RawPlannerSettings;
  models: RawModel[];
}

export const getBoard = (workspaceId: number) => performRequest<BoardResponse>(`/workspace/${workspaceId}/board`);

// ── Maps accepted by a plan (US-PLN-9-06) ───────────────────────────────
//
// `workspace/{id}/map` (569 GET, 570 POST) — new this checkpoint. Found
// missing during E2E-1 (epic finding 5): `template/{id}` PATCH only
// changes what the NEXT instance accepts, so a plan already underway
// had no way to accept a second work type at all. See the endpoints'
// own header comments for the full reasoning. Removing a map isn't
// possible yet — same "deletes are held" reasoning as agents/tasks.

export interface RawWorkspaceMap {
  map_id: number;
  title: string | null;
}

export const listWorkspaceMaps = (workspaceId: number) =>
  performRequest<{maps: RawWorkspaceMap[]}>(`/workspace/${workspaceId}/map`);

export const addWorkspaceMaps = (workspaceId: number, mapIds: number[]) =>
  performRequest<{map_ids: number[]; added_count: number}>(`/workspace/${workspaceId}/map`, {
    method: 'POST',
    body: {map_ids: mapIds},
  });

/**
 * Candidate maps for the "add a map" picker — the journey-map group, not
 * the planner group. Only a hint for the picker; `addWorkspaceMaps` above
 * is what actually re-validates "published" server-side.
 *
 * ⚠️ NOT `GET journey_map/search` (endpoint 210, the account-scoped,
 * published-only search that would have been the right fit) — confirmed
 * live that it 400s with "journey_map_id... not a valid integer" on
 * EVERY call, because `journey_map/{journey_map_id}` (endpoint 23,
 * built earlier) shadows it: Xano's router matches the dynamic path
 * for any `journey_map/<anything>` GET, so the literal segment "search"
 * is parsed as an attempted `journey_map_id` and fails int validation.
 * Endpoint 210 is dead code as a result — a routing collision worth
 * knowing before adding a static path next to an existing dynamic one
 * in the same group (see CLAUDE.md).
 *
 * Falls back to the plain `GET journey_map` (endpoint 18) instead,
 * filtered to `status === 'active'` client-side. Known gap: that
 * endpoint is OWNER-scoped (`owner_user == auth.id`), not account-
 * scoped, so a map owned by a different user in the same account won't
 * appear here even though `addWorkspaceMaps` would accept it. Revisit
 * once the routing collision above is fixed and 210 is reachable.
 */
export interface JourneyMapSearchResult {
  map_id: number;
  title: string;
  status: string;
  /**
   * GAP-FIX W7 — the map's latest published version, or null if it has
   * never been published. Attaching a map REQUIRES one (E-PLAN-004),
   * so a picker that doesn't know this offers maps the server will
   * then refuse. Added to `GET /journey_map` itself (endpoint 18)
   * rather than fetched per map.
   */
  publishedVersionNo: number | null;
}

/**
 * Unpublished maps are RETURNED, NOT FILTERED OUT. A planner looking
 * for the map they just drew needs to see it and be told "publish it
 * first" — a map silently missing from the list is the same dead end
 * W7 is about, just one step earlier. The caller disables them.
 *
 * THE `status === 'active'` FILTER THAT USED TO BE HERE WAS THE REAL
 * BUG, and it was invisible until the fixed picker was opened against
 * real data: a map becomes `active` when it is first published, so
 * "only active maps" and "only published maps" were the same set, and
 * all 12 of this account's draft maps — every map anyone is likely to
 * be looking for — were silently absent with no explanation anywhere.
 * Now only ARCHIVED maps are dropped (they are retired on purpose),
 * and "not published yet" is shown and explained rather than hidden.
 */
export const searchJourneyMaps = () =>
  performRequest<Array<{id: number; title: string; status: string; published_version_no: number | null}>>('/journey_map', {
    baseUrl: getJourneyMapBaseUrl(),
  }).then((maps) => ({
    results: maps
      .filter(m => m.status !== 'archived')
      .map(m => ({map_id: m.id, title: m.title, status: m.status, publishedVersionNo: m.published_version_no ?? null})),
  }));

// ── Plan templates (US-PLN-9-07, PLAN-3 US-PLAN-3-04) ──────────────────────
//
// PLN-9 wired read + instantiate only; creating/editing a template was
// explicitly deferred to this epic (completing PLAN-1's own never-built
// US-PLAN-1-05) — now also carrying the agent roster PLAN-3 adds.

export interface RawTemplate {
  id: number;
  account_id: number;
  name: string;
  window_days: number;
  default_start_time: string;
  is_active: boolean;
}

export interface TemplateListEntry {
  template: RawTemplate;
  maps: Array<{map_id: number; title: string | null}>;
  agents: Array<{profile_id: number; name: string | null}>;
}

export const listTemplates = () => performRequest<{templates: TemplateListEntry[]}>('/template');

export const createTemplate = (body: {
  name: string;
  window_days?: number;
  default_start_time?: string;
  map_ids?: number[];
  agent_profile_ids?: number[];
}) => performRequest<{template: RawTemplate; map_ids: number[]; agent_profile_ids: number[]}>('/template', {method: 'POST', body});

export const updateTemplate = (
  templateId: number,
  body: Partial<{name: string; window_days: number; default_start_time: string; is_active: boolean; add_map_ids: number[]; add_agent_profile_ids: number[]}>,
) => performRequest<{template: RawTemplate; map_ids: number[]; agent_profile_ids: number[]}>(`/template/${templateId}`, {method: 'PATCH', body});

export const createWorkspaceFromTemplate = (templateId: number, body: {name: string; start_date: string}) =>
  performRequest<{
    workspace: RawWorkspace;
    from_template_id: number;
    default_start_time: string;
    window_days: number;
    accepted_map_count: number;
    agent_count: number;
    skipped_agents: SkippedAgent[];
  }>(`/template/${templateId}/instance`, {method: 'POST', body});

/** Why a roster agent was left off a new plan (gap-fix #1). */
export interface SkippedAgent {
  profile_id: number;
  name: string | null;
  reason: 'not_eligible' | 'not_found' | 'duplicate_name';
}

// ── Agent profiles (PLAN-2, US-PLAN-2-02) ──────────────────────────────────
//
// A durable, per-person identity independent of any one plan — see the
// epic's own header for why `planner_agent` alone couldn't do this.
// Account-scoped, not workspace-scoped: these calls don't take a
// workspace id at all.

export interface RawAgentProfile {
  id: number;
  user_id: number;
  account_id: number;
  kind: 'person' | 'ai';
  name: string;
  color: string;
  default_daily_capacity_hours: number;
  is_eligible: boolean;
}

export interface AgentProfileListEntry {
  profile: RawAgentProfile;
  display_name: string;
}

export const listAgentProfiles = (includeIneligible = false) =>
  performRequest<{profiles: AgentProfileListEntry[]}>(`/agent-profile${includeIneligible ? '?include_ineligible=true' : ''}`);

export const createAgentProfile = (body: {user_id?: number; name?: string; color?: string; default_daily_capacity_hours?: number}) =>
  performRequest<{profile: RawAgentProfile}>('/agent-profile', {method: 'POST', body});

export const updateAgentProfile = (
  profileId: number,
  body: Partial<{name: string; color: string; default_daily_capacity_hours: number; is_eligible: boolean}>,
) => performRequest<{profile: RawAgentProfile}>(`/agent-profile/${profileId}`, {method: 'PATCH', body});

// ── Team members (Members & Accounts group) — candidates for tagging ───────

export interface TeamMember {
  id: number;
  created_at: number;
  name: string;
  email: string;
  phone: string | null;
  account_id: number;
}

export const listTeamMembers = () => performRequest<TeamMember[]>('/account/my_team_members', {baseUrl: getAccountsBaseUrl()});

// ── Jobs (GAP-FIX W1, over JOB-1 / SCHED-1) ────────────────────────────────
//
// THE BACKEND FOR ALL OF THIS WAS ALREADY BUILT AND TESTED. JOB-1 and
// SCHED-1 shipped `work_item` (a real instance of the work, whose steps
// come from a map's frozen version) and the scheduling link that puts
// one of those steps on somebody's day — and nothing in the planner UI
// ever called any of it. There were zero references to `work_item`,
// `job_id` or `createJob` anywhere under `planner/`. "Add task" made a
// plain `planner_task`: a title, a duration and a slot, with no
// connection to any map. So attaching a map to a plan changed nothing a
// user could see, and Execution showed steps with no instructions and
// no done-when — the exact things the map exists to carry.
//
// These are the calls that were missing, not new capability.

export interface RawWorkItem {
  id: number;
  account_id: number;
  workspace_id: number;
  journey_map_version_id: number;
  title: string;
  status: 'open' | 'in_progress' | 'blocked' | 'completed' | 'cancelled';
  attributes: Record<string, unknown>;
  parent_work_item_id: number;
  created_by: number;
  started_at: number;
  finished_at: number;
}

export interface WorkItemListEntry {
  work_item: RawWorkItem;
  task_count: number;
  finished_count: number;
  has_blocked: boolean;
  has_progress: boolean;
}

/**
 * Create a job from one of the plan's accepted maps.
 *
 * THE JOB IS PINNED TO THAT MAP'S LATEST PUBLISHED VERSION AT THIS
 * MOMENT, and the pin never moves — later edits or republishes cannot
 * change a job already underway. Refuses with a friendly message if
 * the plan doesn't accept the map (E-JOB-002) or the map has never
 * been published (E-JOB-003).
 */
export const createWorkItem = (body: {workspace_id: number; journey_map_id: number; title: string}) =>
  performRequest<{
    work_item: RawWorkItem;
    pinned_version: {id: number; version_no: number};
    task_count: number;
    skipped_stages: unknown[];
  }>('/work_item', {method: 'POST', body});

/** Cancelled jobs are excluded unless asked for — they're history, not work waiting to happen. */
export const listWorkItems = (workspaceId: number, includeCancelled = false) =>
  performRequest<{work_items: WorkItemListEntry[]}>(
    `/workspace/${workspaceId}/work_item${includeCancelled ? '?include_cancelled=true' : ''}`,
  );

/** US-JOB-1-05 — a cancelled job's steps leave the backlog but stay as history. */
export const cancelWorkItem = (workItemId: number) =>
  performRequest<{work_item: RawWorkItem; was_already_cancelled: boolean; message: string}>(
    `/work_item/${workItemId}/cancel`,
    {method: 'POST', body: {}},
  );

/**
 * Every job step in this plan with no slot on the schedule yet, with
 * its text and expected minutes read from its job's PINNED version —
 * what was agreed, not what the live map says today.
 */
export interface BacklogWorkRow {
  work_task_id: number;
  work_item_id: number;
  job_title: string | null;
  stage_key: string;
  lens_key: string;
  status: string;
  task: string | null;
  done_when: string | null;
  expected_minutes: number | null;
}

export const listBacklogWork = (workspaceId: number) =>
  performRequest<{workspace_id: number; count: number; backlog: BacklogWorkRow[]}>(
    `/workspace/${workspaceId}/backlog_work`,
  );

/**
 * Put a job step on a day. The slot's duration defaults to the step's
 * expected minutes from the pinned version, so scheduling changes
 * nothing about what was agreed. Scheduling the same step twice is
 * impossible (unique index), not merely checked.
 */
export const scheduleWorkTask = (
  workTaskId: number,
  body: {timeline_id: number; duration_minutes?: number; assignee_agent_id?: number},
) =>
  performRequest<{
    planner_task: RawTask;
    work_task_id: number;
    expected_minutes: number | null;
    scheduled_minutes: number;
    is_tweaked: boolean;
  }>(`/work_task/${workTaskId}/schedule`, {method: 'POST', body});

/**
 * GAP-FIX W1 — what a scheduled job step actually says, for every slot
 * in the plan. Returned by the board; see `planner/job_step_hydration`.
 */
export interface LinkedStep {
  planner_task_id: number;
  work_task_id: number;
  work_item_id: number;
  job_title: string | null;
  job_status: string;
  stage_key: string;
  lens_key: string;
  step_status: string;
  step_title: string | null;
  done_when: string | null;
  expected_minutes: number | null;
}
