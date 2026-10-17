# PLN-6 — Timelines

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-04):** a published timeline cannot be deleted; only LIVE-1's publish endpoint changes `status`.

**Epic ID:** PLN-6
**Status:** Partially done — create/list/read/update/move live and verified over real HTTP; **timeline delete (US-PLN-6-05) needs the founder's approval** (see Test Results)
**Depends on:** PLN-5
**Goal:** CRUD for timelines (one agent's plan for one day) enforcing *one agent, one timeline, per day*, with cell moves and a delete that returns tasks to the backlog.

---

## Context

Frontend: `handleStartTimelineForAgentDay`, `handleMoveTimelineCell`, `handleSaveTimelineFromModal`, `handleOpenTimelineEditModal` in `App.tsx`; Schedule grid drag in `ScheduleGrid.tsx`. A timeline has no name or assignee of its own in the backend — both are derived from its agent and date.

## Existing Architecture (Do Not Break)

- `handleMoveTimelineCell` **refuses** a move when the target agent already has a timeline on the target date; it does not swap or merge. The API keeps that rule.
- Task start times cascade from the timeline's `start_time` (`recomputeTimelineTaskTimes`). Changing `start_time` must change every task's *derived* start, with no task rows rewritten.
- Out-of-window dates are allowed to exist (they are flagged in the UI), not rejected.

## Non-Goals

- **Publishing is on hold.** No publish/reopen/bulk-publish. `status` is read-only and always `draft`; any `status` in input is rejected.

## Endpoints

| Verb | Path | Purpose |
|---|---|---|
| GET | `planner/workspace/{workspace_id}/timeline` | List (optional `date_from`, `date_to`, `agent_id`) |
| POST | `planner/workspace/{workspace_id}/timeline` | Create for `(agent_id, planned_date)` |
| GET | `planner/timeline/{timeline_id}` | Read with derived label + task count |
| PATCH | `planner/timeline/{timeline_id}` | Change `start_time`, or move (`agent_id`/`planned_date`) |
| DELETE | `planner/timeline/{timeline_id}` | Delete; tasks return to backlog |

---

## Stories

### US-PLN-6-01 — Create timeline

- Input: `agent_id`, `planned_date` (YYYY-MM-DD), `start_time` (optional, `HH:MM`, default `08:00`).
- Agent must belong to the workspace (`assert_same_workspace`).

**Acceptance:**
- Existing timeline for that agent/date → returns **that timeline** unchanged with `created: false` (mirrors the UI, which opens the existing one) — never a duplicate.
- `start_time` not `HH:MM` 00:00–23:59 → `inputerror`.
- Out-of-window date → created, with `out_of_window: true` in the response.
- `status` supplied → `inputerror`.

### US-PLN-6-02 — Read / list with derived fields

- Each timeline returns `{id, workspace_id, agent_id, agent_name, label, planned_date, start_time, status:"draft", task_count, total_minutes, out_of_window}` where `label = "<Mon D> — <agent_name>"`.

**Acceptance:** Renaming the agent changes `label`/`agent_name` on the next read with no timeline write; `out_of_window` follows the workspace's current window.

### US-PLN-6-03 — Update start time

- PATCH `start_time`. No task rows are written.

**Acceptance:** After changing `08:00 → 09:30`, a hydrated read (PLN-8) shows every task start shifted by 90 minutes; task `updated_at` values unchanged.

### US-PLN-6-04 — Move timeline (agent and/or date)

**File:** `functions/planner/move_timeline.xs`

- PATCH `agent_id` and/or `planned_date`. Target agent must be in the same workspace.
- If another timeline exists for the target `(agent_id, planned_date)` → `inputerror` `"Target agent already has a timeline on that date"`; nothing changes.
- Tasks are not touched (their effective assignee follows the new agent automatically, unless they carry an override — see below).

**Acceptance:**
- Move to a free cell succeeds; to an occupied cell is refused and the original is intact.
- Moving a timeline onto its own current cell is a no-op success.
- Tasks with an explicit `assignee_agent_id` override keep it.

### US-PLN-6-05 — Delete timeline

**File:** `functions/planner/delete_timeline_cascade.xs`

- Uses `return_tasks_to_backlog` (from PLN-5) for the timeline's tasks, then deletes the timeline. Returns `{tasks_returned}`.

**Acceptance:** No task is deleted; returned tasks keep their relative order after the existing backlog; no task references the removed id.

### US-PLN-6-06 — Create-and-place helper (backend side of "drop on empty cell")

- `POST planner/workspace/{workspace_id}/timeline` accepts an optional `place_task_id`: creates (or reuses) the timeline for `(agent_id, planned_date)` and appends that backlog task to it — atomically, via the PLN-7 `place_task` function.

**Acceptance:** Either both happen or neither (invalid task id → no timeline created). *This story is completed after US-PLN-7-03 lands; its tests run in PLN-7's plan.*

---

## Functional Test Plan

`workflow_tests/planner_6_timelines.xs` (task rows inserted with `db.add` where needed).

| ID | Case | Expected |
|---|---|---|
| FT-PLN-6-01 | Create timeline | `draft`, start `08:00`, `created: true` |
| FT-PLN-6-02 | Create again for same agent/date | Same id, `created: false`, row count 1 |
| FT-PLN-6-03 | Agent from another workspace | `inputerror` |
| FT-PLN-6-04 | Bad `start_time` values (`25:00`, `8:5`, empty string) | `inputerror` |
| FT-PLN-6-05 | Supply `status:"published"` on create and PATCH | `inputerror` both |
| FT-PLN-6-06 | Out-of-window date | Created; `out_of_window: true` |
| FT-PLN-6-07 | Rename agent; read timeline | `label`/`agent_name` updated; timeline `updated_at` unchanged |
| FT-PLN-6-08 | PATCH `start_time` | Persisted; no task `updated_at` changes |
| FT-PLN-6-09 | Move to free cell / occupied cell / own cell | success / refused (original intact) / no-op |
| FT-PLN-6-10 | Move preserves task override assignees | Overrides intact |
| FT-PLN-6-11 | Delete timeline with 3 tasks, backlog has 2 | 5 backlog tasks, order = 2 originals then 3 returned; 0 deleted |
| FT-PLN-6-12 | List filters `date_from/date_to/agent_id` | Correct subsets |
| FT-PLN-6-13 | Cross-account ids on every endpoint | `notfound` |
| FT-PLN-6-14 | Unauthenticated call to each endpoint | 401 |

**Completion gate:** all FT cases pass (US-PLN-6-06 deferred cases are tracked under FT-PLN-7) → record results → move to `completed-epics/`.

## Test Results

**2026-10-14 — Opus 5 build pass. Partially complete: everything except
the delete.** Four endpoints live, all exercised over **real
authenticated HTTP**.

### What shipped

| Endpoint | Live id | File |
|---|---|---|
| `POST planner/workspace/{id}/timeline` | 538 | `apis/planner/538_workspace_workspace_id_timeline_POST.xs` |
| `GET planner/workspace/{id}/timeline` | 539 | `apis/planner/539_workspace_workspace_id_timeline_GET.xs` |
| `GET planner/timeline/{id}` | 540 | `apis/planner/540_timeline_timeline_id_GET.xs` |
| `PATCH planner/timeline/{id}` | 541 | `apis/planner/541_timeline_timeline_id_PATCH.xs` |

### 🔴 Not done: the delete needs the founder's approval

`DELETE planner/timeline/{timeline_id}` and
`planner/delete_timeline_cascade` are **written but not pushed** —
fourth and final held delete path. **Blocks FT-PLN-6-11.**

The cascade is only two steps, and **the first is already proven**:
`planner/return_tasks_to_backlog` is pushed and tested (PLN-5), and it
is the part that guarantees no task is lost and the backlog keeps its
order. Only the single `db.del` that follows is unverified.

US-PLN-6-06 (`place_task_id`) is deferred to PLN-7 by the epic itself.

### Functional cases

| ID | Result |
|---|---|
| FT-PLN-6-01 | ✅ Created `draft`, `start_time 08:00`, `created: true` |
| FT-PLN-6-02 | ✅ Same agent + date again → **same id**, `created: false`, no duplicate row |
| FT-PLN-6-03 | ✅ Agent from another plan → *"Entities must belong to the same workspace"* |
| FT-PLN-6-04 | ✅ `25:00`, `8:5`, `""` and `abc` all → `E-PLN-010` |
| FT-PLN-6-05 | ✅ `status: "published"` rejected on **both** create and PATCH → `E-PLN-011` |
| FT-PLN-6-06 | ✅ A date outside the plan's window was created and returned `out_of_window: true` |
| FT-PLN-6-07 | ✅ The agent renamed in PLN-5 shows through: `"Oct 20 — Cascade A Renamed"`, with no timeline row written. The label is derived on read, never stored |
| FT-PLN-6-08 | ✅ `start_time` `09:00 → 09:30` persisted; the timeline's task row came back **byte-identical** (no task rows written) |
| FT-PLN-6-09 | ✅ All three: move to a free cell succeeded; move onto an occupied cell → `E-PLN-012` with the original timeline **intact**; move onto its own cell → no-op `200`, not a duplicate-key error |
| FT-PLN-6-10 | ✅ By construction and confirmed — this endpoint writes **no** task rows, and a task row was byte-identical after two moves of its timeline. (An explicit override value was not set, as no task-write endpoint exists until PLN-7; "no task row is written at all" is the stronger claim) |
| FT-PLN-6-11 | ⛔ Blocked |
| FT-PLN-6-12 | ✅ `date_from`, `date_from`+`date_to`, and `agent_id` each returned the right subset |
| FT-PLN-6-13 | ✅ Cross-account `PATCH timeline/{id}` → `404` |
| FT-PLN-6-14 | ✅ All four endpoints `401` unauthenticated |

Derived counts verified against the database directly: timelines 4 and
5 reported `tasks=1 mins=30`, timeline 3 reported `0` after its tasks
had been returned to the backlog by PLN-5's test — matching the rows
exactly.

`npm test`: 213/213.

### Two more XanoScript traps found, both silent

**1. `task_count` was 0 for every timeline.** The tally loop skipped
unknown keys with `if ($cur != null)`. **A `conditional` inside a
`foreach` whose condition reads a variable updated earlier in the same
iteration silently discards everything the branch writes.** Isolated
with three side-by-side tallies over identical data:

| condition reads | result |
|---|---|
| the loop item (`$r.flag`) | ✅ correct |
| a constant (`true`) | ✅ correct |
| a var updated earlier in that iteration (`$cur != null`) | ❌ all writes lost, no error |

That is why `ops/group_issues.xs` and PLN-3's list work — their
conditions read the loop item. Fixed by scoping the task query with
`timeline_id in $tl_ids`, so every key is seeded and no `if` is needed
at all.

**2. An omitted optional `date` input does not exist.** Unlike `text`
and `int` (which arrive as `""` and `0`), referencing an absent
optional `date` throws `"Unable to locate input: date_from"` at
runtime. And on a **GET** there is no JSON body, so
`util.get_raw_input|has:` cannot detect it either. The date filters are
declared `text` and widened to sentinel bounds when absent.

Both are now in `CLAUDE.md`.

### Deviations

| Change | Why |
|---|---|
| `date_from` / `date_to` are `text`, not `date` | See trap #2 above — a `date` filter on a GET cannot be made optional |
| Create also runs `assert_same_workspace` | US-PLN-6-01 requires the agent to be in the workspace; `assert_agent` only proves the account, so the plan-level check is explicit |
| Timeline writes are blocked on an archived plan | Not in PLN-6, but P3A-1 makes an archived plan read-only |
| `label` uses `"M j"` (e.g. `Oct 20`) | US-PLN-6-02 says `"<Mon D> — <agent_name>"`; this is that format |
