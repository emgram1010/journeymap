# VAR-1 — Variance and Outliers

**Epic ID:** VAR-1
**Feature:** The system computes expected vs. scheduled vs. actual on its own and flags tasks that ran unusually long.
**Status:** Planning
**Depends on:** LOG-1 (and SCHED-1/LIVE-1 for scheduled values)
**Goal:** Nobody reports variance. It is **derived** from the activity log, the pinned version and the published snapshot. Unusually long tasks are **flagged** for someone to explain instead of being trusted blindly (this replaces pause capture in the MVP).

---

## MVP scope (after review, 2026-10-12)

| In the MVP | Deferred (post-MVP) |
|---|---|
| Per-task variance (01) · outlier flag (02) · per-job report (part of 03) · data-quality warnings (Governance) | Stage aggregates (rest of 03) · planner-tweak signal (04) · variance panel (05) · time-window adherence (PRD VA-2, review finding F20) |

Tasks marked Done without Start (D-38) have **unknown** actual time: no gap, no outlier, warning `W-VAR-001`.

## Context

Three durations, three owners:

| Number | Source |
|---|---|
| **Expected** | Pinned map version (minutes via TIME-1) |
| **Scheduled** | Published snapshot's scheduled minutes (the planner's tweak included) |
| **Actual** | Activity log: start to done (elapsed) |

The earlier initiative plans similar numbers for AI runs (`planned_duration_ms`, `duration_gap_ms`, `duration_gap_pct`, `overrun_rate`, minimum 5 runs: US-EXE-10…12). This epic reuses those ideas at **task level**; names can be aligned during reconciliation.

## Existing Architecture (Do Not Break)

- Nothing is stored: variance is a read model computed from existing data. The log is never edited.

## Non-Goals

- No attribute-based modifiers (future). No AI recommendations (future). No pause capture.

---

## Stories

### US-VAR-1-01 — Per-task variance (pure function)

**Files:** `webapp/protype-2/src/variance.ts`, `variance.test.ts`; backend function `compute_task_variance.xs`

- Inputs: task events, expected minutes, scheduled minutes, planned start.
- Outputs: `actual_minutes` (first start to latest completion; if reopened, uses the latest start-to-completion span after the reopen), `blocked_minutes` (sum of blocked→unblocked intervals, reported separately), `expected_gap_minutes`, `expected_gap_pct`, `scheduled_gap_minutes`, `scheduled_gap_pct`, `start_lateness_minutes`.
- Missing inputs yield `null` for the dependent fields, never an error or a guess.

**Acceptance:** golden cases below; same result on frontend and backend.

### US-VAR-1-02 — Outlier flag

- A task is an **outlier** when `actual_minutes > max(outlier_factor × reference, reference + outlier_floor_minutes)`, where `reference` = scheduled minutes if present, else expected. Defaults: factor **2.0**, floor **10** minutes. Constants live in one place.

**Acceptance:** boundary values behave per the table; tasks without a reference or without a completion are never flagged.

### US-VAR-1-03 — Job and stage reports

- `GET variance/work_item/{id}` returns per-task variance and totals.
- `GET variance/stage?map&from&to` aggregates by stage: average gap %, overrun rate (gap > +5%), worst gap %, sample size. Aggregates return **only with at least 5 samples**; otherwise `insufficient_data = true`.

**Acceptance:** thresholds respected; filters by work type, stage, role and date range work.

### US-VAR-1-04 — Planner-tweak signal *(deferred)*

- Aggregate "scheduled ≠ expected" by stage and by reason key: share of jobs tweaked, average tweak %, count. Same minimum sample rule.

**Acceptance:** stage with consistent upward tweaks surfaces in the report; tweak reasons grouped.

### US-VAR-1-05 — Read-only variance panel (planner/manager) *(deferred)*

- Table of the stage report with outlier badges and a drill-down to jobs.

**Acceptance:** renders `insufficient_data` clearly; no edit controls.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-VAR-1-01 | Unit | Start 09:00, done 09:40, expected 30 | actual 40, expected gap +10 (+33.3%) |
| UT-VAR-1-02 | Unit | Same with scheduled 45 | scheduled gap -5 (-11.1%) |
| UT-VAR-1-03 | Unit | Blocked 09:10–09:20 | `blocked_minutes` 10; `actual_minutes` unchanged (elapsed) |
| UT-VAR-1-04 | Unit | Never started / never completed | actual `null`; no outlier |
| UT-VAR-1-05 | Unit | Expected missing | expected gap `null`; scheduled gap still computed |
| UT-VAR-1-06 | Unit | Start 09:05, planned 09:00 | `start_lateness_minutes` 5 |
| UT-VAR-1-07 | Unit | Reopened after done | Uses the latest start→completion span |
| UT-VAR-1-08 | Unit | Outlier boundary: reference 30, actual 60 / 61 | Not flagged / flagged |
| UT-VAR-1-09 | Unit | Small task: reference 3, actual 12 | Not flagged (floor +10 → 13) |
| UT-VAR-1-10 | Unit | Aggregate with 4 samples vs. 5 samples | `insufficient_data` vs. values |
| UT-VAR-1-11 | Unit | Overrun-rate threshold at exactly +5% | Not overrun; +5.1% overrun |
| UT-VAR-1-12 | Unit | Frozen inputs; same call twice | No mutation; same output |
| UT-VAR-1-13 | Unit | Done without a start event | Actual unknown; no gap; no outlier; `W-VAR-001` |
| FT-VAR-1-01 | Functional (`workflow_tests/23_variance.xs`) | Seed log events for a task | Backend result equals frontend golden values |
| FT-VAR-1-02 | Functional | Stage aggregate over a date range | Matches hand-computed expectation |
| FT-VAR-1-03 | Functional | Filters by work type/stage/role | Only matching rows |
| FT-VAR-1-04 | Functional | Tweak signal with 5+ jobs | Reported with reason breakdown |
| FT-VAR-1-05 | Functional | Cross-account | Denied |
| FT-VAR-1-06 | Functional | Nothing in the log or version is modified by reading variance | Confirmed (row counts and hashes unchanged) |
| E2E-VAR-1-01 | UI | Variance panel with sufficient and insufficient data | Both states render *(deferred with the panel)* |

In the MVP, UT-VAR-1-10, UT-VAR-1-11, FT-VAR-1-02 to 04 (aggregates and tweak signal) are deferred.

**Completion gate:** all pass.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity:** read-only. Nothing is stored; every figure is derived from the log, the pinned version and the publication snapshot. Reading variance must never change data.

**Data-quality checks (warnings, not blocks)**

| Check | Meaning | Code |
|---|---|---|
| Task `done` with no start event | Missing data | `W-VAR-001` |
| End earlier than start | Clock or data problem | `W-VAR-002` |
| Elapsed time longer than 24 hours | Probably forgotten | `W-VAR-003` |
| No expected duration on the map | Cannot compute gap | `W-VAR-004` |

Warnings appear on the Health page as low-severity issues with the owner (usually the product manager, to fix the map or follow up with the performer).

**Validation and friendly messages**

| Situation | Friendly message | Code |
|---|---|---|
| Date range longer than 366 days | "Choose a range of up to one year." | `E-VAR-001` |
| Start after end | "The start date must be before the end date." | `E-VAR-002` |
| Unknown map, stage or role in a filter | "We couldn't find that filter option." | `E-VAR-003` |
| Not enough data | "Not enough data yet (needs at least 5 completed jobs)." (not an error) | — |

**Events logged** (`feature = VAR-1`): `compute_report` (`success` with duration and row count; `failure`), `data_quality_warning` (code and counts only).

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-VAR-1-G01 | Unit | Each data-quality rule | Raises the right warning code |
| FT-VAR-1-G01 | Functional | Filter validation (bad range, unknown id) | Friendly message; nothing computed |
| FT-VAR-1-G02 | Functional | Report on a large synthetic data set | Completes; `success` event has duration |
| FT-VAR-1-G03 | Functional | Row counts and hashes before and after reading | Unchanged |

## Test Results

**Run 2026-10-15. Completion gate: PASSED** for everything in MVP scope. Stage aggregates and the tweak signal (US-VAR-1-04/05) are deferred per the epic's own MVP scope table; their tests were not attempted.

Built: `webapp/protype-2/src/variance.ts` (pure), function **144** `variance/compute_task_variance`, function **147** `variance/task_report`, endpoint **568** `GET variance/work_item/{id}`.

### A real bug found via live testing, not by the unit tests

The unit tests' reopen case (UT-VAR-1-07) assumed an explicit `started` event could follow a `reopened` one. Live testing on a real task that had actually been reopened during APP-1's own testing showed this is **impossible in the real system** — `logModel.ts::canTransition` has no `in_progress`+`started` row, and the UI's `availableActions('in_progress')` never offers a Start button. The first version of `computeTaskVariance` treated every reopen as "attempt start unknown", which produced a live, wrong result: `actual_minutes: null` and a spurious `W-VAR-001` on a task that had plainly been worked on.

**Fixed**: on `reopened`, the resumed attempt now begins at the reopen's own timestamp, not `null` — the reopen IS the only signal that work resumed, so it is treated as one. Fixed in `variance.ts`, the test (corrected to the realistic sequence, plus a new test pinning that `start_lateness_minutes` still uses the ORIGINAL first start across a reopen), and the XanoScript twin. Re-verified live afterward: the same real task now reports a correct `actual_minutes` and no warning.

### Also found and documented separately (CLAUDE.md, cross-cutting, not VAR-1-specific)

`==`/`!=` against `null` in XanoScript is a PHP-style LOOSE comparison: `0`, `""`, `false` and `[]` all test equal to `null`. Found because a smoke test using `occurred_at: 0` as a stand-in timestamp silently produced the wrong answer. Does not affect VAR-1 in production (every timestamp compared is a real epoch ms, never legitimately `0`) — checked by hand — but it is a landmine for the rest of the codebase. Flagged in `learning-fixes.md` as needing a dedicated sweep; not done here.

### Unit (`npm test`, 321/321 green — 18 new)

| ID | Result | Notes |
|---|---|---|
| UT-VAR-1-01 | Pass | Start 09:00, done 09:40, expected 30 → actual 40, +10 (+33.3%). |
| UT-VAR-1-02 | Pass | Same with scheduled 45 → -5 (-11.1%). |
| UT-VAR-1-03 | Pass | Blocked 09:10–09:20 → `blocked_minutes` 10; `actual_minutes` unchanged (elapsed, blocked time included, never subtracted). |
| UT-VAR-1-04 | Pass | Never started/completed → actual null, no outlier. |
| UT-VAR-1-05 | Pass | Expected missing → expected gap null; scheduled gap still computed. |
| UT-VAR-1-06 | Pass | Start 09:05, planned 09:00 → lateness 5. |
| UT-VAR-1-07 | Pass (corrected) | Reopened then completed directly → actual_minutes from the reopen itself; no warning. |
| UT-VAR-1-08 | Pass | Outlier boundary: reference 30, actual 60 not flagged, 61 flagged. |
| UT-VAR-1-09 | Pass | Reference 3, actual 12 not flagged (floor dominates: 3+10=13). |
| UT-VAR-1-12 | Pass | Frozen input, called twice, identical output, no mutation. |
| UT-VAR-1-13 | Pass | Done with no start → actual null, `W-VAR-001`. |
| UT-VAR-1-G01 | Pass | All four warning codes (`W-VAR-001..004`) individually triggered; a clean task carries none. |

UT-VAR-1-10/11 (aggregate thresholds) deferred with the stage-aggregate story.

### Functional / live (real authenticated HTTP, account 6, work_item 4 — a job created fresh during APP-1, with real reopen/block/unblock history)

| ID | Result | Evidence |
|---|---|---|
| FT-VAR-1-01 | Pass | Backend `variance/compute_task_variance` matched the TS golden cases exactly over real HTTP-reachable `runWorkspaceFunction` calls, including the reopen fix. |
| FT-VAR-1-05 | Pass | `GET variance/work_item/99999` (another account's id) → 404 "Job not found". |
| FT-VAR-1-06 / FT-VAR-1-G03 | Pass | Called the report twice in a row: byte-identical response both times; `activity_log` and `work_task` row counts unchanged across the calls. |
| FT-VAR-1-G02 | Pass | Report completes; `compute_report` event logged with `duration_ms` (105–454ms observed) and the right counts. |

**`start_lateness_minutes` cross-checked independently**, outside the XanoScript engine entirely: a task's real `started_at` (captured during APP-1 testing) minus the timeline's `planned_date`+`start_time` (parsed via Node's own `Date`), by hand, in a shell — `276.47411666666665` both ways, to the full float. This also incidentally proved the `parse_timestamp`/`add_secs_to_timestamp` chain and the cumulative-seq-offset math inside `variance/task_report` are correct, not just plausible.

**Outlier and scheduled/expected gaps verified on real (if deliberately odd) fixture data**: one task with `expected_minutes: 999` (a LOG-1-era test value) and `scheduled_minutes: 20` correctly used scheduled as the reference (not expected) and reported `expected_gap_pct: -97.8%` against the odd expected value while `scheduled_gap_pct: +11.3%` against the real one — exactly the "scheduled wins over expected" rule (US-VAR-1-02).

### Governance

| ID | Result | Evidence |
|---|---|---|
| FT-VAR-1-G02 | Pass | See above. |
| FT-VAR-1-G03 | Pass | See above. |
| `data_quality_warning` event | Pass | One event per REPORT (not per row), with a `by_code` tally — confirmed via `event_log`: `{"W-VAR-001":1}` matching the one task that was genuinely done-without-start. |

### Not run / deferred (per the epic's own MVP scope)

| ID | Why |
|---|---|
| UT-VAR-1-10, UT-VAR-1-11 | Aggregate thresholds — stage aggregates are explicitly deferred. |
| FT-VAR-1-02, 03, 04 | Stage report filters and the tweak signal — same deferral. |
| FT-VAR-1-G01 | Filter validation (bad date range, unknown id) applies to the deferred stage-aggregate endpoint, which was not built. The MVP per-job endpoint's only "filter" is `work_item_id` itself, which is tenancy-checked (FT-VAR-1-05). |
| E2E-VAR-1-01 | The variance panel (US-VAR-1-05) is explicitly deferred with the aggregate report. |
| `workflow_tests/23_variance.xs` | Same standing gap as every other epic this session: no tool exists to run a Xano workflow test from here. Driven through `runWorkspaceFunction` and real HTTP instead. |

### Needs the founder

Four more scratch functions used to verify this epic (`parse_timestamp_probe`, `nested_conditional_probe`, `zero_vs_null_probe`, `var1_check` — all read-only) are now on the held-deletion list in `learning-fixes.md`, which also carries the codebase-wide null-comparison sweep recommendation.
