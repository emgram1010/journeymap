# PLN-5 — Agents

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-03):** an agent with a published timeline or log events is deactivated, not deleted.

**Epic ID:** PLN-5
**Status:** Partially done — list/create/update/visibility live and verified over real HTTP; **agent delete (US-PLN-5-04) needs the founder's approval** (see Test Results)
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

**2026-10-14 — Opus 5 build pass. Partially complete: everything except
the delete cascade.** Four endpoints live, all exercised over **real
authenticated HTTP**.

### What shipped

| Endpoint | Live id | File |
|---|---|---|
| `GET planner/workspace/{id}/agent` | 534 | `apis/planner/534_workspace_workspace_id_agent_GET.xs` |
| `POST planner/workspace/{id}/agent` | 535 | `apis/planner/535_workspace_workspace_id_agent_POST.xs` |
| `PATCH planner/agent/{id}` | 536 | `apis/planner/536_agent_agent_id_PATCH.xs` |
| `POST planner/workspace/{id}/agent/visibility` | 537 | `apis/planner/537_workspace_workspace_id_agent_visibility_POST.xs` |
| `planner/return_tasks_to_backlog` | fn 114 | `functions/planner/return_tasks_to_backlog.xs` |

### 🔴 Not done: the delete cascade needs the founder's approval

`DELETE planner/agent/{agent_id}` and `planner/delete_agent_cascade`
are **written but not pushed** — third delete path held for the same
reason. The cascade is in `functions/planner/delete_agent_cascade.xs`.

**This blocks FT-PLN-5-07, -08 and -09.**

**But the hard half of FT-PLN-5-07 is already proven.** The risky part
of an agent delete is not the deleting, it is keeping the work and its
order — and that lives in `planner/return_tasks_to_backlog`, which is
a pure move, contains no delete, and **was pushed and verified**:

> ws4's backlog held `Cascade backlog 1` (seq 0) and `Cascade backlog 2`
> (seq 1). Returning timeline 3's two tasks produced seq **2** and **3**
> in their original timeline order, with the two existing backlog tasks
> untouched at 0 and 1, and all six tasks still present. That is
> US-PLN-5-04's backlog-order acceptance criterion exactly.

### Functional cases

| ID | Result |
|---|---|
| FT-PLN-5-01 | ✅ Person and AI agent both created. Defaults applied: capacity 8, `is_visible true`, `is_active true`, auto colour |
| FT-PLN-5-02 | ✅ Person with a `model_id` → `E-PLN-008`; AI with another account's model → `404 Model not found` (not "forbidden" — the model's existence is not revealed) |
| FT-PLN-5-03 | ✅ Duplicate name → `E-PLN-007`; capacity `0` and `25` both → `E-PLN-009` |
| FT-PLN-5-04 | ✅ Renamed an agent owning 2 timelines. Its three timeline rows came back **byte-identical** to a snapshot taken beforehand — same ids, timestamps, dates, start times, statuses. Only the agent row was written |
| FT-PLN-5-05 | ✅ AI → person cleared `model_id` to 0 in the same write. Person → AI without a model is allowed, as the story requires |
| FT-PLN-5-06 | ✅ Hide-all flipped all 6 agents, show-all restored all 6, and the plan's counts (agents/timelines/tasks/backlog) were unchanged throughout |
| FT-PLN-5-07 | ⛔ Blocked — but see the backlog-order evidence above |
| FT-PLN-5-08 | ⛔ Blocked |
| FT-PLN-5-09 | ⛔ Blocked — the read/update half is proven: a cross-account `PATCH agent/{id}` returns `404 Agent not found` |
| FT-PLN-5-10 | ✅ All four endpoints return `401` unauthenticated |

### Beyond the plan

| Case | Result |
|---|---|
| US-PLN-5-05 model summary, no N+1 | ✅ One query for all models, indexed in memory. An AI agent with a model resolved to `claude-sonnet-5 (Claude Sonnet 5)`; agents without one returned `null` |
| Hidden agents are listed | ✅ Included by design — the popover is where you un-hide, so filtering them out would make hiding one-way |
| Auto colour walks the palette | ✅ Four consecutive creates took `#475569`, `#0d9488`, `#c2410c`, `#b45309` in order |
| An explicit colour overrides | ✅ `#abcdef` kept |
| Rename to its own name | ✅ Allowed |
| Archived plan blocks agent writes | ✅ Create, update and bulk visibility all go through `guards/assert_not_archived` |

`npm test`: 213/213 — including the catalog lint, which required
`E-PLN-007/008/009` to be cataloged.

### Two live bugs found and fixed during the build

**1. Every new agent got the same colour.** The "is this palette colour
already used?" test was `($used|contains:$p) == false`. **`|contains:`
returns `false` for every array** — present or absent, literal or
variable (isolated across four combinations live). So the test was
always true and the first palette entry always won. Replaced with a
nested loop.

**2. "Hide all" hid exactly one agent out of six — and reported
success.** `db.patch` with `field_name`/`field_value` updates only the
**first** matching row; there is no "patch where" form. Replaced with a
read-then-loop, patching each agent by id inside one `db.transaction`.

### ⚠️ What finding #2 means for the delete paths

`db.del` takes the same `field_name`/`field_value` form, so it almost
certainly deletes one row too. **PLN-3's cascade was written on the
opposite assumption** — one `db.del` per child table by `workspace_id`.
Had it been pushed, deleting a plan would have removed one task, one
timeline, one agent and then the plan itself, **orphaning every
remaining child against a plan that no longer existed** — exactly the
corruption GOV-1's integrity audit exists to catch, caused by the
cleanup meant to prevent it.

`functions/planner/delete_workspace_cascade.xs` has been rewritten to
read each child set and delete by id. This is the clearest argument yet
for the delete paths having been held rather than pushed.

### Deviations

| Change | Why |
|---|---|
| `return_tasks_to_backlog` takes `(workspace_id, timeline_id)`, not a `task_filter` | US-PLN-5-04 describes a filter, but a filter cannot be passed into a Xano function. Every caller (PLN-5 delete, PLN-6 delete, PLN-7 unschedule) works a timeline at a time anyway |
| It was pushed and tested even though its only current caller is unpushed | It contains no delete, so it needed no approval — and it holds the part of the cascade most likely to be wrong. Testing it now means that when the delete is approved, only the deleting itself is unverified |
| Three new error codes | `E-PLN-007` (duplicate agent name), `E-PLN-008` (model on a person), `E-PLN-009` (capacity out of range). The epic specifies the behaviours but names no codes |
| Agent writes are blocked on an archived plan | Not in PLN-5, but P3A-1 makes an archived plan read-only and this is a write to its contents |
