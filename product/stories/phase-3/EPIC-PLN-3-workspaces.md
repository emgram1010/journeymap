# PLN-3 — Workspaces

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-02):** delete cascades only when the plan has no jobs, publications or log events; otherwise it must be archived.

**Epic ID:** PLN-3
**Status:** Planning
**Depends on:** PLN-1, PLN-2
**Goal:** Full CRUD for planner workspaces, including the planning window and AI throughput assumptions, with a correct cascade delete.

---

## Context

Frontend handlers: `handleCreateWorkspace`, `handleRenameWorkspace`, `handleDeleteWorkspace`, `handleUpdateWorkspaceSettings` in `webapp/planningFrontendv2/src/App.tsx`; UI in `Header.tsx` and `WorkspaceSettingsModal.tsx`. Today delete removes agents, timelines and tasks of that workspace.

## Existing Architecture (Do Not Break)

- Planning window rule used by the UI: dates outside `[start, end]` are flagged out-of-window (`isDateOutOfWindow`). Moving the window must **not** delete or move anything.

## Non-Goals

- No sharing, duplication/templates, or archiving (hard delete only, matching today's behavior).

## Endpoints

| Verb | Path | Purpose |
|---|---|---|
| GET | `planner/workspace` | List the account's workspaces |
| POST | `planner/workspace` | Create |
| GET | `planner/workspace/{workspace_id}` | Read one |
| PATCH | `planner/workspace/{workspace_id}` | Rename, planning window, throughput |
| DELETE | `planner/workspace/{workspace_id}` | Cascade delete |

---

## Stories

### US-PLN-3-01 — Create workspace

- Input: `name` (required, trimmed, 1–80 chars), `planning_window_start`, `planning_window_end` (optional; default = today → today+13), `input_tokens_per_minute`, `output_tokens_per_minute` (optional; defaults 2000 / 500).
- Sets `account_id` and `created_by` from the actor, never from input.

**Acceptance:**
- Duplicate name in the account → `inputerror` `"A workspace with this name already exists"`.
- `end < start` → `inputerror`.
- Token rates must be integers ≥ 0.

### US-PLN-3-02 — List and read

- List returns only the actor's account, newest first, with counts `{agent_count, timeline_count, task_count, backlog_count}` computed by aggregate queries (no per-row loops).
- Read returns one workspace with the same counts.

**Acceptance:** Cross-account id on read → `notfound`; list never includes another account's rows.

### US-PLN-3-03 — Update workspace

- PATCH accepts any subset of `name`, `planning_window_start`, `planning_window_end`, `input_tokens_per_minute`, `output_tokens_per_minute`; `util.get_all_input` pattern as in `134_account_me_PATCH.xs`.
- Validation re-runs against the **merged** result (e.g. changing only `start` must still be ≤ stored `end`).

**Acceptance:**
- Shrinking the window leaves existing timelines untouched (they become out-of-window in the UI).
- Rename to an existing name → `inputerror`; rename to its own current name → OK.
- `updated_at` bumps on every successful PATCH.

### US-PLN-3-04 — Delete workspace (cascade)

**File:** `functions/planner/delete_workspace_cascade.xs`

- Order: tasks → timelines → agents → workspace. Returns counts removed per table.

**Acceptance:**
- After delete, zero rows reference the workspace in any planner table.
- Another workspace in the same account is untouched.
- Cross-account id → `notfound`, nothing deleted.

### US-PLN-3-05 — Last-workspace behavior

- Deleting the final workspace is allowed; the API returns an empty list afterwards and the frontend shows the empty state (PLN-9).

**Acceptance:** `GET planner/workspace` returns `[]` for an account with none; no error.

---

## Functional Test Plan

`workflow_tests/planner_3_workspaces.xs`

| ID | Case | Expected |
|---|---|---|
| FT-PLN-3-01 | Create with only a name | Defaults applied; `account_id`/`created_by` from actor |
| FT-PLN-3-02 | Create with `account_id` in input | Ignored |
| FT-PLN-3-03 | Duplicate name; whitespace-padded duplicate | Both rejected |
| FT-PLN-3-04 | `end < start` on create and on PATCH of one field | Rejected both times |
| FT-PLN-3-05 | List shows counts; other account's workspace absent | Correct |
| FT-PLN-3-06 | PATCH window smaller than existing timelines | 200; timelines unchanged |
| FT-PLN-3-07 | Delete workspace with 2 agents, 3 timelines, 6 tasks (2 backlog) | All 11+ rows gone; sibling workspace intact |
| FT-PLN-3-08 | Delete as other account | `notfound`; data intact |
| FT-PLN-3-09 | Delete last workspace, then list | `[]` |
| FT-PLN-3-10 | Unauthenticated call to each endpoint | 401 |

**Completion gate:** all FT cases pass → record results → move to `completed-epics/`.

## Test Results

_Not yet run._
