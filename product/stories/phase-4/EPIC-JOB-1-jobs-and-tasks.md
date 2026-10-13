# JOB-1 — Jobs and Tasks

**Epic ID:** JOB-1
**Feature:** Add a job to a plan; its tasks appear automatically from the published map version.
**Status:** Planning
**Depends on:** PLAN-1
**Goal:** A **job** is one real instance of a work type. When added to a plan instance it is **pinned** to a published map version and receives one **task per work step** (stage × work-doing cell). Task text and expected durations are **read from the pinned version**, never copied.

---

## MVP scope (after review, 2026-10-12)

- Fully in scope.
- A task's content in the MVP is **task, done-when, owner row and expected minutes** (from existing cell fields, D-37). Input/output come later with LEAN-1.
- **Job attributes are free key/value pairs** in the MVP (D-44), each with its source and time; a controlled list per work type comes later with the intake schema.
- `work_item.status` is a cached value written **only** by the LOG-1 engine; the GOV-1 daily audit checks it against the status derived from the tasks (review finding F12).

## Context

Tasks are pulled, not pushed. A job stores only identity, attributes and status; the definition (task text, input, output, done-when, expected minutes, owner role) is read through the pinned version. This keeps one source of truth and makes live work immune to later map edits.

## Existing Architecture (Do Not Break)

- Phase-3 planner tables and the PLAN-1 instance (`planner_workspace`).
- `workflow_execution` (AI run engine) is untouched except an optional nullable link `work_item_id`.
- Published versions (PUB-1) are read-only inputs.

## Non-Goals

- No scheduling (SCHED-1), no execution events (LOG-1). Attributes do **not** alter durations.

---

## Stories

### US-JOB-1-01 — Tables `work_item` and `work_task`

**Files:** `static/tables/86_work_item.xs`, `87_work_task.xs`

- `work_item`: `id`, `created_at`, `updated_at`, `account_id`, `workspace_id → planner_workspace`, `journey_map_version_id → journey_map_version` (required), `title` (required), `status` enum `open | in_progress | blocked | completed | cancelled` (default `open`), `attributes` JSON (`{key: {value, source, entered_at}}`), `parent_work_item_id` (nullable self-reference), `created_by`, `started_at`, `finished_at`.
- `work_task`: `id`, `created_at`, `updated_at`, `work_item_id`, `stage_key`, `lens_key`, `status` enum `not_started | in_progress | blocked | done | skipped` (default `not_started`), `started_at`, `completed_at`.
- Unique `(work_item_id, stage_key, lens_key)`; btree `(work_item_id)`, `(workspace_id, status)`.
- `workflow_execution.work_item_id` nullable.

**Acceptance:** no text columns for task content; duplicate task key rejected.

### US-JOB-1-02 — Add a job (generates tasks)

- Input: workspace id, map id, title, optional attributes.
- The map must be in the instance's accepted maps and have a published version; the job pins the **latest published version at creation**.
- Tasks created for each stage: the **owner's cell** (its row must do planned work) plus any other work-doing cell that has a task (`task_objective`) in the version.
- Stage order is taken from the version.

**Acceptance:** a version with 3 stages and one owner each yields 3 tasks, all `not_started`; map not accepted or never published → clear error.

### US-JOB-1-03 — Pinning and hydrated read

- `GET work_item/{id}` returns the job with each task **hydrated** from its pinned version: task, done-when, owner row, expected minutes (TIME-1 rule).
- Publishing a newer version or editing the live map later does not change a job's hydrated content.

**Acceptance:** hydrated values equal the pinned snapshot, not the live map.

### US-JOB-1-04 — Attributes with source

- Planner sets attributes manually; each entry records `source = manual` and `entered_at`. The structure accepts other sources later without change.
- Attribute keys/values are plain controlled strings or numbers here; the map's intake schema is a later feature.

**Acceptance:** source and time are recorded for every attribute. Editing replaces the value and updates source and time; history of post-publish edits is handled by the plan change log (LIVE-1).

### US-JOB-1-05 — Job status derivation and cancel

- `deriveJobStatus(tasks)`: all `done/skipped` → `completed`; any `blocked` → `blocked`; any `in_progress` or a mix of done and not started → `in_progress`; none started → `open`. Cancelled is set explicitly and wins.
- Cancel marks the job `cancelled`; its tasks are left as they are (history) but are excluded from scheduling and from performer lists.

**Acceptance:** derivation table below passes; cancelled jobs disappear from planning views.

---

## Test Plan

**Fixtures:** a 3-stage synthetic version (two roles, one non-work role) in `fixtures/job-version-golden.json`; map 178 clone version for realism.

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-JOB-1-01 | Unit | `deriveJobStatus`: all not_started | `open` |
| UT-JOB-1-02 | Unit | one in_progress | `in_progress` |
| UT-JOB-1-03 | Unit | one blocked + others done | `blocked` |
| UT-JOB-1-04 | Unit | all done | `completed` |
| UT-JOB-1-05 | Unit | done + skipped only | `completed` |
| UT-JOB-1-06 | Unit | some done, rest not_started | `in_progress` |
| UT-JOB-1-07 | Unit | cancelled flag with tasks done | `cancelled` |
| UT-JOB-1-08 | Unit | `tasksFromVersion(version)` over the synthetic fixture | Expected keys, in stage order |
| UT-JOB-1-09 | Unit | Version with a non-work owner stage | Stage produces no task (reported) |
| FT-JOB-1-01 | Functional (`workflow_tests/18_jobs_and_tasks.xs`) | Add a job | Correct task count, all `not_started` |
| FT-JOB-1-02 | Functional | Add job for a map not accepted by the instance | Rejected |
| FT-JOB-1-03 | Functional | Add job for a never-published map | Rejected |
| FT-JOB-1-04 | Functional | Publish version 2, then re-read the job created under version 1 | Still version 1 content |
| FT-JOB-1-05 | Functional | Edit the live map cell text after job creation | Hydrated text unchanged |
| FT-JOB-1-06 | Functional | New job after version 2 | Pinned to version 2 |
| FT-JOB-1-07 | Functional | Duplicate `(job, stage, lens)` insert | Rejected |
| FT-JOB-1-08 | Functional | Attribute set manually | `source = manual`, `entered_at` present |
| FT-JOB-1-09 | Functional | Cancel job | Status `cancelled`; excluded from list for scheduling |
| FT-JOB-1-10 | Functional | Cross-account add/read | Denied |
| FT-JOB-1-11 | Functional | Hydrated expected minutes match TIME-1 golden values | Equal |
| FT-JOB-1-12 | Functional | Regression: workflow tests 1–9 and phase-3 planner tests | Green |

**Completion gate:** all pass.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity**

| Table | Keys and relations | Uniqueness | Required | Delete behaviour |
|---|---|---|---|---|
| `work_item` (86) | PK; `account_id`; `workspace_id → planner_workspace`; `journey_map_version_id → journey_map_version`; `parent_work_item_id → work_item` (nullable); all indexed | — | title, workspace, version, status | **Cancel**, never delete once any task has log events; versions are never deleted |
| `work_task` (87) | PK; `work_item_id → work_item` (indexed) | `(work_item_id, stage_key, lens_key)` | work_item, keys, status | Kept for history; changes only through LOG-1 |
| Status rule | `work_task.status` may be changed **only** by the LOG-1 engine; job status is derived | | | |

**Validation and friendly messages**

| Field / situation | Rule | Friendly message | Code |
|---|---|---|---|
| Title | 1–120 characters, trimmed, no HTML | "Give the job a short title (up to 120 characters)." | `E-JOB-001` |
| Map not in this plan | Must be an accepted map | "This plan doesn't use '{map}'. Add it to the plan's maps first." | `E-JOB-002` |
| Map never published | Must have a published version | "'{map}' hasn't been published yet." | `E-JOB-003` |
| Attributes | ≤ 50 keys; key = letters/numbers/underscore, ≤ 40 characters; value = text ≤ 200 characters or a number; **no nested objects** | "That detail isn't valid. Use short text or a number." | `E-JOB-004` |
| Cancel an already cancelled job | Idempotent | "This job is already cancelled." | `E-JOB-005` |

**Events logged** (`feature = JOB-1`): `add_job` (`success` with task count; `rejected`; `failure`), `cancel_job`, `set_attribute` (logs **key names only, never values**).

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-JOB-1-G01 | Unit | Junk corpus through title and attribute rules | Rejected correctly |
| UT-JOB-1-G02 | Unit | Event metadata builder with attribute values present | Values absent, keys present |
| FT-JOB-1-G01 | Functional | Schema audit on tables 86–87 | Pass |
| FT-JOB-1-G02 | Functional | Add-job failure injected after the job row, before tasks | No partial job |
| FT-JOB-1-G03 | Functional | Direct status change on `work_task` outside LOG-1 | Rejected |
| FT-JOB-1-G04 | Functional | Every rejection above | Friendly message, Reference, event, nothing written |
| FT-JOB-1-G05 | Functional | Integrity audit with a task key missing from the version | Detected |

## Test Results

_Not yet run._
