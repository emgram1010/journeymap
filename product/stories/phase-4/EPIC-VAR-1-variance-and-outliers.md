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

_Not yet run._
