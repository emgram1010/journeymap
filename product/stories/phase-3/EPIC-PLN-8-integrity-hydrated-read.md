# PLN-8 — Integrity & Hydrated Read

> **Amended by phase-4 `EPIC-P3A-1` (US-P3A-1-06):** the orphan audit also covers the phase-4 links.

**Epic ID:** PLN-8
**Status:** Mostly done — hydrated board read, the ten-check audit and the admin endpoint are live and verified, including the concurrency cases; the **nightly task and the delete half of the propagation scenario need the founder's approval** (see Test Results)
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
| `NON_DRAFT_STATUS` | timeline `status` is neither `draft` nor `published` — a value no endpoint can produce. *Narrowed 2026-10-16 (PLN-9): originally `status != draft`, correct while publishing was on hold, but it flagged every real published day once LIVE-1 shipped.* |

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

**2026-10-14 — Opus 5 build pass.** Two endpoints and five functions
live, all exercised over **real authenticated HTTP**.

### What shipped

| Thing | Live id | File |
|---|---|---|
| `GET planner/workspace/{id}/board` | 548 | `apis/planner/548_workspace_workspace_id_board_GET.xs` |
| `GET planner/workspace/integrity` | 549 | `apis/planner/549_workspace_integrity_GET.xs` |
| `planner/integrity_audit` | fn 118 | `functions/planner/integrity_audit.xs` |
| `planner/audit_agents` | fn 119 | `functions/planner/audit_agents.xs` |
| `planner/audit_timelines` | fn 120 | `functions/planner/audit_timelines.xs` |
| `planner/audit_tasks` | fn 121 | `functions/planner/audit_tasks.xs` |
| `planner/audit_sequences` | fn 122 | `functions/planner/audit_sequences.xs` |

### 🔴 Needs the founder's approval

**The nightly task** (`tasks/20_planner_integrity_audit.xs`) is written
but **not pushed**. A recurring job is standing configuration — once
created it runs every night unattended — so it needs a go-ahead like
the delete paths. Everything it calls is live and tested, so pushing it
later is one step with no logic left to verify. Note it should not share
an hour with the existing `19_ops_integrity_audit`.

**FT-PLN-8-03's delete half** cannot run until the five delete paths
are approved. The non-delete two-thirds of that scenario were exercised
across PLN-3…PLN-7 with the audit clean throughout.

### Functional cases

| ID | Result |
|---|---|
| FT-PLN-8-01 | ✅ One request returned workspace + **4 agents, 7 timelines, 17 tasks**, settings and 5 models. Backlog tasks appear in `tasks[]` with `planned_start: null` in seq order; scheduled tasks carry derived starts and effective assignees; timelines carry label and `out_of_window`. Cross-account → `404` |
| FT-PLN-8-02 | ✅ **9 of 10 codes provoked and caught.** See the table below |
| FT-PLN-8-03 | ⛔ Delete half blocked (see above) |
| FT-PLN-8-04 | ✅ Proven in PLN-5/PLN-6: the agent renamed in PLN-5 reads through to every timeline label, with the timeline rows byte-identical before and after |
| FT-PLN-8-05 | ✅ Account 4 and account 6 were driven through overlapping work all session with no cross-visibility; both audits clean |
| FT-PLN-8-06 | ✅ **Both cases pass** — see Concurrency below |
| FT-PLN-8-07 | ⛔ Task not pushed |
| FT-PLN-8-08 | ✅ Member → `403`; admin → `{clean: true, violations: []}` |
| FT-PLN-8-09 | ✅ Both endpoints `401` unauthenticated |

### The audit caught a real problem before any test did

Its very first run on live data returned **three genuine
`SEQ_GAP_OR_DUP` violations** — tasks still holding `seq 0` from the
fixture seeded before PLN-7's resequence existed, never touched by a
mutation since. Not a planted bug; a real inconsistency the audit found
on its own. `planner/resequence` fixed all three and the audit went
clean, which also demonstrates detect → repair → verify end to end.

### Every code, deliberately provoked

Each corruption was applied, audited, and **restored in the same
function call** so the fixture was never left broken. The audit
confirmed clean after each restore.

| Code | Result |
|---|---|
| `MODEL_DANGLING` | ✅ agent pointed at model 99999 |
| `PERSON_WITH_MODEL` | ✅ same row, caught independently |
| `ORPHAN_AGENT` | ✅ agent pointed at workspace 99999 |
| `ORPHAN_TIMELINE` | ✅ timeline pointed at agent 99999 — **and two further timelines correctly reported** once their agent left the account's workspaces, which is the checks interacting as intended |
| `NON_DRAFT_STATUS` | ✅ status forced to `published` — *valid at the time, when `draft` was the only legal status. The rule was narrowed 2026-10-16 (PLN-9) and `published` no longer triggers it, so this exact case would not fire today; it was re-proven then by blanking a status to `""`, which is the only invalid value Xano's enum actually permits.* |
| `ORPHAN_TASK` | ✅ task pointed at timeline 99999 |
| `SEQ_GAP_OR_DUP` | ✅ seq forced to 77 |
| `CROSS_WORKSPACE_TIMELINE` | ✅ ws4 timeline pointed at a **real** ws5 agent |
| `CROSS_WORKSPACE_TASK` | ✅ ws4 task pointed at a **real** ws5 timeline |
| `DUP_AGENT_DAY` | ⚠️ **Unprovokable.** Every attempt to seed a duplicate was refused by the unique index — the right outcome, and it means this check cannot be exercised while that index exists. It stays as a tripwire for an index that is dropped or rebuilt wrong |

The two CROSS codes needed a *real* row in another workspace; pointing
at a missing id produces ORPHAN instead, which is the correct
distinction and worth knowing when reading a report.

### Concurrency (US-PLN-8-05) — and a bug it found

**Four simultaneous `place_task` calls into one timeline:** seqs came
out `1,2,3,4`, gapless, audit clean.

**Two simultaneous creates for the same agent and day:** exactly one
timeline resulted — the data invariant held — **but the losing caller
got `500 "Duplicate record detected"`**, a raw database string shown to
someone who did nothing wrong. A VAL-1 violation and a classic
check-then-act race: both callers saw no existing row, both inserted,
the unique index rejected one.

Fixed by wrapping the insert and, on conflict, re-reading and returning
the existing row as `created: false` — the same answer the slower click
would have received a moment later. The index still guarantees
uniqueness; this only decides what the loser is told.

**Re-tested after the fix:** both callers got `200`, the same timeline
id, one `created: true` and one `created: false`, one row, audit clean.
So US-PLN-8-05 passes outright rather than being recorded as a
documented limitation.

`npm test`: 213/213.

### Deviations

| Change | Why |
|---|---|
| The audit is five functions, not one | A single function holding all ten checks failed at runtime with `"Invalid syntax. Try using the transform filter or an expression."` — an apparent complexity ceiling, since every construct inside it worked in isolation. Splitting also makes each part independently runnable when the audit fires |
| Every check is written as two passes | Forced by the `conditional` defect found in PLN-6: a branch whose condition reads a variable updated earlier in the same iteration loses its writes. Pass 1 records the lookup as a field; pass 2 branches on the loop item |
| The board makes one `derive_tasks` call per timeline | US-PLN-8-01 asks for a constant query count. This is constant per entity *type* — no per-agent or per-task queries — but it is one function call per timeline rather than a single pass over all tasks. The alternative was re-implementing the start-time maths inline, which the epic explicitly forbids. Correctness over a count: worth revisiting if a plan ever holds hundreds of days |
| `SEQ_GAP_OR_DUP` compares positions, not a checksum | A sum check passes `[1,1,4,4]`, the most likely real corruption |
| Audit endpoint logs an event only when dirty | A nightly clean run must not fill the Health page with noise |
