# PLN-5 — Agents

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-03):** an agent with a published timeline or log events is deactivated, not deleted.

**Epic ID:** PLN-5
**Status:** Planning
**Depends on:** PLN-3, PLN-4
**Goal:** CRUD for workspace agents (people and AI), including show/hide, model assignment, and a delete that propagates correctly to timelines and tasks.

---

## Context

Frontend: `handleSaveAgent`, `handleDeleteAgent`, `handleToggleAgentVisibility`, `handleShowAllAgents`, `handleHideAllAgents` in `App.tsx`; the **Agents** popover (`AgentsPopover.tsx`) and the edit modal (`EditModal.tsx`, `entity.type === 'agent'`). Today a rename rewrites `assignee` strings on every timeline and task; with the normalized model nothing needs rewriting.

## Existing Architecture (Do Not Break)

- AI agents carry a model (drives token-based cost); people do not.
- Visibility is a per-agent flag (`is_visible`) shared by the Plan and Schedule views.
- Removing an agent returns its tasks to the backlog (nothing is destroyed except the emptied timelines) — this is the shipped behavior in `handleDeleteAgent`.

## Non-Goals

- No agent reordering (list order is `created_at`, then `id`).
- No linking to journey-map actors.

## Endpoints

| Verb | Path | Purpose |
|---|---|---|
| GET | `planner/workspace/{workspace_id}/agent` | List (all, including hidden) |
| POST | `planner/workspace/{workspace_id}/agent` | Create |
| PATCH | `planner/agent/{agent_id}` | Update fields / visibility |
| DELETE | `planner/agent/{agent_id}` | Delete with propagation |
| POST | `planner/workspace/{workspace_id}/agent/visibility` | Bulk show-all / hide-all |

---

## Stories

### US-PLN-5-01 — Create agent

- Input: `name` (required, 1–60, trimmed), `kind` (`person|ai`), `color` (hex; default = next unused palette color, same palette as `AGENT_PALETTE`), `daily_capacity_hours` (0 < x ≤ 24, default 8), `model_id` (optional).
- `model_id` allowed only when `kind = ai` **and** the model belongs to the workspace's account.

**Acceptance:**
- Duplicate name in the workspace → `inputerror`.
- `kind = person` with a `model_id` → `inputerror`.
- `model_id` from another account → `notfound`.
- New agents are `is_visible = true`.

### US-PLN-5-02 — Update agent

- PATCH any of `name`, `kind`, `color`, `daily_capacity_hours`, `model_id`, `is_visible`.
- Switching `kind` from `ai` to `person` clears `model_id` in the same write.
- Renaming writes **only** the agent row.

**Acceptance:**
- After renaming, a timeline/task hydrated read (PLN-8) shows the new name with no other row changed (assert `updated_at` of timelines/tasks unchanged).
- Rename to an existing name → `inputerror`; rename to its own name → OK.
- Switching person → ai without a model is allowed (model may be set later); the UI shows no cost until chosen.

### US-PLN-5-03 — Visibility (single + bulk)

- Single: PATCH `is_visible`. Bulk: `POST …/agent/visibility {visible: true|false}` updates all agents in the workspace in one call.

**Acceptance:** Bulk hide leaves rows intact (no timelines/tasks affected); bulk call returns the updated list.

### US-PLN-5-04 — Delete agent (propagation)

**Files:** `functions/planner/delete_agent_cascade.xs`, `functions/planner/return_tasks_to_backlog.xs`

- `return_tasks_to_backlog(task_filter)` is the shared primitive (reused by PLN-6 and PLN-7): sets `timeline_id = null`, assigns `seq` continuing after the current max backlog `seq` in the workspace (preserving the tasks' previous relative order), clears nothing else.
- Cascade: (1) tasks in the agent's timelines → backlog; (2) tasks whose `assignee_agent_id` is this agent → `assignee_agent_id = null`; (3) delete the agent's timelines; (4) delete the agent. Returns `{timelines_removed, tasks_returned, assignments_cleared}`.

**Acceptance:**
- No task is deleted by an agent delete.
- Backlog order: previously-backlog tasks keep their order; returned tasks follow, ordered by (date, timeline `seq`).
- After delete, no row anywhere references the agent id.
- Cross-account / other-workspace agent id → `notfound`.

### US-PLN-5-05 — List agents

- Returns agents with the resolved model summary `{model_id, model_key, label}` for AI agents; no N+1 (single join/batched lookup).

**Acceptance:** Hidden agents are included (the popover needs them); ordering is stable.

---

## Functional Test Plan

`workflow_tests/planner_5_agents.xs` (timelines/tasks inserted directly with `db.add` for propagation cases — PLN-6/7 endpoints are not required).

| ID | Case | Expected |
|---|---|---|
| FT-PLN-5-01 | Create person agent, AI agent with valid model | Both succeed; defaults applied |
| FT-PLN-5-02 | Person with `model_id`; AI with other account's model | `inputerror`; `notfound` |
| FT-PLN-5-03 | Duplicate name; capacity 0 and 25 | Rejected |
| FT-PLN-5-04 | Rename agent that owns 2 timelines + 4 tasks | Only the agent row changes (`updated_at` of children identical) |
| FT-PLN-5-05 | AI → person | `model_id` cleared |
| FT-PLN-5-06 | Bulk hide, bulk show | All flags flip; counts of other tables unchanged |
| FT-PLN-5-07 | Delete agent with 2 timelines (5 tasks) + 1 task assigned to it elsewhere + 2 existing backlog tasks | 0 tasks deleted; 5 returned to backlog after the 2 originals; override cleared; timelines gone |
| FT-PLN-5-08 | After FT-07, query every planner table for the agent id | Zero hits |
| FT-PLN-5-09 | Delete agent from a different account | `notfound`; nothing changed |
| FT-PLN-5-10 | Unauthenticated call to each endpoint | 401 |

**Completion gate:** all FT cases pass → record results → move to `completed-epics/`.

## Test Results

_Not yet run._
