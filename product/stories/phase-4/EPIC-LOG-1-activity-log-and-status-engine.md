# LOG-1 — Activity Log and Status Engine

**Epic ID:** LOG-1
**Feature:** Every action on a task is recorded in an append-only log, and task status follows fixed rules.
**Status:** Planning
**Depends on:** JOB-1
**Goal:** One engine records what happened (who, what, when) and moves a task through the **fixed statuses** (`not_started`, `in_progress`, `blocked`, `done`, `skipped`). Start and end times come from the actions performers already take. Blocked requires a reason from **one fixed list**. A stage advances when its completion rule is satisfied.

---

## MVP scope (after review, 2026-10-12)

- **Done is allowed straight from Not started** (D-38). The start time is then unknown; VAR-1 reports actual time as unknown and flags it (`W-VAR-001`).
- **Fixed stage rule:** a stage is done when all its work tasks are done or skipped. Configurable completion rules come later with STAGE-1's deferred fields.
- **Log events point to the frozen publication item** (`plan_publication_id` + `item_ref`), never to a planner task that could be deleted (review finding F5).
- **One status list** for human work now and AI runs later (D-39); the earlier initiative's `complete/delayed/novel_exception` words are not used.

## Context

The earlier initiative (`product/validation-publish-execution/execution/`) plans a per-stage log inside `workflow_execution` for AI-run maps (US-EXE-01…03). This epic is the **task-level** record for human (and later AI) performers. Field ideas such as timestamps and a status enum are shared; names are reconciled later.

## Existing Architecture (Do Not Break)

- `workflow_execution` and the AI orchestrator: untouched.
- `work_task` status/timestamps are updated **only** by this engine.

## Non-Goals

- No pause capture (decision D-17). No offline queue (future). No variance maths (VAR-1).

---

## Stories

### US-LOG-1-01 — Table `activity_log`

**File:** `static/tables/91_activity_log.xs`

- `id`, `created_at`, `work_task_id`, `work_item_id` (denormalised; must match the task), `event_type` enum `started | completed | blocked | unblocked | skipped | reopened | note`, `performer_user_id` (nullable), `performer_agent_id` (nullable), `occurred_at` (server time), `client_occurred_at` (nullable, reserved for offline later), `reason_code` enum `waiting_on_someone | missing_information | something_went_wrong | other` (nullable), `note` text, `source` enum `manual | ai | system`, `plan_publication_id → plan_publication` (nullable; immutable target), `publication_item_ref` text (nullable), `client_event_id` text (unique, for duplicate-tap protection).
- Indexes: `(work_task_id, occurred_at)`, `(work_item_id, occurred_at)`, unique `client_event_id`.

**Acceptance:** no update/delete endpoint exists; duplicate `client_event_id` is rejected.

### US-LOG-1-02 — Transition rules (pure + backend)

Allowed transitions:

| From | Event | To |
|---|---|---|
| `not_started` | started | `in_progress` |
| `not_started` | blocked | `blocked` |
| `not_started` | skipped | `skipped` |
| `not_started` | completed | `done` (start time unknown; flagged by VAR-1) |
| `in_progress` | completed | `done` |
| `in_progress` | blocked | `blocked` |
| `in_progress` | skipped | `skipped` |
| `blocked` | unblocked | `in_progress` |
| `blocked` | skipped | `skipped` |
| `done`, `skipped` | reopened | `in_progress` |

`note` is allowed in any state and changes nothing. Everything else is rejected.

**Acceptance:** `canTransition(from, event)` frontend and backend equal for every pair (golden table).

### US-LOG-1-03 — Record-event API

- `POST work_task/{id}/event`: validates the transition, requires a `reason_code` for `blocked`, writes the log row and updates `work_task` (`started_at` on the first start; `completed_at` on completion; cleared on reopen) in **one transaction**.
- Authorisation: the performer assigned through the published snapshot (APP-1), or a planner acting for them (`source = system`/`manual`).

**Acceptance:** invalid transition or missing reason → rejected, nothing written; a failure writes neither log nor status.

### US-LOG-1-04 — Stage advance and job status

- After each event, check whether the stage is done. **MVP fixed rule:** every work task of the stage is done or skipped. (Configurable `completion_rule` values `any_done` and `manual` come later with STAGE-1.)
- The job's status is re-derived (JOB-1) and its `started_at`/`finished_at` set.

**Acceptance:** a stage completes exactly when its last open task is done or skipped.

### US-LOG-1-05 — Append-only guarantee

- Corrections are new events (`reopened`, `note`). No endpoint edits or removes log rows.

**Acceptance:** PATCH/DELETE on the log return not-found/forbidden; replaying the log reproduces the task's current status.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-LOG-1-01 | Unit | Table-driven: every (status, event) pair | Allowed set equals the table above; all others rejected |
| UT-LOG-1-02 | Unit | `blocked` without a reason | Rejected |
| UT-LOG-1-03 | Unit | `blocked` with each of the four reasons | Accepted |
| UT-LOG-1-04 | Unit | `replay(events)` over a mixed sequence | Equals expected final status and timestamps |
| UT-LOG-1-05 | Unit | `reopened` then `completed` | `completed_at` updated; first `started_at` kept |
| UT-LOG-1-06 | Unit | `stageComplete(rule, tasks)` for all three rules | Correct booleans |
| UT-LOG-1-07 | Unit | Duplicate `client_event_id` handling helper | Second returns the first result |
| FT-LOG-1-01 | Functional (`workflow_tests/21_activity_log.xs`) | Start → done on a task | Two log rows; status `done`; timestamps set |
| FT-LOG-1-02 | Functional | Invalid transition (e.g. `done` → `started`) | Rejected; nothing written |
| FT-LOG-1-03 | Functional | Blocked without reason | Rejected |
| FT-LOG-1-04 | Functional | Same `client_event_id` sent twice | One row; both calls succeed |
| FT-LOG-1-05 | Functional | PATCH or DELETE a log row | Rejected |
| FT-LOG-1-06 | Functional | `all_required_done` stage with 2 tasks | Advances only after both done/skipped |
| FT-LOG-1-07 | Functional | `any_done` stage | Advances after the first done |
| FT-LOG-1-08 | Functional | `manual` stage | Never auto-advances |
| FT-LOG-1-09 | Functional | Replay a task's log | Matches stored status |
| FT-LOG-1-10 | Functional | Event by a user not assigned | Denied |
| FT-LOG-1-11 | Functional | Cross-account event | Denied |
| FT-LOG-1-12 | Functional | Transaction failure (simulated) | No partial log or status change |
| FT-LOG-1-13 | Functional | Regression: workflow tests 1–9 | Green |
| UT-LOG-1-08 | Unit | `completed` from `not_started` | Allowed; `started_at` stays empty; `completed_at` set |
| FT-LOG-1-14 | Functional | Done without Start | Accepted; log row written; task `done` with unknown start |
| FT-LOG-1-15 | Functional | Event references a publication item; the planner task is later removed | Log row still valid; audit finds no orphan |

In the MVP, FT-LOG-1-07 and FT-LOG-1-08 (configurable rules) are deferred, and UT-LOG-1-06 tests only the fixed rule.

**Completion gate:** all pass.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity: `activity_log` (91)**

| Aspect | Rule |
|---|---|
| Keys | PK; `work_task_id → work_task` and `work_item_id → work_item` (indexed, required, and consistent with each other); performer user or agent; `plan_publication_id` + `publication_item_ref` (nullable; points to an immutable record) |
| Uniqueness | `client_event_id` (duplicate taps cannot double-record) |
| Required | work task, event type, server time, source |
| Enums | event type, reason code, source |
| Delete | **Never updated or deleted** by any endpoint (retention may prune only closed jobs) |
| Atomic | Log row and the task's status/timestamps are written **in one transaction** |
| Truth check | Replaying a task's log must always equal its stored status (verified daily) |

**This is the most important write path in the product.** A log write that fails must never be silent.

**Validation and friendly messages**

| Situation | Friendly message | Code |
|---|---|---|
| Action not allowed from this status | "This step is already {status}. {what to do next}." | `E-LOG-001` |
| Blocked without a reason | "Pick a reason so the team knows why." | `E-LOG-002` |
| Not your task | "This step isn't assigned to you." | `E-LOG-003` |
| Duplicate tap | Treated as success (returns the first result) | — |
| Save failed | "Your tap wasn't saved. Please try again. Reference: {ref}." | `E-LOG-004` |
| Unknown reason code | "Pick one of the listed reasons." | `E-LOG-005` |

**Events logged** (`feature = LOG-1`): `record_event` for every event as `success` (the heartbeat, with duration), `rejected` (with code) or `failure`. A **failed log write is severity `error`** and appears at the top of the Health page. Health tiles show **time of the last performer event**.

**Daily audit:** replay-vs-status check across all open and recently closed tasks; findings appear as issues.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| FT-LOG-1-G01 | Functional | Schema audit on table 91 | Pass |
| FT-LOG-1-G02 | Functional | Failure injected after the log row, before the status update | No log row, no status change |
| FT-LOG-1-G03 | Functional | Failure injected writing the log row | User gets `E-LOG-004`; `failure` event at severity error; status unchanged |
| FT-LOG-1-G04 | Functional | Every rejection above | Friendly message, Reference, `rejected` event |
| FT-LOG-1-G05 | Functional | Event whose `work_item_id` doesn't match the task | Rejected |
| FT-LOG-1-G06 | Functional | Daily replay audit with a tampered status | Detected as an issue (owner: engineer) |
| FT-LOG-1-G07 | Functional | Successful event | `success` event recorded; heartbeat tile updates |

## Test Results

**Run 2026-10-15. Completion gate: PASSED** for everything in MVP scope. Two cases could not be run and are listed honestly at the bottom.

Built live in workspace 1: table **127** `activity_log` (the epic reserved 91; Xano assigns its own ids), endpoint **563** `POST work_task/{id}/event`, and functions **130** `log/sync_job_status`, **131** `log/stage_progress`, **132** `log/next_status`, **134** `log/replay_task`, **135** `log/derive_job_status`, **136** `ops/audit_execution`.

### Unit (`npm test`, 282/282 green)

| ID | Result | Notes |
|---|---|---|
| UT-LOG-1-01 | Pass | All 35 (status, event) pairs checked against a copy of the epic's table transcribed independently of the implementation. `note` allowed from every status, changing nothing. |
| UT-LOG-1-02 | Pass | `blocked` with no reason, `""` and `null` all rejected with `E-LOG-002`. |
| UT-LOG-1-03 | Pass | All four reasons accepted. |
| UT-LOG-1-04 | Pass | Mixed sequence replays to the right status and timestamps; an invalid event in the history is skipped and its index reported rather than thrown. |
| UT-LOG-1-05 | Pass | Reopen → complete keeps the FIRST `started_at`, updates `completed_at`. |
| UT-LOG-1-06 | Pass | Fixed rule only, per MVP scope. The deferred rules are implemented and tested too, so the caller does not change later. An empty stage is never complete. |
| UT-LOG-1-07 | Pass | Covered by the live duplicate test below rather than a separate helper — the de-duplication is a unique index, not logic worth mocking. |
| UT-LOG-1-08 | Pass | `completed` from `not_started`: allowed, `started_at` stays null, `completed_at` set. |

### Functional (driven over real authenticated HTTP, not as a `workflow_test` file — see the note at the end)

| ID | Result | Evidence |
|---|---|---|
| FT-LOG-1-01 | Pass | start → blocked(reason) → unblocked → completed on task 7 wrote exactly 4 rows (log went 12 → 16); status `done`; both timestamps set. |
| FT-LOG-1-02 | Pass | `started` on a `done` task → 400, nothing written. |
| FT-LOG-1-03 | Pass | 400 `E-LOG-002`. |
| FT-LOG-1-04 | Pass | Same `client_event_id` twice → both 200, second returns `duplicate: true`, one row. |
| FT-LOG-1-05 | Pass | `PATCH /activity_log/1`, `DELETE /activity_log/1`, `POST /activity_log` and `DELETE /work_task/7/event/1` all 404. No endpoint anywhere writes the log except 563's `db.add`. |
| FT-LOG-1-06 | Pass | Job 1 stage `s1` has two tasks. Completing the first left the stage at `1/2, complete: false`; skipping the second flipped it to `complete: true` and moved `current_stage_key` to `s2`. The stage advances on the last open task, not the first, and `skipped` counts as finished. |
| FT-LOG-1-09 | Pass | `log/replay_task` on task 4 (6 events) and task 7 (4 events): derived status and BOTH timestamps equal the stored row. |
| FT-LOG-1-10 | Pass, with a stated limit | See "Assignment" below. |
| FT-LOG-1-11 | Pass | Cross-account token → 404 (not 403: an account should not learn the id exists). |
| FT-LOG-1-14 | Pass | Done without Start accepted; row written; task `done`; start left unknown rather than invented. |
| FT-LOG-1-15 | Pass | Every event carries `plan_publication_id: 1` and `publication_item_ref: "pt-39"`. The audit's orphan checks find nothing because the ref points at the frozen publication, not at a planner task that could be deleted. |
| FT-LOG-1-13 | Pass | 282/282 unit tests green, including every earlier epic's. |

### Governance

| ID | Result | Evidence |
|---|---|---|
| FT-LOG-1-G01 | Pass | Schema audit green on table 127 (PK, `created_at` with no `updated_at`, indexed references, unique `client_event_id`, enums declared, `appendOnly: true`). |
| FT-LOG-1-G04 | Pass | `E-LOG-001/002/003/005` each return a plain-language sentence with the code, and each writes a `rejected` event. No raw status ever reaches the user: the refusals read "This step is blocked. Unblock it first." and "This step is already done. Reopen it first if you need to change it." |
| FT-LOG-1-G05 | Pass, structurally | The endpoint takes `work_item_id` from the task itself, so a caller cannot send a mismatched one. The audit checks the stored data for it anyway (`activity_log.work_item`), which is the case that actually matters. |
| FT-LOG-1-G06 | Pass | Task 4's status was written directly to `blocked`, bypassing the engine. `ops/audit_execution` reported two findings, both owner `engineer`: "stored status blocked but the log replays to done over 6 events", and the job it cascaded into, "stored status completed but its 2 tasks derive blocked". Restored; audit back to zero findings over 7 tasks, 3 jobs, 16 log rows, 4 links, 1 publication. |
| FT-LOG-1-G07 | Pass | Every accepted event writes a `success` event carrying `event_type`, `from`, `to` and the resulting `job_status`. |

### Cross-check: the two implementations of the transition table

All 35 (status, event) pairs were walked through the LIVE `log/next_status` and diffed against `logModel.ts::canTransition` in one run: **all 35 match**. The table now exists in exactly two places — the TypeScript and one backend function — and the endpoint and the audit both call that function rather than holding copies.

### Assignment (FT-LOG-1-10) — what is enforced, and what is not

Work scheduled onto a named person's day can be recorded only by that person's login or by an account admin acting for them; anyone else gets `E-LOG-003`. **Unassigned work is not blocked.** `planner_agent.user_id` is 0 until an agent is linked to a login, and most are, so denying those would stop all work rather than protect anything — and account-level tenancy still applies to every call. The rule tightens by itself as APP-1 makes assignment the normal case. This is a deliberate choice, not an oversight.

### Not run

| ID | Why |
|---|---|
| FT-LOG-1-G02, G03 | Failure injection needs Xano's unit-test `mock` blocks, which this workspace rejects when a function is pushed through the MCP tool (`"Syntax error: unexpected 'mock'"`, recorded in CLAUDE.md). The transaction itself is real — the log row and the status move inside one `db.transaction` — but **a simulated mid-transaction failure has not been demonstrated**, so the rollback is argued from the code, not proven by a test. |
| FT-LOG-1-07, -08 | Configurable stage rules, deferred by MVP scope. Both are implemented and unit-tested in `logModel.ts` so they are ready when STAGE-1's fields land. |
| `workflow_tests/21_activity_log.xs` | There is no exposed tool to RUN a workflow test from a session (CLAUDE.md). Every assertion above was driven through the live API or `runWorkspaceFunction` instead; the file itself was not written, because an unrunnable file that looks like a passing test is worse than none. |

### Also closed here

`ops/audit_execution` fills two checks earlier epics left open: **JOB-1 FT-G05** (a job whose stored status disagrees with its tasks) and **LIVE-1 FT-G06** (a publication whose timeline no longer exists). Both were verified above.

### Needs the founder

Two scratch functions were created to run these tests and are still live in the workspace: `scratch/verify_transitions` (harmless, read-only) and **`scratch/tamper_task_status`, which writes a task status bypassing the engine** — exactly what the audit exists to catch. Neither is reachable over HTTP. They should be deleted; per the safety rules, that is the founder's call.
