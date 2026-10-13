# PLN-1 — Data Foundation

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-01):** add `planner_workspace.is_archived`, `plan_template_id`; `planner_agent.user_id`, `is_active`; `planner_task.tweak_reason`; `planner_task.title` nullable at schema level (required by the API when not linked).

**Epic ID:** PLN-1
**Status:** Planning
**Depends on:** —
**Goal:** Six normalized Xano tables with explicit primary keys, foreign keys, enums, defaults and indexes, so every later epic builds on a schema that needs no rework.

---

## Context

The planner stores everything in `localStorage` (`webapp/planningFrontendv2/src/data/initialData.ts::loadStoredData`). Its types carry denormalized copies (assignee names on timelines and tasks, a stored `planned_start`, a generated timeline name, an embedded model list). See the README's *Normalization decisions* table — this epic implements that table.

## Existing Architecture (Do Not Break)

- `static/tables/2_account.xs`, `1_user.xs` — tenancy roots; every planner table scopes to `account`.
- Existing `agent_*` tables (AI chat) — no name collisions: all new tables are `planner_`-prefixed.
- Table style reference: `static/tables/13_journey_architecture.xs`.

## Non-Goals

- No endpoints (PLN-2…7).
- No publishing columns beyond the reserved `status`.
- No link to journey-map actors (possible future FK; not now).

---

## Stories

### US-PLN-1-01 — `planner_settings` and `planner_model`

**Files:** `static/tables/74_planner_settings.xs`, `75_planner_model.xs`

- `planner_settings`: `id`, `created_at`, `updated_at`, `account_id → account` (required), `currency_symbol` text default `"$"`, `human_hourly_rate` decimal default `0`.
- `planner_model`: `id`, `created_at`, `account_id → account` (required), `model_key` text, `label` text, `input_per_1m` decimal, `output_per_1m` decimal, `is_custom` bool default false.
- Indexes: unique `planner_settings(account_id)`; unique `planner_model(account_id, model_key)`; btree `planner_model(account_id)`.

**Acceptance:**
- Second settings row for the same account is rejected by the unique index.
- Duplicate `model_key` within an account rejected; same key in another account allowed.
- Rates are non-negative (enforced in API, PLN-4; schema uses decimal).

### US-PLN-1-02 — `planner_workspace`

**File:** `static/tables/76_planner_workspace.xs`

- `id`, `created_at`, `updated_at`, `account_id → account` (required), `created_by → user` (required), `name` text (required, trimmed), `planning_window_start` date, `planning_window_end` date, `input_tokens_per_minute` int default 2000, `output_tokens_per_minute` int default 500.
- Indexes: unique `(account_id, name)`; btree `(account_id, created_at desc)`.

**Acceptance:**
- Defaults match `DEFAULT_INPUT_TOKENS_PER_MINUTE` / `DEFAULT_OUTPUT_TOKENS_PER_MINUTE` in `initialData.ts`.
- `planning_window_end >= planning_window_start` documented as an API-enforced rule (PLN-3).

### US-PLN-1-03 — `planner_agent`

**File:** `static/tables/77_planner_agent.xs`

- `id`, `created_at`, `updated_at`, `workspace_id → planner_workspace` (required), `name` (required), `kind` enum `["person","ai"]` (required), `color` text (hex), `daily_capacity_hours` decimal default 8, `is_visible` bool default true, `model_id → planner_model` (nullable; AI only).
- Indexes: unique `(workspace_id, name)`; btree `(workspace_id, is_visible)`; btree `(model_id)` for the delete guard.

**Acceptance:**
- `model_id` is nullable; the "AI only" rule is API-enforced (PLN-5) and documented in the file header comment.

### US-PLN-1-04 — `planner_timeline`

**File:** `static/tables/78_planner_timeline.xs`

- `id`, `created_at`, `updated_at`, `workspace_id → planner_workspace` (required), `agent_id → planner_agent` (required), `planned_date` date (required), `start_time` text `"HH:MM"` default `"08:00"`, `status` enum `["draft","published"]` default `draft` (**reserved**, see README).
- Indexes: **unique `(agent_id, planned_date)`** (one agent, one timeline, per day); btree `(workspace_id, planned_date)`.

**Acceptance:**
- No `assignee` or `name` column (derived).
- Unique index rejects a second timeline for the same agent and date.

### US-PLN-1-05 — `planner_task`

**File:** `static/tables/79_planner_task.xs`

- `id`, `created_at`, `updated_at`, `workspace_id → planner_workspace` (required), `timeline_id → planner_timeline` (nullable; null = backlog), `assignee_agent_id → planner_agent` (nullable override), `title` (required), `seq` int default 0 (position within timeline, or backlog order), `duration_minutes` int default 30, `notes` text, `status` enum `["planned","needs_info"]` default `planned`, `needs_info_reason` text.
- Indexes: btree `(timeline_id, seq)` (non-unique — reorders rewrite several rows; uniqueness is guaranteed by the resequence function, PLN-7); btree `(workspace_id, timeline_id)`; btree `(assignee_agent_id)`.

**Acceptance:**
- No `planned_start` column.
- `duration_minutes` > 0 documented as API-enforced.

### US-PLN-1-06 — Schema documentation and constraint matrix

**File:** `docs/planner-data-model.md` (or the repo's existing docs location)

- ER diagram (copy of the README's), column dictionary, the delete/propagation table, and a list of every rule the schema **cannot** enforce (and the function/epic that does).

**Acceptance:**
- Every FK in the six tables appears in the doc with its delete behavior.
- Each API-enforced rule names the owning epic.

### US-PLN-1-07 — Seed policy

- No automatic seeding of workspaces. First `GET planner/settings` (PLN-4) lazily creates the settings row and seeds the four default models from `DEFAULT_MODELS`.
- Demo data (`INITIAL_*` in `initialData.ts`) stays frontend-only, used by the one-time import preview (PLN-9).

**Acceptance:** Documented in the data-model doc; no seed script ships in this epic.

---

## Functional Test Plan

Run as `workflow_tests/planner_1_data_foundation.xs` (direct `db.*` operations against a throwaway account).

| ID | Case | Expected |
|---|---|---|
| FT-PLN-1-01 | Insert two `planner_settings` rows for one account | Second rejected |
| FT-PLN-1-02 | Insert duplicate `(account_id, model_key)` | Rejected; same key in a second account succeeds |
| FT-PLN-1-03 | Insert duplicate workspace name in one account | Rejected |
| FT-PLN-1-04 | Insert duplicate `(workspace_id, name)` agent | Rejected |
| FT-PLN-1-05 | Insert two timelines for the same `(agent_id, planned_date)` | Second rejected |
| FT-PLN-1-06 | Insert task with `timeline_id = null` | Succeeds; appears as backlog |
| FT-PLN-1-07 | Defaults: new workspace/agent/timeline/task | Match the documented defaults (tokens 2000/500, capacity 8, visible true, start `08:00`, status `draft`/`planned`, duration 30) |
| FT-PLN-1-08 | Schema review: no `assignee`, `name` (timeline), or `planned_start` columns exist | Confirmed |
| FT-PLN-1-09 | Every FK listed in the README exists with the documented target table | Confirmed by reading pushed schema |

**Completion gate:** all FT cases pass → record under `## Test Results` → move to `completed-epics/`.

## Test Results

_Not yet run._
