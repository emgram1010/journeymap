# PLN-8 — Integrity & Hydrated Read

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-06):** the orphan audit also covers the phase-4 links.

**Epic ID:** PLN-8
**Status:** Planning
**Depends on:** PLN-3, PLN-4, PLN-5, PLN-6, PLN-7
**Goal:** Prove CRUD propagation holds across all entities together, detect any orphan or invariant violation, and give the frontend a single call that loads a whole workspace.

---

## Context

Xano references are typed but do not enforce referential actions (see README). Epics 3–7 each test their own entity; this epic tests the **interactions** and adds the safety net. It also provides the read the frontend needs: today `loadStoredData()` returns everything at once, so the backend must offer an equivalent without N+1 calls.

## Existing Architecture (Do Not Break)

- Derived fields (labels, effective assignee, planned starts) come from the single implementations built in PLN-6/PLN-7. The hydrated read **reuses** them; it must not re-implement the math.

## Non-Goals

- No caching layer, no pagination (a workspace's plan is bounded by its planning window).
- No auto-repair of violations — the audit reports; a human decides.

## Endpoints / tasks

| Item | Purpose |
|---|---|
| `GET planner/workspace/{workspace_id}/board` | Hydrated read: workspace + agents + timelines + tasks + backlog |
| `GET planner/workspace/{workspace_id}/integrity` | Run the audit for one workspace (admin) |
| Scheduled task `tasks/planner_integrity_audit.xs` | Nightly audit across accounts; logs violations to `event_log` |

---

## Stories

### US-PLN-8-01 — Hydrated board read

- Returns `{workspace, agents[], timelines[], tasks[], settings, models[]}` using batched queries (one per table, filtered by `workspace_id`/`account_id`), joined in memory. Tasks carry derived `planned_start` and `effective_assignee`; timelines carry `label`, `agent_name`, `out_of_window`.
- Query count is constant regardless of data size (documented and asserted in the test by checking the count of `db.query` calls in the function).

**Acceptance:**
- A workspace with 4 agents, 14 timelines, 60 tasks loads in one request.
- Backlog tasks appear in `tasks[]` with `timeline_id: null` ordered by `seq`.
- Cross-account → `notfound`.

### US-PLN-8-02 — Integrity audit function

**File:** `functions/planner/integrity_audit.xs`

Checks (each returns offending ids):

| Code | Invariant |
|---|---|
| `ORPHAN_AGENT` | agent whose workspace is missing |
| `ORPHAN_TIMELINE` | timeline whose workspace or agent is missing |
| `ORPHAN_TASK` | task whose workspace is missing, or whose `timeline_id`/`assignee_agent_id` points nowhere |
| `CROSS_WORKSPACE_TASK` | task and its timeline (or assignee) in different workspaces |
| `CROSS_WORKSPACE_TIMELINE` | timeline and its agent in different workspaces |
| `SEQ_GAP_OR_DUP` | a container whose `seq` is not exactly `1..n` |
| `DUP_AGENT_DAY` | two timelines for one agent/date (should be impossible via the unique index; asserted anyway) |
| `PERSON_WITH_MODEL` | `kind = person` with a `model_id` |
| `MODEL_DANGLING` | agent `model_id` pointing at a missing model |
| `NON_DRAFT_STATUS` | timeline `status != draft` (publishing is on hold) |

**Acceptance:** On a clean dataset → empty result. Each code is triggered by a deliberately corrupted row in the test and reported with the right ids.

### US-PLN-8-03 — Scheduled audit task

**File:** `tasks/planner_integrity_audit.xs`

- Runs nightly, audits every account's planner data, writes one `event_log` row per violation code found (account, workspace, ids). Never mutates planner tables.

**Acceptance:** Clean data writes nothing; a seeded violation writes exactly one log row per code.

### US-PLN-8-04 — Cross-entity propagation suite

A single end-to-end scenario that exercises the whole delete/propagation table from the README against a seeded workspace, with the audit run **after every step**.

**Acceptance:** Audit stays clean after every step of the scenario (see FT-PLN-8-03).

### US-PLN-8-05 — Concurrency check

- Two simultaneous `place_task` calls into the same timeline, and two simultaneous creates for the same agent/day.

**Acceptance:** Exactly one timeline results; `seq` ends gapless (no duplicate positions) — or, if the platform cannot guarantee ordering under races, the limitation is documented in the epic with the mitigation (retry on audit failure) and a follow-up story is filed.

---

## Functional Test Plan

`workflow_tests/planner_8_integrity.xs`

| ID | Case | Expected |
|---|---|---|
| FT-PLN-8-01 | Hydrated read of a seeded workspace (4/14/60) | All rows present, derived fields correct, constant query count |
| FT-PLN-8-02 | Corrupt one row per audit code via `db.add`/`db.patch` | Each code reported with the right ids; clean rows not reported |
| FT-PLN-8-03 | Scenario, audit after each step: create ws → settings/models → 3 agents → timelines → tasks → move across agents → reorder → rename agent → change timeline start → delete task → delete timeline → delete AI agent → delete model (blocked, then allowed) → delete workspace | Audit clean after every step; final state: zero rows for the workspace in any planner table |
| FT-PLN-8-04 | Rename agent mid-scenario | Hydrated read shows new name everywhere; no timeline/task `updated_at` changed |
| FT-PLN-8-05 | Two accounts running the scenario in parallel | No cross-visibility; each audit clean |
| FT-PLN-8-06 | Concurrency cases (US-PLN-8-05) | Pass, or limitation documented + follow-up filed |
| FT-PLN-8-07 | Scheduled task on clean vs. corrupted data | No logs vs. one log per code |
| FT-PLN-8-08 | Audit endpoint as member | `accessdenied`; as admin → result |
| FT-PLN-8-09 | Unauthenticated calls | 401 |

**Completion gate:** all FT cases pass → record results → move to `completed-epics/`.

## Test Results

_Not yet run._
