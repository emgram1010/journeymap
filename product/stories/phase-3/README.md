# Phase 3 — Planner Backend

> **Amended by `product/stories/phase-4/EPIC-P3A-1-planner-amendments.md`** (2026-10-12): plans, agents and timelines with recorded work are archived/deactivated, not deleted, and extra columns are added in the first push. Read it before building PLN-1, 3, 5, 6, 7, 8.

**Status:** Planning
**Goal:** Replace the planner's `localStorage` persistence with a normalized, account-scoped Xano backend (tables, APIs, functions) so the Planner (`webapp/planningFrontendv2`, mounted in `webapp/protype-2` at `/planner`) reads and writes real data with correct CRUD propagation.

**Explicitly out of scope (on hold): publishing.** No publish / reopen / bulk-publish endpoints, no execution hand-off, no publish UI wiring. The `status` column is created now (`draft` only) so publishing needs no later migration — see [Reserved for publishing](#reserved-for-publishing).

---

## Epics (build in this order)

| # | Epic | Depends on | Delivers |
|---|---|---|---|
| 1 | [PLN-1 Data Foundation](EPIC-PLN-1-data-foundation.md) | — | 6 normalized tables, PKs, FKs, indexes, enums, ER doc |
| 2 | [PLN-2 Tenancy & Access Control](EPIC-PLN-2-tenancy-access-control.md) | 1 | Account scoping + shared guard functions used by every endpoint |
| 3 | [PLN-3 Workspaces](EPIC-PLN-3-workspaces.md) | 1, 2 | Workspace CRUD, cascade delete |
| 4 | [PLN-4 Settings & Model Catalog](EPIC-PLN-4-settings-model-catalog.md) | 1, 2 | Account rates + model pricing CRUD |
| 5 | [PLN-5 Agents](EPIC-PLN-5-agents.md) | 3, 4 | Agent CRUD, visibility, delete propagation |
| 6 | [PLN-6 Timelines](EPIC-PLN-6-timelines.md) | 5 | Timeline CRUD, one-per-agent-per-day, cell move |
| 7 | [PLN-7 Tasks & Ordering](EPIC-PLN-7-tasks-ordering.md) | 6 | Task CRUD, backlog, reorder, derived start times |
| 8 | [PLN-8 Integrity & Hydrated Read](EPIC-PLN-8-integrity-hydrated-read.md) | 3–7 | Cross-entity propagation tests, orphan audit, one-call board load |
| 9 | [PLN-9 Frontend Integration](EPIC-PLN-9-frontend-integration.md) | 8 | API client, replace localStorage, one-time import |

## Data model

```
account 1──1 planner_settings
account 1──N planner_model
account 1──N planner_workspace ──┬─N planner_agent ──┬─N planner_timeline ──N planner_task
                                 │        │          │                          ▲  ▲
                                 │        └─ model_id → planner_model           │  │
                                 ├─N planner_timeline (workspace_id)  ──────────┘  │
                                 └─N planner_task     (workspace_id)               │
                                 planner_agent 1──N planner_task (assignee_agent_id, optional override)
```

| Table | PK | Foreign keys | Natural uniqueness |
|---|---|---|---|
| `planner_settings` | `id` | `account_id → account` | one row per account |
| `planner_model` | `id` | `account_id → account` | `(account_id, model_key)` |
| `planner_workspace` | `id` | `account_id → account`, `created_by → user` | `(account_id, name)` |
| `planner_agent` | `id` | `workspace_id → planner_workspace`, `model_id → planner_model` (AI only) | `(workspace_id, name)` |
| `planner_timeline` | `id` | `workspace_id → planner_workspace`, `agent_id → planner_agent` | `(agent_id, planned_date)` — one agent, one timeline, per day |
| `planner_task` | `id` | `workspace_id → planner_workspace`, `timeline_id → planner_timeline` (null = backlog), `assignee_agent_id → planner_agent` (null = inherit) | — |

Table names are prefixed `planner_` because `agent_*` tables already exist for the AI chat feature (`agent_conversation`, `agent_message`, …).

## Normalization decisions (what changes vs. today's frontend types)

| Today (`types.ts`) | Backend | Why |
|---|---|---|
| `Timeline.assignee` (name string, rewritten on agent rename) | **dropped** — derived from `agent.name` | Removes a copy that must be hand-synced |
| `Timeline.name` (generated `"Oct 13 — Marcus"`) | **dropped** — derived label | Pure function of date + agent |
| `Task.assignee` (name string, copied on every move) | `assignee_agent_id` FK, nullable override | Rename propagates for free; null means "inherit the timeline's agent" |
| `Task.planned_start` | **dropped** — computed on read | Already derived by `recomputeTimelineTaskTimes` (timeline `start_time` + cumulative duration of lower `seq`); storing it creates drift |
| `AppSettings.models[]` (embedded array) | `planner_model` rows | Agents reference a model by FK instead of a loose string |
| `Agent.modelId` (string) | `model_id` FK | Referential check; delete-guard |
| Costs, load, capacity | **never stored** | Computed from settings + durations |
| `Task.workspaceId` | kept | Backlog tasks have no timeline, so they need their own scope; consistency with the timeline's workspace is enforced in the API |

## Conventions

- **Tables:** `static/tables/74_…` onward (highest existing is 73). One file per table, schema + indexes, matching `static/tables/13_journey_architecture.xs` style.
- **APIs:** new api group `planner`; files under `apis/planner/`, numbered from 214 (highest existing is 213). Every endpoint `auth = "user"`.
- **Functions:** shared logic in `functions/planner/` (guards, resequence, cascade). Endpoints stay thin.
- **Functional tests:** Xano `workflow_test`s in `workflow_tests/planner_<epic>.xs`, same style as `workflow_tests/4_journey_map_cell_identifiers.xs`.
- **Referential integrity:** Xano table references are typed but do **not** enforce referential actions. Every delete rule is implemented in shared functions and verified by PLN-8's orphan audit.
- **Errors:** `notfound` (missing or cross-account — never leak existence), `accessdenied` (role), `inputerror` (validation), `conflict` semantics via `inputerror` with a stable message prefix when a business rule blocks the call.

## Delete / propagation rules (single source of truth)

| Action | Effect |
|---|---|
| Delete workspace | Hard-delete its tasks → timelines → agents (in that order) |
| Delete agent | Hard-delete its timelines; their tasks return to the backlog; tasks that named it as `assignee_agent_id` get `null` |
| Delete timeline | Its tasks return to the backlog (end of backlog order) |
| Delete task | Hard delete; remaining tasks in its timeline are resequenced `1..n` |
| Delete model | Blocked while any agent references it |
| Rename agent | No writes elsewhere — names are derived |
| Move timeline (agent/date) | Refused if the target agent already has a timeline that day; no task writes needed (assignee is derived) |
| Change agent `kind` to `person` | `model_id` cleared |

## Reserved for publishing

`planner_timeline.status` is `enum ["draft","published"]`, default `draft`. In Phase 3 the API **never accepts** `status` on write and always returns `draft`. Publishing (publish, reopen, bulk publish, readiness checks, hand-off) is a later phase; the frontend's Publish controls remain local-only until then.

## Epic completion workflow

1. All stories in the epic are done and merged.
2. Run the epic's **Functional Test Plan** (Xano workflow tests + the listed manual checks). Record the result in the epic file under `## Test Results` (date, pass/fail per case, run by).
3. Only when every case passes: set `**Status:** Complete` and **move the file to [`completed-epics/`](completed-epics/)**.
4. A failing case blocks the move; fix, re-run, re-record.
5. The next epic does not start until its dependencies are in `completed-epics/`.
