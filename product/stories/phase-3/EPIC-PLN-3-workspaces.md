# PLN-3 — Workspaces

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-02):** delete cascades only when the plan has no jobs, publications or log events; otherwise it must be archived.

**Epic ID:** PLN-3
**Status:** Partially done — read/create/update/archive live and verified over real HTTP; **the delete path needs the founder's approval** (see Test Results)
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

**2026-10-14 — Opus 5 build pass. Partially complete: everything except
the delete path.** Five endpoints are live and were exercised over **real
authenticated HTTP**, not `runWorkspaceFunction`.

### What shipped

| Endpoint | Live id | File |
|---|---|---|
| `POST planner/workspace` | 523 | `apis/planner/523_workspace_POST.xs` |
| `GET planner/workspace` | 524 | `apis/planner/524_workspace_GET.xs` |
| `GET planner/workspace/{id}` | 525 | `apis/planner/525_workspace_workspace_id_GET.xs` |
| `PATCH planner/workspace/{id}` | 526 | `apis/planner/526_workspace_workspace_id_PATCH.xs` |
| `POST planner/workspace/{id}/archive` | 527 | `apis/planner/527_workspace_workspace_id_archive_POST.xs` |
| `planner/workspace_counts` | fn 107 | `functions/planner/workspace_counts.xs` |
| `planner/workspace_has_history` | fn 106 | `functions/planner/workspace_has_history.xs` |

### 🔴 Not done: the delete path needs the founder's approval

`DELETE planner/workspace/{workspace_id}` and
`planner/delete_workspace_cascade` were **written but not pushed**. The
cascade is in `functions/planner/delete_workspace_cascade.xs` for review.

Two reasons, pointing the same way:

1. CLAUDE.md requires asking before any delete, and this is the planner's
   first destructive path.
2. The push was independently refused by the session's permission layer
   as a shared-resource modification.

**This blocks FT-PLN-3-07, FT-PLN-3-08 and FT-PLN-3-09**, and
US-PLN-3-04/05. Everything needed to finish them is ready: a throwaway
fixture is already seeded (below), so once approved this is one push and
one test run.

**One thing genuinely unknown**, flagged in the file: whether `db.del`
with `field_name`/`field_value` deletes *every* matching row or only the
first. CLAUDE.md only documents the single-record case. If it deletes
one, each child delete becomes a loop. This must be tested on the
throwaway plan before the cascade is trusted.

### Fixtures used

Account **6** (user 9, admin). A throwaway plan **ws 4** was seeded to
match FT-PLN-3-07 exactly — 2 agents, 3 timelines, 6 tasks of which 2 are
backlog — plus sibling plan **ws 5** (1/1/2/1) that must survive the
cascade. Plans 6, 7, 8 were created through the API during testing.

### Functional cases

| ID | Result |
|---|---|
| FT-PLN-3-01 | ✅ Create with only a name → window `2026-10-14 … 2026-10-27` (today → +13), rates 2000/500, `is_archived` false. `account_id`/`created_by` taken from the actor |
| FT-PLN-3-02 | ✅ `account_id: 3` and `created_by: 2` sent in the body were ignored — the row came back `account_id 6, created_by 9`. They are not declared as inputs at all |
| FT-PLN-3-03 | ✅ Duplicate name rejected; **whitespace-padded** duplicate (`"   Defaults Check   "`) also rejected, via the input's `trim` filter |
| FT-PLN-3-04 | ✅ `end < start` rejected on create. **And on a one-field PATCH**: sending only `planning_window_start: 2026-12-01` against a stored end of `2026-10-27` was rejected — the merged-value check works |
| FT-PLN-3-05 | ✅ List returned ws5 then ws4 (newest first) with counts `1/1/2/1` and `2/3/6/2`, exactly matching the seeded fixture. Another account's plans absent; cross-account read → `Plan not found` |
| FT-PLN-3-06 | ✅ Shrank ws4's window to `2026-10-14 … 2026-10-15`, well inside its timelines (20th, 21st) → 200, and `timeline_count` stayed 3. Moving a window destroys nothing |
| FT-PLN-3-07 | ⛔ Blocked — see above |
| FT-PLN-3-08 | ⛔ Blocked — but the read/update half is proven: cross-account `GET` and `PATCH` both return `Plan not found`, byte-identical to a nonexistent id |
| FT-PLN-3-09 | ⛔ Blocked |
| FT-PLN-3-10 | ✅ Unauthenticated call to **all five** endpoints → `401 ERROR_CODE_UNAUTHORIZED`. This is also the first real evidence for US-PLN-2-05's standing auth test |

### Beyond the plan

| Case | Result |
|---|---|
| Archive lifecycle (P3A-1) | ✅ Archive → hidden from the default list, still present under `?include_archived=true`, still readable by id. Restore → back in the list |
| Archived plan is read-only | ✅ `PATCH` on an archived plan → *"This has been archived, so it can't be changed. (E-GOV-004)"* — from the existing GOV-1 guard, reused rather than reimplemented |
| Rename to its own current name | ✅ Allowed (the clash check excludes the row being renamed) |
| Partial PATCH leaves other fields alone | ✅ Sending only a rate left name and both dates untouched |
| Blank name / 81-char name / negative rate | ✅ `E-VAL-001` / `E-VAL-002` / `E-PLN-003`, all with friendly sentences |
| OBS-1 events | ✅ `event_log` holds `PLN-3.create_workspace` and `PLN-3.update_workspace` rows, success and rejected, each carrying its error code |

`npm test`: 213/213. `npm run lint`: exits 0.

### Two bugs found and fixed during the build

**1. Every count came back `null`.** `|get` with a **variable** key
silently ignores its default argument on a miss: `{}|get:$k:0` returns
`null`, while `{}|get:"k":0` returns `0`. Isolated with a live probe
across seven variants. The list endpoint now pre-seeds every plan's key
to `0`, so no lookup ever misses and the broken default is never relied
on. Logged in `product/learning-fixes.md` and `CLAUDE.md`.

**2. Two of the five rejections were silent.** Only the duplicate-name
case logged an event; the date and rate refusals threw with no
`event_log` row, breaking OBS-1's "never fail silently" rule. Both write
endpoints were restructured so every check sets a reject code and a
single block logs and raises it — one log path, impossible to forget.
Confirmed afterwards: `E-PLN-003` rejections now appear in `event_log`
for both create and update. **The whole suite was then re-run from
scratch**, since the restructure invalidated the earlier passes.

### Resolves an open question from PLN-2

PLN-2 flagged that `inputerror` seemed to prefix its message with
`"Param:  - "`, which would have violated VAL-1 across five existing
guards. **It does not.** Over real HTTP every message came back clean —
*"You already have a plan with this name. (E-PLN-001)"*. The prefix is an
artefact of `runWorkspaceFunction`, exactly like the `accessdenied` case
PUB-1 hit. No fix needed, and the PLN-2 note is now closed.

### Deviations

| Change | Why |
|---|---|
| Added `POST workspace/{id}/archive`, not in PLN-3's endpoint table | P3A-1 (US-P3A-1-02) requires archive as the alternative to deleting a plan with history. Without it the amendment has no way to be used. Takes an `is_archived` boolean so restoring is possible — a one-way archive would just be a second kind of delete |
| PLN-3's Non-Goals say "no archiving (hard delete only)" | Directly overridden by P3A-1, which amends this epic. Noted because the epic text still reads the old way |
| List counts are tallied in memory from 4 queries, not 4 queries per plan | US-PLN-3-02 forbids per-row loops. `planner/workspace_counts` (the single-plan version) is used only by read and update, where there is exactly one plan |
| `planner/workspace_has_history` always returns "no history" | Its three source tables (`work_item`, `plan_publication`, `activity_log`) belong to JOB-1, LIVE-1 and LOG-1 and do not exist yet, so "no" is currently the true answer. It exists now so the call site is already right; each later epic fills in its own count |
