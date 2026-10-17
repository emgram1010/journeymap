# PLN-7 — Tasks & Ordering

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-05):** changes to tasks on a published timeline are allowed for the planner and logged in `plan_change_log`.

**Epic ID:** PLN-7
**Status:** Partially done — create/list/read/edit/place/reorder live and verified over real HTTP, including the 50-operation ordering invariant; **task delete (US-PLN-7-07) needs the founder's approval** (see Test Results)
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

**2026-10-14 — Opus 5 build pass. Partially complete: everything except
the delete.** Six endpoints and three functions live, all exercised
over **real authenticated HTTP**.

### What shipped

| Thing | Live id | File |
|---|---|---|
| `POST planner/workspace/{id}/task` | 542 | `apis/planner/542_workspace_workspace_id_task_POST.xs` |
| `POST planner/task/{id}/place` | 543 | `apis/planner/543_task_task_id_place_POST.xs` |
| `POST planner/timeline/{id}/reorder` | 544 | `apis/planner/544_timeline_timeline_id_reorder_POST.xs` |
| `PATCH planner/task/{id}` | 545 | `apis/planner/545_task_task_id_PATCH.xs` |
| `GET planner/workspace/{id}/task` | 546 | `apis/planner/546_workspace_workspace_id_task_GET.xs` |
| `GET planner/task/{id}` | 547 | `apis/planner/547_task_task_id_GET.xs` |
| `planner/resequence` | fn 115 | `functions/planner/resequence.xs` |
| `planner/derive_tasks` | fn 116 | `functions/planner/derive_tasks.xs` |
| `planner/place_task` | fn 117 | `functions/planner/place_task.xs` |

### 🔴 Not done: task delete needs the founder's approval

`DELETE planner/task/{task_id}` and `planner/delete_task` are
**written but not pushed**. **Blocks FT-PLN-7-16.**

**This is the only planner delete that actually destroys anything.**
Deleting a plan, an agent or a timeline all keep the tasks; this one
removes work outright, so it is the one most likely to be regretted
and the one most worth a confirmation step in the UI.

Its second half is already proven: `planner/resequence` is pushed,
tested and idempotent, so only the single `db.del` is unverified.

US-PLN-6-06 / FT-PLN-7-18 (create-and-place on an empty cell) was not
built — it is a convenience wrapper over `place_task`, and its
all-or-nothing guarantee depends on the same unapproved path.

### Functional cases

| ID | Result |
|---|---|
| FT-PLN-7-01 | ✅ Backlog creates append and resequence to 1..n |
| FT-PLN-7-02 | ✅ Created into a timeline, appended, derived start correct |
| FT-PLN-7-03 | ✅ Whitespace title → `E-VAL-001`; duration `0` and `1441` → `E-PLN-013` |
| FT-PLN-7-04 | ✅ Backlog task placed into a timeline at index 1 landed second; **both** containers came back gapless |
| FT-PLN-7-05 | ✅ Index `99` clamped to the end; index `-1` → `E-PLN-015` |
| FT-PLN-7-06 | ✅ Moved between containers repeatedly; source and destination both resequenced each time |
| FT-PLN-7-07 | ✅ Placing a task into **another plan's** timeline → *"Entities must belong to the same workspace"*. Same for creating one there |
| FT-PLN-7-08 | ✅ A `needs_info` task kept its status and reason in the backlog, and had both cleared the moment it landed in a timeline |
| FT-PLN-7-09 | ✅ Placed back to the backlog: `planned_start` became `null`, source timeline gapless |
| FT-PLN-7-10 | ✅ Full reversal of a 7-task day applied; derived starts recomputed down the list |
| FT-PLN-7-11 | ✅ Missing, extra **and** duplicate ids each → `E-PLN-016`, order unchanged (task count verified afterwards) |
| FT-PLN-7-12 | ✅ Task 2 of 7 changed 30 → 120 minutes: only that row written, every later start shifted exactly 90 minutes |
| FT-PLN-7-13 | ✅ `needs_info` with no reason → `E-PLN-014`; with a reason → accepted |
| FT-PLN-7-14 | ✅ **Exactly the spec's numbers.** From `08:00` with 30/45/60 → `08:00`, `08:30`, `09:15`. Midnight wrap from `23:00` with 45/60/90 → `23:00`, `23:45`, `00:45`, `02:15` |
| FT-PLN-7-15 | ✅ All four: inherit from the day's agent, explicit override, override cleared back to inherit, and backlog with no override → `{agent_id: 0, name: null}` |
| FT-PLN-7-16 | ⛔ Blocked |
| FT-PLN-7-17 | ✅ **50 random place/reorder operations across 3 timelines and the backlog: zero errors, and all four containers exactly 1..n afterwards.** Task count held at 13 throughout — nothing lost or duplicated |
| FT-PLN-7-18 | ⛔ Not built (see above) |
| FT-PLN-7-19 | ✅ Cross-account task → `404 Task not found`; all six endpoints `401` unauthenticated |

`npm test`: 213/213.

### The ordering invariant, and how it is kept

`seq` is normalised in exactly one place — `planner/resequence` — and
every mutation ends by calling it for each container it touched.
Nothing else invents a sequence number. FT-PLN-7-17 is the evidence
that this holds under arbitrary interleaving.

**Insertion is done by arithmetic, not control flow**, and that is
forced by a XanoScript defect rather than chosen. Inserting "at index
2" would normally mean a loop that counts and branches on reaching the
target — but a `conditional` inside a `foreach` whose condition reads a
counter updated in that same iteration **silently discards everything
the branch writes** (found in PLN-6, documented in CLAUDE.md). So
`place_task` spaces the other tasks 10 apart, gives the moved task
`index * 10 + 5` so it falls in exactly one gap, and lets `resequence`
flatten it to 1..n. No branching inside any loop.

The same defect shaped the reorder validation: rather than looping to
check membership, it compares two counts — submitted vs. current, and
`id IN (submitted)` vs. current. That catches missing, extra,
duplicate **and** foreign ids, which is also why an id from another
plan cannot be reordered in.

### Deviations

| Change | Why |
|---|---|
| `seq` is 1..n, while PLN-1 created the column with default 0 | US-PLN-7-01 specifies 1..n and the frontend's `seq: idx + 1` agrees. `resequence` normalises any legacy 0-based rows on first touch |
| `planner/derive_tasks` is one function for list, read and hydrate | US-PLN-7-06 requires a single implementation. The single-task read filters that function's output rather than computing anything itself — a task's start depends on every task before it, so it cannot be derived from the row alone |
| Four new error codes | `E-PLN-013` (duration range), `E-PLN-014` (needs_info without a reason), `E-PLN-015` (negative index), `E-PLN-016` (reorder is not a permutation) |
| Task writes are blocked on an archived plan | P3A-1 makes an archived plan read-only |
| US-P3A-1-05 (`plan_change_log` on published timelines) not implemented | `plan_change_log` is LIVE-1's table and does not exist yet, and publishing is on hold for PLN-6/7, so no timeline can currently be published |
