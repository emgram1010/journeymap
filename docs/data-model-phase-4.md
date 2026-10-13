# Phase-4 data model and constraint matrix (GOV-1, US-GOV-1-02)

The human-readable half of the schema audit's manifest
(`webapp/protype-2/src/ops/schemaAudit.ts`). If you change one, change
the other: the manifest is what fails the build, this is what explains
why.

Standards referenced here (S1–S13) are defined in
[`data-standards.md`](./data-standards.md).

**Status key:** ✅ built and live · ⬜ not built yet (the epic that
creates it owns satisfying this row).

---

## Tables

| Table | Status | Owner epic | Keys and references | Unique on | Enums | Delete behaviour |
|---|---|---|---|---|---|---|
| `account_feature_flag` (108) | ✅ | GOV-1 | PK `id`; `account_id → account` (indexed) | `(account_id, flag_key)` | `flag_key` | **Cascade** with the account. A flag row has no history worth keeping. |
| `actor_role` | ⬜ | ROLE-1 *(deferred)* | PK `id`; `account_id → account` | `(account_id, name_key)` — see S6/US-GOV-1-11 | `actor_type` | **Restrict** if any lens or agent references it; **archive** instead. |
| `agent_role` | ⬜ | ROLE-1 *(deferred)* | PK `id`; `planner_agent_id`, `actor_role_id` (both indexed) | `(planner_agent_id, actor_role_id)` | — | **Cascade** when the agent goes; the role is archived, never deleted. |
| `journey_map_version` | ⬜ | PUB-1 | PK `id`; `journey_map_id` (indexed); `published_by → user` | `(journey_map_id, version_no)` | — | **Never deleted.** Immutable snapshot; archive the map instead. |
| `plan_template` | ⬜ | PLAN-1 | PK `id`; `account_id → account` | `(account_id, name_key)` | — | **Archive.** Instances are independent copies and are unaffected. |
| `plan_template_map` | ⬜ | PLAN-1 | PK `id`; `plan_template_id`, `journey_map_id` | `(plan_template_id, journey_map_id)` | — | **Cascade** with the template. |
| `planner_workspace_map` | ⬜ | PLAN-1 | PK `id`; `workspace_id`, `journey_map_id` | `(workspace_id, journey_map_id)` | — | **Cascade** with the plan instance. |
| `work_item` | ⬜ | JOB-1 | PK `id`; `account_id`; `workspace_id`; `journey_map_version_id`; `parent_work_item_id` (self) | — | `status` | **Cancel, never delete** once any task has log events. |
| `work_task` | ⬜ | JOB-1 | PK `id`; `work_item_id` (indexed) | `(work_item_id, stage_key, lens_key)` | `status` | Kept for history. Status changes only through the LOG-1 engine. |
| `planner_task_work_task` | ⬜ | SCHED-1 | PK `id`; `planner_task_id`, `work_task_id` | `(work_task_id)` — a task is scheduled at most once | — | **Cascade** with the planner task; the work task returns to backlog. |
| `plan_publication` | ⬜ | LIVE-1 | PK `id`; `timeline_id` (indexed); `published_by → user` | `(timeline_id)` | — | **Never updated or deleted.** Frozen snapshot. |
| `plan_change_log` | ⬜ | LIVE-1 | PK `id`; `timeline_id` (indexed); `changed_by → user` | — | `change_type` | **Append-only.** |
| `activity_log` | ⬜ | LOG-1 | PK `id`; `work_task_id`, `work_item_id` (indexed, must agree); `plan_publication_id` + `publication_item_ref` | `(client_event_id)` — duplicate-tap protection | `event_type`, `source` | **Append-only.** Retention may prune only closed jobs. |

### Additive columns on existing tables

| Column | Status | Owner epic | Note |
|---|---|---|---|
| `event_log.severity / outcome / feature / step / entity_type / entity_id / correlation_id / error_code / message / duration_ms` | ✅ | OBS-1 | Additive; existing writers unaffected. |
| `user.is_platform_admin` | ✅ | OBS-1 | Separate from the per-account `role`. No endpoint writes it. |
| `journey_stage.owner_lens_id`, `exit_condition`, `completion_rule`, `continuous_with_previous` | ⬜ | STAGE-1 | `owner_lens_id` replaces the fragile `primary_actor_lens` text key — the audit already finds **24 stages** where that key resolves to nothing. |
| `journey_lens.actor_role_id`, `does_planned_work` | ⬜ | STAGE-1 / ROLE-1 | The MVP uses the per-row switch; the role reference comes with ROLE-1. |
| `journey_cell.core_fields`, `core_schema_version` | ⬜ | LEAN-1 *(deferred)* | MVP uses the existing cell fields instead. |
| `planner_workspace.is_archived`, `plan_template_id` · `planner_agent.user_id`, `is_active` · `planner_task.tweak_reason`, nullable `title` | ⬜ | P3A-1 | Must land in phase-3's **first** push to avoid a later migration. |
| `workflow_execution.work_item_id` | ⬜ | JOB-1 | Nullable link; the AI run engine is otherwise untouched. |

> ⚠️ **Adding a column to an existing table that has validators will destroy them.** `updateTableSchema` silently drops `trim`/`lower`/password rules across the whole table. Do it in the Xano dashboard UI, or put the data in a new table. This is why feature flags became `account_feature_flag` rather than `account.feature_flags`.

---

## Rules the schema cannot enforce

Xano gives us primary keys, typed references, enums and indexes. It does
**not** enforce any of the following, so each one names the thing that does.

| Rule | Enforced by | Status |
|---|---|---|
| A referenced parent still exists (no orphans) | `ops/audit_integrity`, daily via `tasks/19_ops_integrity_audit.xs` | ✅ live — **currently reports 729 real orphans** |
| The caller owns what it is touching | `guards/assert_owns` | ✅ live |
| Two linked records share an account | `guards/assert_same_account` | ✅ live |
| An action is legal in the record's current state | `guards/assert_state` | ✅ live |
| Archived records are never written to | `guards/assert_not_archived` | ✅ live |
| A write does not overwrite someone else's | `guards/assert_fresh` | ✅ built, **not wired up** (S12 deferred) |
| Required fields are actually required | VAL-1 rules registry | ⬜ VAL-1 |
| Multi-row writes are all-or-nothing | `db.transaction` in each operation | ⬜ per-epic |
| Append-only tables are never updated or deleted | No update/delete endpoint exists + tests | ⬜ per-epic |
| A job's stored status matches its tasks | `ops/audit_integrity` (check to be added) | ⬜ JOB-1 |
| A work task's stage key exists in its pinned version | `ops/audit_integrity` (check to be added) | ⬜ JOB-1 |
| A publication's snapshot hash still matches | `ops/audit_integrity` (check to be added) | ⬜ LIVE-1 |
| Replaying a task's log agrees with its status | `ops/audit_integrity` (check to be added) | ⬜ LOG-1 |

**Each epic adds its own checks** to `ops/audit_integrity` as its tables
land. Do not retrofit them all at the end — a check written with the
table is a check that gets written.

---

## Current integrity findings (first run, 2026-10-13)

The audit's first run against live data, over 1,231 cells, 139 stages
and 163 lenses:

| Check | Count | What it means |
|---|---|---|
| `journey_cell.journey_map` | **577** | Cells still pointing at a deleted map |
| `journey_lens.journey_map` | **76** | Lenses still pointing at a deleted map |
| `journey_stage.journey_map` | **52** | Stages still pointing at a deleted map |
| `journey_stage.primary_actor_lens` | **24** | Stage owner key matching no lens in its map |
| `journey_cell.stage` / `journey_cell.lens` | 0 | Clean |

The first three are one problem: **deleting a journey map does not clean
up its children.** Nothing reads these rows, so they are not urgent, but
the delete path needs a guard (US-GOV-1-10) before the count grows. The
fourth is the text key STAGE-1 replaces — already broken in 24 places,
which is the argument for replacing it.
