# PLN-6 — Timelines

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-04):** a published timeline cannot be deleted; only LIVE-1's publish endpoint changes `status`.

**Epic ID:** PLN-6
**Status:** Planning
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

_Not yet run._
