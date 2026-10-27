// PLN-9 (US-PLN-9-02) — The real backend calls this app makes, in the
// shapes the actual endpoints return (verified against the live
// workspace, not assumed from a spec). `plannerAdapter.ts` maps these
// into the existing frontend types (`src/types.ts`), which this epic
// deliberately keeps unchanged where possible.
import {performRequest, getJourneyMapBaseUrl, getAccountsBaseUrl} from '../perform/performApi';
import {getXanoCatalogBaseUrl} from '../xano';

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
 * Candidate maps for the "add a map" picker — the journey-map group,
 * not the planner group. Only a hint for the picker; `addWorkspaceMaps`
 * is what actually re-validates "published" server-side.
 *
 * ACCOUNT-SCOPED SINCE O8 (2026-10-17). This used to read the plain
 * `GET journey_map` (endpoint 18), which filters `owner_user ==
 * auth.id` — so a map drawn by a teammate never appeared in any
 * picker, even though attaching it would have been accepted. Invisible
 * on a one-person account, and indistinguishable from "the map
 * vanished" the moment there are two. Confirmed against real data:
 * the owner-scoped list returned 14 maps where the account has 17.
 *
 * ⚠️ NOT `GET journey_map/search` (endpoint 210, built for exactly
 * this and account-scoped) — confirmed live that it 400s with
 * "journey_map_id... not a valid integer" on EVERY call, because
 * `journey_map/{journey_map_id}` (endpoint 23, built earlier) shadows
 * it: Xano's router matches the dynamic path for any
 * `journey_map/<anything>` GET, so the literal segment "search" is
 * parsed as an attempted id and fails int validation. The endpoint
 * here uses a DIFFERENT STATIC PREFIX so no collision is possible —
 * the workaround CLAUDE.md recommends for this shape. 210 is still
 * dead code, and still carries the `status == "active"` filter that
 * hid every draft map plus a telemetry write on every call.
 *
 * Unpublished maps are RETURNED, NOT FILTERED OUT. A planner looking
 * for the map they just drew needs to see it and be told "publish it
 * first" — a map silently missing from the list is the same dead end,
 * one step earlier. The caller disables them.
 */
export interface JourneyMapSearchResult {
  map_id: number;
  title: string;
  status: string;
  /**
   * GAP-FIX W7 — the map's latest published version, or null if it has
   * never been published. Attaching a map REQUIRES one (E-PLAN-004),
   * so a picker that doesn't know this offers maps the server will
   * then refuse.
   */
  publishedVersionNo: number | null;
}

export const searchJourneyMaps = () =>
  performRequest<{
    account_id: number;
    count: number;
    maps: Array<{map_id: number; title: string; status: string; published_version_no: number | null}>;
  }>('/journey_map_attachable', {baseUrl: getJourneyMapBaseUrl()}).then((data) => ({
    results: data.maps.map((m) => ({
      map_id: m.map_id,
      title: m.title,
      status: m.status,
      publishedVersionNo: m.published_version_no ?? null,
    })),
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
  /** EXC-1 — jobs started from this one (exception spawns and jobs added under it), any status. */
  child_count?: number;
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
 * Everything in this plan waiting for a day, as CARDS.
 *
 * BLK-1 (US-BLK-1-01) — one row is one job's unscheduled steps for ONE
 * ACTOR ROW, which is the unit a person actually picks up. Before it, a
 * customer's return arrived here as eight separate rows.
 *
 * Text and expected minutes are read from each job's PINNED version —
 * what was agreed, not what the live map says today — and the steps
 * arrive in that version's stage order, which ORD-1 made mutable.
 */
export interface BacklogCardStep {
  work_task_id: number;
  stage_key: string;
  stage_label: string;
  status: string;
  task: string | null;
  done_when: string | null;
  expected_minutes: number | null;
  /** EST-1 — 'n/a' on a map with no Items row; 'incomplete' when this stage is missing a rate for something in the order. */
  estimate_status?: 'n/a' | 'complete' | 'incomplete';
  /** EST-1 — 'n/a' / 'seed' / 'measured'. A guess (seed) still shows the number; the badge just says so. */
  estimate_source?: 'n/a' | 'seed' | 'measured';
}

export interface BacklogCard {
  /** `work_item_id::lens_key`, the card's identity. Safe as a React key; `work_task_id` is not — a card has several. */
  card_key: string;
  work_item_id: number;
  job_title: string | null;
  lens_key: string;
  lens_label: string;
  step_count: number;
  /** Summed over the card's steps, from the pinned version (or the real estimate, EST-1). */
  expected_minutes: number;
  /** EST-1 — the worst of the card's steps: 'incomplete' if any step is, else 'complete' if any step was estimated, else 'n/a'. */
  estimate_status?: 'n/a' | 'complete' | 'incomplete';
  first_stage_label: string;
  last_stage_label: string;
  work_task_ids: number[];
  steps: BacklogCardStep[];
  /** EXC-1 — 0 unless this card's job was started from another job. */
  parent_work_item_id?: number;
  /** EXC-1 — open jobs started from this card's job. */
  child_count?: number;
}

export const listBacklogWork = (workspaceId: number) =>
  performRequest<{workspace_id: number; count: number; backlog: BacklogCard[]}>(
    `/workspace/${workspaceId}/backlog_work`,
  );

/**
 * Put a whole CARD on a day: one slot linked to every unscheduled step
 * of that job for that actor row, in the pinned version's stage order.
 *
 * THE CALLER NAMES THE CARD; THE SERVER DERIVES THE STEPS. Sending
 * `work_item_id` + `lens_key` rather than a list of step ids removes
 * the whole class of "the list was nearly right" failure — there is no
 * list to be wrong, and no way to express a card spanning two jobs or
 * two actor rows.
 *
 * The duration defaults to the summed expected minutes, so scheduling
 * changes nothing about what was agreed. Scheduling any step twice is
 * impossible (unique index), not merely checked — the server turns that
 * into a sentence (`E-SCHED-001`) instead of a database error.
 *
 * ⚠️ `POST work_task/{id}/schedule` (endpoint 560) is still live for API
 * callers, but NO SCREEN MAY CALL IT. A single-step card goes through
 * here too; two UI paths to the same write is how the two eventually
 * disagree about the rule (US-BLK-1-07).
 */
export const scheduleCard = (body: {
  work_item_id: number;
  lens_key: string;
  timeline_id: number;
  duration_minutes?: number;
  assignee_agent_id?: number;
}) =>
  performRequest<{
    planner_task: RawTask;
    work_item_id: number;
    lens_key: string;
    work_task_ids: number[];
    step_count: number;
    expected_minutes: number;
    scheduled_minutes: number;
    is_tweaked: boolean;
  }>('/card/schedule', {method: 'POST', body});

/**
 * O4 — take a job step back off the schedule.
 *
 * The other half of scheduling, which shipped without one (the
 * step-level `scheduleWorkTask` wrapper it was written against is gone;
 * `scheduleCard` replaced it in US-BLK-1-07). The
 * step itself survives: it returns to "waiting for a day" and keeps
 * reading its text from its job's pinned version. Only the slot and
 * the link go.
 *
 * Refuses on a published day (E-SCHED-006) or once anything has been
 * recorded against the step (E-SCHED-007). Calling it on a step that
 * isn't scheduled is NOT an error — `already_unscheduled` says so.
 *
 * BLK-1 — NAMING ONE STEP RELEASES THE WHOLE CARD, and both refusals
 * are checked against every step the slot covers. The slot is the unit
 * being released, so releasing half of one is not a thing that can be
 * asked for; `released_work_task_ids` says what actually came back.
 */
export const unscheduleWorkTask = (workTaskId: number) =>
  performRequest<{
    work_task_id: number;
    already_unscheduled: boolean;
    removed_slot_id: number;
    container: number;
    released_work_task_ids: number[];
    released_count: number;
  }>(`/work_task/${workTaskId}/schedule`, {method: 'DELETE'});

/**
 * GAP-FIX W1 — what a scheduled job step actually says, for every slot
 * in the plan. Returned by the board; see `planner/job_step_hydration`.
 */
export interface LinkedStep {
  planner_task_id: number;
  work_task_id: number;
  /** `planner_task_work_task.position`, 1..n — the order the steps were agreed in. Optional: added to the hydration in US-BLK-1-07. */
  position?: number | null;
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

// ── What came back from Execution (W3) ─────────────────────────────────────
//
// THE LOOP WAS ONE-WAY. Everything below already existed server-side and
// had never been called from anywhere: `variance.ts` (pure, tested),
// endpoint 568, and an `activity_log` table that nothing read back. A
// performer could be blocked twice and leave a note saying exactly why,
// and no screen could show it.

export interface TaskVarianceRow {
  work_task_id: number;
  stage_key: string;
  lens_key: string;
  status: string;
  expected_minutes: number | null;
  scheduled_minutes: number | null;
  actual_minutes: number | null;
  blocked_minutes: number | null;
  expected_gap_minutes: number | null;
  expected_gap_pct: number | null;
  scheduled_gap_minutes: number | null;
  scheduled_gap_pct: number | null;
  start_lateness_minutes: number | null;
  is_outlier: boolean;
  warnings: string[];
}

/** Planned vs actual for one job. Computed on the fly from the log — nothing is stored, and nobody reports variance by hand (VAR-1). */
export const getWorkItemVariance = (workItemId: number) =>
  performRequest<{
    work_item_id: number;
    task_count: number;
    outlier_count: number;
    warning_count: number;
    tasks: TaskVarianceRow[];
  }>(`/variance/work_item/${workItemId}`);

export interface ActivityEvent {
  id: number;
  work_task_id: number;
  step_title: string | null;
  stage_key: string | null;
  event_type: 'started' | 'completed' | 'blocked' | 'unblocked' | 'skipped' | 'reopened' | 'note';
  reason_code: string | null;
  note: string | null;
  occurred_at: number | null;
  performer_name: string | null;
  source: string;
}

/** The human half: what was said, by whom, when. Step wording comes from the job's pinned version, so a note reads against the text the person actually saw. */
export const getWorkItemActivity = (workItemId: number) =>
  performRequest<{
    work_item_id: number;
    job_title: string;
    event_count: number;
    note_count: number;
    blocked_count: number;
    skipped_count: number;
    events: ActivityEvent[];
  }>(`/work_item/${workItemId}/activity`);

// ── EST-1: what's in this order ─────────────────────────────────────────
//
// `work_item_line` — the counts on a job. The map owns the per-unit
// RATE (stage_rate, RATE-1); this is the only place the COUNT lives.
// `estimate_job` (the one formula) turns the two into the real
// per-stage minutes the rest of the planner now reads.

export interface EstimateStage {
  stage_key: string;
  scales_with: 'per_order' | 'per_unit' | 'per_flagged_unit';
  baseline_minutes: number;
  variable_minutes: number;
  total_minutes: number;
  source: 'measured' | 'seed' | 'n/a';
  by_method: {method_key: string; minutes: number}[];
  missing: string[];
}

export interface JobEstimate {
  work_item_id?: number;
  journey_map_version_id?: number;
  has_items_row: boolean;
  complete: boolean;
  total_minutes: number;
  stages: EstimateStage[];
  missing: {stage_key: string; quantity_key: string}[];
  reasons: string[];
}

export interface WorkItemLine {
  id: number;
  item_type_id: number;
  item_key: string;
  item_label: string;
  unit: string;
  is_active: boolean;
  quantity: number;
  flagged_quantity: number;
  by_stage: {stage_key: string; minutes: number}[];
}

/** EST-1 Opus review fix (finding #8a) — the version's own priceable items, read from `stage_rate`, not the account's whole catalog. */
export interface AvailableItem {
  item_type_id: number;
  key: string;
  label: string;
  unit: string;
  is_active: boolean;
}

/** US-EST-1-02 — this job's lines, each with its own per-stage contribution, plus the job's whole estimate. */
export const getWorkItemLines = (workItemId: number) =>
  performRequest<{
    work_item_id: number;
    lines: WorkItemLine[];
    estimate: JobEstimate;
    available_items: AvailableItem[];
    frozen: boolean;
  }>(`/work-item/${workItemId}/lines`);

/**
 * Replace the job's whole set of lines. The server REJECTS a repeated
 * item with E-EST-006 ("change its quantity instead") — it does not
 * merge duplicate lines into one quantity. (Opus review pass, 2026-10-25:
 * an earlier version of this comment claimed a merge; it does not exist.)
 * Refuses once any of the job's steps has started (E-EST-007). Returns
 * the fresh estimate so the caller can repaint without a second request.
 */
export const putWorkItemLines = (workItemId: number, lines: {item_type_id: number; quantity: number}[]) =>
  performRequest<{
    work_item_id: number;
    line_count: number;
    estimate: JobEstimate;
    refreshed_count: number;
    tweaked_skipped_count: number;
  }>(`/work-item/${workItemId}/lines`, {method: 'PUT', body: {lines}});

// ── CAT-1's catalog, read-only here ──────────────────────────────────────
// The item picker needs the account's active items. CAT-1's own group
// (getXanoCatalogBaseUrl) is a different base URL from the planner's.

export interface CatalogItemType {
  id: number;
  account_id: number;
  key: string;
  label: string;
  unit: string;
  is_active: boolean;
}

export const listCatalogItemTypes = () =>
  performRequest<{items: CatalogItemType[]}>('/item-type', {baseUrl: getXanoCatalogBaseUrl()});

// ── EXC-1 — exceptions: work leaves this journey for a linked map ────────

/** Where a job came from (null for an ordinary job). `via` says whether it was an exception or added by hand. */
export interface JobParentLink {
  work_item_id: number;
  title: string;
  status: string;
  stage_key: string;
  stage_label: string;
  reason_code: string;
  note: string;
  moved_lines: {item_type_id: number; item_key: string; quantity: number}[];
  created_at: number;
  via: 'exception' | 'manual';
}

export interface JobChildLink {
  work_item_id: number;
  title: string;
  status: string;
  target_map_title: string;
  stage_key: string;
  stage_label: string;
  reason_code: string;
  note: string;
  moved_lines: {item_type_id: number; item_key: string; quantity: number}[];
  parent_blocked: boolean;
  created_at: number;
  via: 'exception' | 'manual';
}

export interface JobSendOption {
  work_task_id: number;
  stage_key: string;
  stage_label: string;
  target_map_id: number;
  target_map_title: string;
  published: boolean;
}

/** GET work_item/{id}/links (611) — where a job came from, what was sent off it, and what each step can send. */
export const getWorkItemLinks = (workItemId: number) =>
  performRequest<{
    work_item_id: number;
    parent: JobParentLink | null;
    children: JobChildLink[];
    send_options: JobSendOption[];
  }>(`/work_item/${workItemId}/links`);

export interface RaiseExceptionResult {
  exception_id: number;
  child: {
    work_item_id: number;
    title: string;
    journey_map_version_id: number;
    version_no: number;
    status: string;
    task_count: number;
    lines: {item_type_id: number; item_key: string; quantity: number}[];
  };
  parent: {work_item_id: number; lines_after: {item_type_id: number; quantity: number}[]; refreshed_count: number; tweaked_skipped_count: number};
  parent_blocked: boolean;
  block_refusal: string;
  /** True when the send saved but a follow-up (estimate, slots, feed note, block) failed — logged for Health. */
  followup_failed?: boolean;
}

/**
 * Endpoint 610 — "this part of the job is leaving the happy path". Starts a
 * child job on the linked map (its latest published version), moves the
 * counts that left, records why. The parent keeps going unless
 * `also_block_parent` is set, and then it goes through LOG-1's engine; a
 * refused block does not fail the send (`parent_blocked` says what happened).
 */
export const raiseException = (
  workTaskId: number,
  body: {
    target_map_id: number;
    reason_code: string;
    note?: string;
    lines: {item_type_id: number; quantity: number}[];
    also_block_parent: boolean;
    correlation_id?: string;
  },
) => performRequest<RaiseExceptionResult>(`/work-task/${workTaskId}/exception`, {method: 'POST', body});

