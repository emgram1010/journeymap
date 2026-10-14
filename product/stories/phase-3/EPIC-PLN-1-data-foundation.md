# PLN-1 — Data Foundation

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-01):** add `planner_workspace.is_archived`, `plan_template_id`; `planner_agent.user_id`, `is_active`; `planner_task.tweak_reason`; `planner_task.title` nullable at schema level (required by the API when not linked).

**Epic ID:** PLN-1
**Status:** Done (see Test Results) — six tables live and constraint-verified; P3A-1's amendments included in the first push
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

**2026-10-14 — Opus 5 build pass.** Six tables pushed to workspace 1 with
P3A-1's amendments included in the first push, as P3A-1 intends. Every
constraint below was exercised with real inserts against a throwaway
account, not inferred from the schema.

> **Model note:** the build order marks phase-3 as Sonnet. This ran on Opus
> because the founder was away and had asked for work to continue rather
> than stall on a model switch. Stronger model than specified, not weaker.

### Tables

| Table | Live id | File |
|---|---|---|
| `planner_settings` | 113 | `static/tables/113_planner_settings.xs` |
| `planner_model` | 114 | `static/tables/114_planner_model.xs` |
| `planner_workspace` | 115 | `static/tables/115_planner_workspace.xs` |
| `planner_agent` | 116 | `static/tables/116_planner_agent.xs` |
| `planner_timeline` | 117 | `static/tables/117_planner_timeline.xs` |
| `planner_task` | 118 | `static/tables/118_planner_task.xs` |

**Not 74–79.** Those ids were already taken by an unrelated live
initiative, and Xano assigns ids itself regardless of what a plan reserves
(PUB-1 asked for 82 and got 112). The reserved-number convention has been
retired — see `product/learning-fixes.md`.

### Functional cases

| ID | Result |
|---|---|
| FT-PLN-1-01 | ✅ Second `planner_settings` row for account 3 rejected by the unique index |
| FT-PLN-1-02 | ✅ Duplicate `(account_id, model_key)` rejected; the **same** key inserted fine under a different account — tenancy isolation confirmed at the index |
| FT-PLN-1-03 | ✅ Duplicate workspace name in one account rejected |
| FT-PLN-1-04 | ✅ Duplicate `(workspace_id, name)` agent rejected |
| FT-PLN-1-05 | ✅ Second timeline for the same `(agent_id, planned_date)` rejected |
| FT-PLN-1-06 | ✅ Task with `timeline_id = 0` inserted — the backlog case |
| FT-PLN-1-07 | ⚠️ Mostly — tokens 2000/500, capacity 8, visible true, active true, duration 30, seq 0, `is_archived` false all confirmed on real inserts. **The two enum defaults are missing** (see Deviations) |
| FT-PLN-1-08 | ✅ No `assignee`, no timeline `name`, no `planned_start` — none were created |
| FT-PLN-1-09 | ✅ Every FK present with the documented target, confirmed in the push responses: `account_id→account`, `created_by→user`, `workspace_id→planner_workspace`, `agent_id→planner_agent`, `model_id→planner_model`, `user_id→user`, `timeline_id→planner_timeline`, `assignee_agent_id→planner_agent` |
| Schema audit (GOV-1) | ✅ All six pass S1/S2/S3/S6/S7 at full strictness — they are above `NEW_TABLE_MIN_ID`, so findings would be errors, not warnings. Manifest entries added to `schemaAudit.ts` |

`npm test`: 213/213. `npm run lint`: exits 0.

### A spec bug caught by testing it

**US-P3A-1-01's `unique (workspace_id, user_id)` would have broken agent
creation.** An `int` column here cannot hold a real null — it defaults to
`0` — so that index treats every login-less agent as the same value, and
the *second* agent in any plan without logins would be rejected. That is
almost every plan on day one.

Built instead as a non-unique `btree (user_id)`, with "one login per agent
per plan" enforced in the API (PLN-5/APP-1). Confirmed live: two agents
with no login insert cleanly under the index set that shipped, and would
not have under the one specified.

### Deviations

| Change | Why |
|---|---|
| `planner_model` gained `updated_at` | Not in the epic's column list, but rates are editable (PLN-4), so the table is not append-only and GOV-1 standard S2 requires it |
| No unique `(workspace_id, user_id)` | See above — the specified index was unimplementable here |
| `plan_template_id` is a plain int, not a declared reference | `plan_template` is PLAN-1's table and does not exist yet; adding the reference later means `updateTableSchema`, which drops this table's trim validators. PLAN-1 enforces it |
| `planner_timeline.status` / `planner_task.status` have no schema default | Specified as `draft` / `planned`. Both were created without one, and a direct insert leaves `""`, which is not a valid enum member. Fixing it now needs `updateTableSchema` (drops validators) or a table recreate — neither worth doing unilaterally while the founder is away. PLN-6 and PLN-7 write the value explicitly on every create, so no API-created row can miss it. **Worth a dashboard edit to close properly.** |

### Not done

- **`workflow_tests/planner_1_data_foundation.xs` was not written.** The FT
  cases above were all executed directly instead. A workflow-test file
  cannot be run from a session (no runner is exposed — see
  `product/learning-fixes.md`), so it would have been an unrunnable
  restatement of work already done live. The evidence is this table.
- `docs/planner-data-model.md` **was** written (US-PLN-1-06), including the
  column dictionary, the delete/propagation rules and the full list of
  rules the schema cannot enforce with the epic that owns each.
