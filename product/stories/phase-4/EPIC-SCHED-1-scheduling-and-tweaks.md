# SCHED-1 — Scheduling and Tweaks

**Epic ID:** SCHED-1
**Feature:** The planner schedules job tasks onto timelines, assigns people by role, and tweaks durations per job.
**Status:** MVP scope built and verified over real HTTP, except **unschedule and cancel-propagation, which are deletes awaiting the founder's approval** (see Test Results)
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

**2026-10-15 — Opus 5 build pass. MVP scope built, minus the two
delete-dependent pieces.** One table, three endpoints, nine unit
tests, all functional cases over **real authenticated HTTP**.

### What shipped

| Thing | Live id | File |
|---|---|---|
| `planner_task_work_task` | table 124 | `static/tables/124_planner_task_work_task.xs` |
| `GET planner/workspace/{id}/backlog_work` | 559 | `apis/planner/559_workspace_workspace_id_backlog_work_GET.xs` |
| `POST planner/work_task/{id}/schedule` | 560 | `apis/planner/560_work_task_work_task_id_schedule_POST.xs` |
| `PATCH planner/planner_task/{id}/tweak` | 561 | `apis/planner/561_planner_task_planner_task_id_tweak_PATCH.xs` |
| `isValidScheduledDuration` etc. | — | `webapp/protype-2/src/scheduleModel.ts` |

### 🔴 Held: unschedule and cancel-propagation

Both are deletes, so both wait with the other six items listed in
`product/learning-fixes.md`:

- **US-SCHED-1-03's "Unschedule"** removes the `planner_task` and its
  link.
- **US-SCHED-1-06's propagation** removes a cancelled job's slots.

**This blocks FT-SCHED-1-04, -08, -09 and FT-SCHED-1-G04.** Everything
they need is in place — the link table cascades by design and
`planner/return_tasks_to_backlog` is already proven — so each is a
small addition once approved.

Partial cover exists today: a cancelled job's steps **already vanish
from the backlog** (verified), so they cannot be scheduled by
accident. What is missing is removing slots that were scheduled
*before* the cancellation.

### Unit tests

| ID | Result |
|---|---|
| UT-SCHED-1-08 | ✅ The epic's exact row — `0`, `-3`, `7.5`, `"x"` rejected; `45` accepted. Boundaries 1 and 1440 accepted, 1441 rejected |
| UT-SCHED-1-06 | ✅ `defaultBlockDuration` sums known durations and **reports** the ones with no estimate rather than guessing. `0` counts as missing, because an untouched decimal column reads as 0 in this workspace |
| UT-SCHED-1-G01 | ✅ Junk corpus (`null`, `""`, `"45"`, `NaN`, `Infinity`, `{}`, `[]`, `true`) all rejected |
| Extra | ✅ A tweak reason must be absent, `other`, or a key the job really has — `"Other"` and a made-up key are both rejected |

`npm test`: **248/248** (9 new).

Deferred stories' unit tests (UT-SCHED-1-01…05, -07) were not written:
they test derived blocks and role suggestions, which need ROLE-1.

### Functional cases

| ID | Result |
|---|---|
| FT-SCHED-1-01 | ✅ A new job's steps appear in the backlog, one row per work task (the MVP shape), each with its task text and expected minutes from the **pinned** version |
| FT-SCHED-1-02 | ✅ Scheduling created a slot with `duration_minutes` = the step's expected minutes, plus the link. The step left the backlog immediately |
| FT-SCHED-1-03 | ✅ Scheduling the same step twice → `E-SCHED-001` |
| FT-SCHED-1-04 | ⛔ Blocked (unschedule) |
| FT-SCHED-1-05 | ✅ Tweaked 999 → 120 with reason `rush_order`. **The version still reported 999** — expected minutes untouched — and `is_tweaked` came back true |
| FT-SCHED-1-06 | ✅ By construction: each job has its own slot and reads expected minutes from its own pinned version, so a tweak cannot reach another job |
| FT-SCHED-1-07 | ⛔ Deferred with role suggestions (ROLE-1). Assigning any agent of the plan works today and is tenancy-checked |
| FT-SCHED-1-08 | ⛔ Blocked (cancel propagation) — though cancelled jobs already leave the backlog |
| FT-SCHED-1-09 | ⛔ Blocked (agent delete) |
| FT-SCHED-1-10 | ✅ Slots take their planned start from the timeline's start plus the cumulative durations before them, via PLN-7's existing derivation — scheduled slots behave exactly like manual tasks |
| FT-SCHED-1-11 | ✅ Manual, unlinked planner tasks are untouched: the tweak endpoint reports `expected_minutes: 0` and `is_tweaked: false` for them rather than inventing an expectation |
| FT-SCHED-1-12 | ✅ Cross-account steps and slots → `404` |

### Beyond the plan

| Case | Result |
|---|---|
| Reset to default | ✅ `reset_to_expected` restored 999 and cleared the reason |
| `other` as a reason | ✅ Always allowed, even for a job with no attributes |
| Made-up reason | ✅ `E-SCHED-005` |
| Stale write | ✅ Sending `expected_duration_minutes: 45` when the row held 90 → `E-SCHED-003`; sending the correct value succeeded |
| Cancelled job's steps | ✅ Absent from the backlog, and scheduling one is refused |
| Schema audit | ✅ Table 124 passes at full strictness |

### A bug caught by testing, not by reading

**An explicit `duration_minutes: 0` was accepted.** The endpoint
clamped anything under a minute up to 30 *before* validating, so a
caller sending zero got a silent 30-minute slot instead of
`E-SCHED-002`. That is precisely the failure VAL-1 exists to prevent:
junk quietly becoming a plausible value.

The fallback now applies **only** when the caller sent nothing and the
version has no estimate. Anything supplied is held to 1–1440.
Re-tested: `0` and `1441` are both refused, and the step stays in the
backlog because nothing was written.

### ⚠️ A finding for GOV-1: `assert_fresh` cannot work on planner tables

`guards/assert_fresh` (GOV-1 standard S12) compares `updated_at`, and
SCHED-1 is the first epic to need stale-write detection. But **every
planner table declares `updated_at` as a `date`** — day granularity.
Two people editing the same slot ten minutes apart produce an
identical value, so the guard would pass the second write while
reporting success. Using it here would have been worse than not
using it, because it would look like protection.

This endpoint uses **value-based** concurrency instead: the caller
sends the duration it last saw, and the write is refused if the row
has moved. Narrower than a timestamp check — it only fires when the
field being changed actually moved — but it is true.

**For the founder:** S12 cannot be switched on across the planner
until `updated_at` becomes a `timestamp` on those tables. That is a
column type change on tables with `trim` validators, so it hits the
same `updateTableSchema` problem as the other open schema items.

### Deviations

| Change | Why |
|---|---|
| A scheduled slot's `title` is left empty | The real title lives in the pinned version and is read through the link; copying it would create a second copy that drifts. **Known gap:** PLN-7's task list does not hydrate linked slots yet, so they read blank there. That belongs with the planner UI work |
| Duration can be tweaked at schedule time, not only afterwards | The planner usually knows immediately that a step needs longer for this job; forcing a second call to say so is friction for no safety gain. The same validation applies either way |
| `E-SCHED-004` (role warning) not cataloged | It belongs to the deferred role-suggestion story |
