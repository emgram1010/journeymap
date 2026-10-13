# SCHED-1 — Scheduling and Tweaks

**Epic ID:** SCHED-1
**Feature:** The planner schedules job tasks onto timelines, assigns people by role, and tweaks durations per job.
**Status:** Planning
**Depends on:** JOB-1, P3A-1, phase-3 PLN-5 … PLN-7 (agents, timelines, tasks)
**Goal:** Unscheduled job tasks appear in the planner backlog. The planner places them (stages marked continuous appear as **one block**), assigns an agent with a suggestion by role, and may tweak the scheduled duration **for that job only**. Expected duration (from the map) is never overwritten.

---

## MVP scope (after review, 2026-10-12)

| In the MVP | Deferred (post-MVP) |
|---|---|
| Link table (01) · backlog and schedule action (03) with **one scheduled item per work task** (each stage its own item) · per-job duration tweak (05) · propagation (06) | Derived blocks (02) and the continuous flag · role-based agent suggestions and the role warning (04), which need ROLE-1 |

In the MVP the default scheduled duration is the task's own expected minutes. The link table is kept so blocks can be added later without a migration.

## Context

Phase-3 defines `planner_task` with `timeline_id` (null = backlog), `duration_minutes`, `assignee_agent_id` and a derived planned start. A scheduled item may cover several consecutive work tasks of one job (a **block**), so linking is many-to-one, through a join table. Blocks are **derived**, not stored.

## Existing Architecture (Do Not Break)

- Phase-3 `planner_task`, `planner_timeline`, ordering/reorder functions, derived start times.
- Manual planner tasks with no job link keep working.
- Three durations: **expected** (map, via version), **scheduled** (`planner_task.duration_minutes`), **actual** (log; not touched here).

## Non-Goals

- No automatic sequencing/optimization. No capacity enforcement. No publish to live (LIVE-1).

---

## Stories

### US-SCHED-1-01 — Link table `planner_task_work_task`

**File:** `static/tables/88_planner_task_work_task.xs`

- `planner_task_id`, `work_task_id` (unique on `work_task_id`: a task is scheduled at most once), plus `position` within the block.
- Uses the P3A-1 columns: `planner_task.title` nullable when linked (effective title is read from the pinned version) and `planner_task.tweak_reason` (key of a job attribute or `other`).

**Acceptance:** a work task cannot be linked to two planner tasks; unlinked planner tasks unaffected.

### US-SCHED-1-02 — Derived blocks *(deferred)*

- `deriveBlocks(tasks, stages)`: consecutive tasks of one job form a block when each later stage has `continuous_with_previous = true` **and** the same owner role as the previous stage. Anything else starts a new block.
- Used for the backlog view and when scheduling.

**Acceptance:** pure function; deterministic.

### US-SCHED-1-03 — Backlog and schedule action

- Backlog lists **unscheduled blocks** (one row per block) across jobs of the instance.
- "Schedule" creates one `planner_task` for the block with default `duration_minutes` = **sum of expected minutes**, placed on a timeline per phase-3 ordering rules.
- "Unschedule" returns the block to backlog (deletes the `planner_task` and its links).

**Acceptance:** scheduled blocks leave the backlog; unscheduled return; default duration equals the expected sum.

### US-SCHED-1-04 — Assignment by role *(deferred; MVP: the planner assigns any active person)*

- Agent suggestions for a block = agents holding the block's owner role (ROLE-1 `agent_role`). The planner can still pick any agent.
- Soft warning (not a block) when no agent holds the role or a different role is chosen.

**Acceptance:** suggestions correct; assignment never blocked by the warning.

### US-SCHED-1-05 — Per-job duration tweak

- Planner edits the scheduled duration of a block (≥ 1 minute) with an **optional reason** (a key from the job's attributes, or `other`).
- Only that job's `planner_task` changes; the map version and other jobs are unaffected.
- A tweak is "scheduled ≠ expected" and is available to variance (VAR-1).

**Acceptance:** expected minutes unchanged after a tweak; reason stored; tweak resettable to default.

### US-SCHED-1-06 — Propagation

- Cancelling a job removes its unscheduled blocks from the backlog and removes its `planner_task` rows (history lives in the plan change log once published, LIVE-1).
- Deleting an agent follows phase-3 rules; linked work tasks return to backlog.

**Acceptance:** no orphan links remain after any of these actions.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-SCHED-1-01 | Unit | Three stages, same role, stages 2–3 continuous | One block of three |
| UT-SCHED-1-02 | Unit | Same role but a stage not continuous | New block |
| UT-SCHED-1-03 | Unit | Continuous flag but owner role changes | New block |
| UT-SCHED-1-04 | Unit | First stage continuous (invalid) | Treated as a new block |
| UT-SCHED-1-05 | Unit | Interleaved: A, B, A with B not continuous | Three separate blocks |
| UT-SCHED-1-06 | Unit | `defaultBlockDuration` over tasks with a missing duration | Sum of known; flags missing |
| UT-SCHED-1-07 | Unit | `suggestAgents(role, agents)` | Only agents with the role, stable order |
| UT-SCHED-1-08 | Unit | Tweak validation: 0, -3, 7.5, "x", 45 | Rejected, rejected, rejected, rejected, accepted |
| FT-SCHED-1-01 | Functional (`workflow_tests/19_scheduling.xs`) | Add job → backlog | One row per derived block |
| FT-SCHED-1-02 | Functional | Schedule a block | `planner_task` with default = expected sum; links created |
| FT-SCHED-1-03 | Functional | Schedule the same work task twice | Rejected |
| FT-SCHED-1-04 | Functional | Unschedule | Back in backlog; links removed |
| FT-SCHED-1-05 | Functional | Tweak duration with a reason | Scheduled changes; version expected unchanged; reason stored |
| FT-SCHED-1-06 | Functional | Tweak on job A | Job B same block unaffected |
| FT-SCHED-1-07 | Functional | Assign agent without the role | Allowed with warning flag |
| FT-SCHED-1-08 | Functional | Cancel job | Backlog and planner tasks removed; no orphan link |
| FT-SCHED-1-09 | Functional | Delete assigned agent | Phase-3 behaviour; work tasks return to backlog |
| FT-SCHED-1-10 | Functional | Planned start times for a block | Derived from timeline start + cumulative durations (phase-3 rule) |
| FT-SCHED-1-11 | Functional | Manual (unlinked) planner task | Unchanged behaviour |
| FT-SCHED-1-12 | Functional | Cross-account | Denied |
| E2E-SCHED-1-01 | UI | Backlog → schedule → tweak → unschedule | Works end to end |

Tests for deferred stories (UT-SCHED-1-01 to 05, UT-SCHED-1-07, FT-SCHED-1-07) run when blocks and role suggestions are built. In the MVP, FT-SCHED-1-01 expects **one backlog row per work task**.

**Completion gate:** all pass; phase-3 planner tests green.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity**

| Table / column | Keys and relations | Uniqueness | Required | Delete behaviour |
|---|---|---|---|---|
| `planner_task_work_task` (88) | PK; `planner_task_id → planner_task`; `work_task_id → work_task` (both indexed) | `work_task_id` (scheduled at most once) | both, position | **Cascade** when the planner task is deleted; the work task returns to backlog |
| `planner_task.tweak_reason` | Text key of a job attribute or `other` | — | — | — |
| `planner_task.duration_minutes` | Integer 1–1440 | — | yes | — |

Edits to planner tasks use `expected_updated_at` (stale writes rejected).

**Validation and friendly messages**

| Situation | Friendly message | Code |
|---|---|---|
| Already scheduled | "This step is already on the schedule." | `E-SCHED-001` |
| Duration not a whole number of minutes from 1 to 1440 | "Enter a duration between 1 and 1,440 minutes." | `E-SCHED-002` |
| Changed by someone else | "Someone else changed this. Reload to see the latest." | `E-SCHED-003` |
| No agent holds the role (warning, not a block) | "Nobody in this plan is set up for '{role}'. You can still assign someone." | `W-SCHED-004` |
| Unknown tweak reason | "Pick a reason from the list or choose 'Other'." | `E-SCHED-005` |

**Events logged** (`feature = SCHED-1`): `schedule_block`, `unschedule_block`, `tweak_duration` (with expected, old and new minutes and the reason key), `assign_agent`, each `success`/`rejected`/`failure`.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-SCHED-1-G01 | Unit | Junk corpus through the duration and reason rules | Rejected correctly |
| FT-SCHED-1-G01 | Functional | Schema audit on table 88 | Pass |
| FT-SCHED-1-G02 | Functional | Schedule failure injected after the planner task, before links | No partial schedule |
| FT-SCHED-1-G03 | Functional | Two simultaneous edits of one block | Second rejected; first kept |
| FT-SCHED-1-G04 | Functional | Delete a planner task | Links removed; work tasks back in backlog; no orphan |
| FT-SCHED-1-G05 | Functional | Every rejection above | Friendly message, Reference, event, nothing written |

## Test Results

_Not yet run._
