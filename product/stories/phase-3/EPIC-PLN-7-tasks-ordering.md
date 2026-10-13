# PLN-7 — Tasks & Ordering

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-05):** changes to tasks on a published timeline are allowed for the planner and logged in `plan_change_log`.

**Epic ID:** PLN-7
**Status:** Planning
**Depends on:** PLN-6
**Goal:** CRUD for tasks across backlog and timelines, with a single resequence function that keeps `seq` gapless and a derived start time that is always correct.

---

## Context

Frontend: `handleCreateBacklogTask`, `handleAddTaskToTimeline`, `handleAddBacklogTaskToAgentDay`, `handlePullToTimeline`, `handleMoveTaskToAgentDayTimeline`, `handleMoveTaskToAgentDay`, `handleReorderTasks`, `handleMoveTaskToBacklog`, `handleDeleteTask`, `handleSaveTaskFromModal`; backlog UI in `BacklogDrawer.tsx`; logic in `utils/planningLogic.ts`.

## Existing Architecture (Do Not Break)

- **Start times are derived, never stored or user-entered:** `start(task) = timeline.start_time + Σ duration of tasks with lower seq`. The API computes this on read; there is no `planned_start` column.
- `seq` within a timeline is `1..n` with no gaps and no duplicates after any mutation. Backlog tasks use `seq` for backlog order.
- A task's effective assignee = `assignee_agent_id` if set, else the timeline's agent, else unassigned (backlog with no override).
- `status` is `planned` or `needs_info` (+ reason). Today `recomputeTimelineTaskTimes` resets tasks to `planned` when they land in a timeline; the API preserves that rule (landing in a timeline clears `needs_info`).

## Non-Goals

- No publishing/readiness enforcement (`getTimelineReadiness` stays a frontend concept until the publishing phase).
- No task dependencies, subtasks, or attachments.

## Endpoints

| Verb | Path | Purpose |
|---|---|---|
| GET | `planner/workspace/{workspace_id}/task` | List (`backlog=true`, `timeline_id`) |
| POST | `planner/workspace/{workspace_id}/task` | Create (backlog, or directly into a timeline) |
| GET | `planner/task/{task_id}` | Read with derived fields |
| PATCH | `planner/task/{task_id}` | Edit title/duration/notes/status/assignee |
| POST | `planner/task/{task_id}/place` | Move into a timeline at an index, or `timeline_id: null` for backlog |
| POST | `planner/timeline/{timeline_id}/reorder` | Reorder with a full id list |
| DELETE | `planner/task/{task_id}` | Delete + resequence |

---

## Stories

### US-PLN-7-01 — Resequence primitive

**File:** `functions/planner/resequence.xs`

- `resequence(timeline_id | workspace backlog)` rewrites `seq` to `1..n` in current order in a single pass. Every mutation below ends by calling it for each affected container (source and destination).

**Acceptance:** After any sequence of operations, `seq` values per container are exactly `1..n`; the function is idempotent.

### US-PLN-7-02 — Create task

- Input: `title` (required, 1–200), `duration_minutes` (int 1–1440, default 30), `notes`, `assignee_agent_id` (optional, same workspace), `timeline_id` (optional → backlog if absent).
- Backlog create appends at the end. Timeline create appends at the end and resequences.

**Acceptance:**
- Task into a timeline of another workspace → `inputerror`.
- Assignee from another workspace → `inputerror`.
- Empty/whitespace title → `inputerror`.

### US-PLN-7-03 — Place / move (`place_task`)

**File:** `functions/planner/place_task.xs`

- `POST …/place {timeline_id|null, index?}`: move between backlog and any timeline in the **same workspace** (including across agents/days), at `index` (clamped to `0..n`; default end). Resequences source and destination; if source = destination it reorders within.
- Landing in a timeline sets `status = planned`, clears `needs_info_reason`. Landing in backlog changes nothing else.
- Does not overwrite `assignee_agent_id`; moving across agents leaves an explicit override in place.

**Acceptance:**
- Move middle task out of a 5-task timeline → source resequenced `1..4`.
- Index beyond end clamps; negative index → `inputerror`.
- Cross-workspace destination → `inputerror`.
- Same-container move produces exactly the requested order.
- (Completes US-PLN-6-06) create-and-place for an empty cell is all-or-nothing.

### US-PLN-7-04 — Reorder

- `POST …/timeline/{id}/reorder {task_ids:[…]}`: must be a permutation of exactly the timeline's current tasks; else `inputerror` and **no** changes.

**Acceptance:** Missing, extra, or duplicate ids → `inputerror`, order unchanged; valid permutation applies atomically.

### US-PLN-7-05 — Edit task

- PATCH `title`, `duration_minutes`, `notes`, `assignee_agent_id` (nullable), `status`, `needs_info_reason`.
- Duration change keeps `seq`; derived starts of later tasks shift on the next read.
- `status = needs_info` requires a non-empty reason.

**Acceptance:**
- Changing the duration of task 2 changes the derived start of tasks 3..n and nothing stored besides task 2.
- Setting `assignee_agent_id = null` returns the task to "inherits the timeline's agent".

### US-PLN-7-06 — Derived fields on every task read

- Each task returns `{…, seq, duration_minutes, planned_start (derived, null for backlog), effective_assignee: {agent_id, name}|null, timeline_id}`.
- Computation is server-side in one function shared by list/read/hydrate (PLN-8) so there is exactly one implementation.
- Times wrap with the same rule as `formatMinutesToTime` (mod 24h).

**Acceptance:** Given start `08:00` and durations 30/45/60 → derived starts `08:00`, `08:30`, `09:15`; a timeline crossing midnight wraps per `formatMinutesToTime`.

### US-PLN-7-07 — Delete task

- Hard delete, then resequence its container.

**Acceptance:** Deleting task 2 of 4 leaves seq `1,2,3`; derived starts recompute; cross-account → `notfound`.

---

## Functional Test Plan

`workflow_tests/planner_7_tasks.xs`

| ID | Case | Expected |
|---|---|---|
| FT-PLN-7-01 | Create 3 backlog tasks | `seq` 1,2,3 |
| FT-PLN-7-02 | Create into timeline | Appended; derived start correct |
| FT-PLN-7-03 | Title empty / duration 0 / duration 1441 | `inputerror` |
| FT-PLN-7-04 | Place backlog task into timeline at index 1 | Inserted; both containers gapless |
| FT-PLN-7-05 | Place with index beyond end / negative | Clamped / `inputerror` |
| FT-PLN-7-06 | Move task between two agents' timelines on different days | Source and destination gapless; override assignee preserved |
| FT-PLN-7-07 | Place into another workspace's timeline | `inputerror` |
| FT-PLN-7-08 | Place a `needs_info` task into a timeline | Becomes `planned`, reason cleared |
| FT-PLN-7-09 | Place task back to backlog | In backlog at end; timeline gapless |
| FT-PLN-7-10 | Reorder with valid permutation | Applied; derived starts follow |
| FT-PLN-7-11 | Reorder with missing/extra/duplicate id | `inputerror`; order unchanged |
| FT-PLN-7-12 | Edit duration of task 2 | Only task 2 row changed; later derived starts shift |
| FT-PLN-7-13 | `needs_info` without reason | `inputerror` |
| FT-PLN-7-14 | Derived starts 30/45/60 from 08:00; midnight wrap | `08:00/08:30/09:15`; wraps correctly |
| FT-PLN-7-15 | Effective assignee: inherit, override, cleared override, backlog | Correct in each case |
| FT-PLN-7-16 | Delete middle task | Resequenced; starts recomputed |
| FT-PLN-7-17 | Run 50 random place/reorder/delete ops, then assert every container is exactly `1..n` | Invariant holds |
| FT-PLN-7-18 | Create-and-place on empty cell with a bad task id | No timeline created |
| FT-PLN-7-19 | Cross-account ids; unauthenticated calls | `notfound`; 401 |

**Completion gate:** all FT cases pass → record results → move to `completed-epics/`.

## Test Results

_Not yet run._
