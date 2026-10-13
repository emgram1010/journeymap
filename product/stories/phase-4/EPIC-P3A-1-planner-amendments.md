# P3A-1 — Planner Amendments (history-safe planner)

**Epic ID:** P3A-1
**Feature:** The planner never destroys work history: plans, people and timelines with recorded work are archived or deactivated, not deleted.
**Status:** Planning
**Depends on:** — (apply **while building** phase-3 PLN-1, PLN-3, PLN-5, PLN-6, PLN-7, PLN-8)
**Goal:** Change the phase-3 planner design before it is built, so it fits phase-4: published plans and execution logs are permanent, and the columns phase-4 needs exist from the first schema push.

---

## Why (review finding F2, F8)

Phase-3 as written **hard-deletes** a workspace with all its children (PLN-3), deletes an agent's timelines (PLN-5) and deletes timelines (PLN-6). Phase-4 makes published plans and logs permanent (GOV-1, LIVE-1, LOG-1). Building phase-3 unchanged would break phase-4 or force a migration later.

## Rule

**Delete is allowed only while nothing has happened yet.** Once a plan, person or timeline has jobs, a publication or log events, it can only be **archived** (plan) or **deactivated** (person), and a published timeline can't be deleted.

## Existing Architecture (Do Not Break)

- All phase-3 behaviour for plans with **no** history stays exactly as specified (including cascade delete and returning tasks to backlog).
- Phase-3 tests stay valid for history-free data; new tests cover the history cases.

## Non-Goals

- No change to phase-3 ordering, timing or cost logic.

---

## Stories

### US-P3A-1-01 — Columns added in the first phase-3 push (amends PLN-1)

- `planner_workspace.is_archived` bool, default false.
- `planner_workspace.plan_template_id` nullable (reference added when PLAN-1's table exists; additive).
- `planner_agent.user_id → user` nullable, with unique `(workspace_id, user_id)` (one login per agent per plan). *(Moved here from APP-1 to remove a circular dependency with LIVE-1.)*
- `planner_agent.is_active` bool, default true.
- `planner_task.title` becomes nullable at schema level; the API requires it when the task is not linked to a job.
- `planner_task.tweak_reason` text, nullable.

**Acceptance:** phase-3 behaviour unchanged with defaults; schema audit (GOV-1) passes.

### US-P3A-1-02 — Plan (workspace) delete becomes archive when history exists (amends PLN-3)

- Delete allowed only if the workspace has no jobs, no publications and no log events; otherwise reject with "This plan has work recorded against it. Archive it instead." (`E-P3A-001`).
- Archive sets `is_archived = true`; archived plans are hidden from default lists and read-only.

**Acceptance:** history-free delete still cascades as in PLN-3; delete with history is blocked; archive works.

### US-P3A-1-03 — Agent delete becomes deactivate when history exists (amends PLN-5)

- Delete allowed only if the agent has no published timeline and no log events; otherwise reject with "{name} has recorded work. Deactivate them instead." (`E-P3A-002`).
- Deactivate sets `is_active = false`: hidden from the roster and from new assignments; history intact.

**Acceptance:** history-free delete follows PLN-5; with history it is blocked; deactivate works.

### US-P3A-1-04 — Published timelines can't be deleted (amends PLN-6)

- Delete of a timeline with `status = published` is rejected ("This timeline is live. It can't be deleted." `E-P3A-003`).
- `status` stays read-only in PLN-6 endpoints; only LIVE-1's publish endpoint changes it.

**Acceptance:** draft timelines behave as PLN-6; published ones are protected.

### US-P3A-1-05 — Task changes after publish are logged (amends PLN-7)

- Moving, adding, removing or re-timing a task on a **published** timeline is allowed for the planner and writes a `plan_change_log` row (LIVE-1).
- Log events never reference planner tasks directly (LOG-1 references the frozen publication item), so removing a planner task cannot break history.

**Acceptance:** post-publish edits produce change-log rows; no history row points to a deleted planner task.

### US-P3A-1-06 — Orphan audit covers phase-4 links (amends PLN-8)

- PLN-8's orphan audit also checks `planner_task_work_task`, `work_item.workspace_id`, `plan_publication.timeline_id` and `planner_agent.user_id`.

**Acceptance:** each seeded orphan is detected.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| FT-P3A-1-01 | Functional | Delete a plan with no history | Cascades as PLN-3 |
| FT-P3A-1-02 | Functional | Delete a plan with a job | Blocked (`E-P3A-001`); archive succeeds; hidden from default list |
| FT-P3A-1-03 | Functional | Delete an agent with no history | PLN-5 behaviour |
| FT-P3A-1-04 | Functional | Delete an agent with a published timeline | Blocked (`E-P3A-002`); deactivate succeeds |
| FT-P3A-1-05 | Functional | Delete a published timeline | Blocked (`E-P3A-003`) |
| FT-P3A-1-06 | Functional | Edit a task on a published timeline | Allowed; change-log row written |
| FT-P3A-1-07 | Functional | Two agents in one plan with the same `user_id` | Rejected |
| FT-P3A-1-08 | Functional | Seeded orphans across the new links | All detected |
| FT-P3A-1-09 | Functional | All original phase-3 tests on history-free data | Green |

Each rejection follows VAL-1 (friendly message, Reference) and OBS-1 (`rejected` event).

**Completion gate:** all pass alongside phase-3 tests.

## Test Results

_Not yet run._
