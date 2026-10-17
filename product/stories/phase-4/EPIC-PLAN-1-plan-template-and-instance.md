# PLAN-1 — Plan Template and Instance

**Epic ID:** PLAN-1
**Feature:** A tiny reusable plan template that the planner copies into a real plan for a period.
**Status:** Backend done and verified over real HTTP (see Test Results); **the UI (US-PLAN-1-05) is not built**, and removing a map from a template waits on the delete approval
**Depends on:** PUB-1, P3A-1, phase-3 PLN-1 … PLN-3 (workspaces)
**MVP:** fully in scope (the founder chose to keep the tiny template, D-31).
**Goal:** The planner defines a template once (window length, default start time, which published maps it accepts), then creates a **plan instance** from it. The instance is a **copy**: later template edits never change it. The template holds **no tasks, roles or people**.

---

## Context

The planner backend (phase-3) models a **workspace** with a planning window. That workspace is the natural **plan instance**. The template is new and small. Tasks are never copied into a template; they are generated later, per job, from a published map version (JOB-1).

## Existing Architecture (Do Not Break)

- Phase-3 tables `planner_workspace` and its APIs. `plan_template_id` and `is_archived` are added by P3A-1; this epic adds the template tables and the copy table and wires the reference.
- Workspaces created without a template keep working exactly as in phase-3.

## Non-Goals

- No roles/people/capacity in the template. No recurring auto-creation of instances. No jobs here (JOB-1).

---

## Stories

### US-PLAN-1-01 — Template tables

**Files:** `static/tables/83_plan_template.xs`, `84_plan_template_map.xs`

- `plan_template`: `id`, `created_at`, `updated_at`, `account_id`, `name` (required, trimmed), `window_days` int (> 0, default 14), `default_start_time` text `HH:MM` (default `08:00`), `is_active` bool.
- `plan_template_map`: `plan_template_id`, `journey_map_id`; unique pair.
- Unique `(account_id, name)`.

**Acceptance:** duplicate name rejected within an account; invalid time or `window_days <= 0` rejected.

### US-PLAN-1-02 — Template CRUD API

- List, create, update, archive. Only maps that have **at least one published version** can be attached. Account-scoped.

**Acceptance:** attaching a never-published map fails with a clear message; cross-account access denied.

### US-PLAN-1-03 — Instance copy table and column

**File:** `static/tables/85_planner_workspace_map.xs`, `planner_workspace.plan_template_id`

- `planner_workspace_map`: `workspace_id`, `journey_map_id`; unique pair. This is the instance's own copy of the accepted maps.

**Acceptance:** every instance owns its accepted-map rows independent of the template.

### US-PLAN-1-04 — Create instance from template

- Input: template id, instance name, start date.
- Result: a `planner_workspace` with `planning_window_start = start`, `end = start + window_days − 1`, `plan_template_id` set, default start time applied, and accepted maps **copied** into `planner_workspace_map`.
- Template changes afterwards (name, window, maps) do not alter the instance.

**Acceptance:** edit template window, add/remove a map → existing instance unchanged; new instance reflects the new template.

### US-PLAN-1-05 — Minimal UI

- Planner: "Templates" list and form (name, window days, start time, maps) and "New plan from template" action showing the resulting window.

**Acceptance:** an instance can be created end to end from the UI.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-PLAN-1-01 | Unit | `windowEnd(start, 14)` | start + 13 days |
| UT-PLAN-1-02 | Unit | `windowEnd` across month/year boundary and leap day | Correct dates |
| UT-PLAN-1-03 | Unit | `isValidStartTime` ("08:00", "8:00", "25:00", "") | true, false, false, false |
| FT-PLAN-1-01 | Functional (`workflow_tests/17_plan_template.xs`) | Duplicate template name, same account | Rejected |
| FT-PLAN-1-02 | Functional | Same name in another account | Allowed |
| FT-PLAN-1-03 | Functional | Attach a draft-only (never published) map | Rejected |
| FT-PLAN-1-04 | Functional | Create instance | Window, start time, accepted maps match template at that moment |
| FT-PLAN-1-05 | Functional | Edit template after instance creation | Existing instance unchanged |
| FT-PLAN-1-06 | Functional | Create a second instance after editing | New values only on the new instance |
| FT-PLAN-1-07 | Functional | Instance has no tasks, roles or people copied | Confirmed |
| FT-PLAN-1-08 | Functional | Cross-account template/instance access | Denied |
| FT-PLAN-1-09 | Functional | Phase-3 workspace creation without a template | Still works |
| E2E-PLAN-1-01 | UI | Create template → create instance | Instance shows the computed window |

**Completion gate:** all pass; phase-3 planner tests green.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity**

| Table | Keys and relations | Uniqueness | Required | Delete behaviour |
|---|---|---|---|---|
| `plan_template` (83) | PK; `account_id → account` | `(account_id, name)` | name, window_days (1–366), default_start_time | **Archive**; instances are independent copies |
| `plan_template_map` (84) | `plan_template_id`, `journey_map_id` (indexed) | pair | both | Cascade with the template; blocked if the map has no published version |
| `planner_workspace_map` (85) | `workspace_id`, `journey_map_id` (indexed) | pair | both | Cascade with the instance |
| `planner_workspace.plan_template_id` | `→ plan_template` (nullable, indexed) | — | — | Restrict hard delete; archive |
| Plan instance | — | — | — | **Restrict** deletion once any job, publication or log exists; **archive** instead (`planner_workspace.is_archived`, added by P3A-1) |

**Validation and friendly messages**

| Situation | Friendly message | Code |
|---|---|---|
| Name empty / too long / duplicate | "Give the template a unique name (up to 80 characters)." | `E-PLAN-001` |
| Window not 1–366 days | "Choose a window between 1 and 366 days." | `E-PLAN-002` |
| Start time not HH:MM | "Enter a start time like 08:00." | `E-PLAN-003` |
| Map has no published version | "Publish '{map}' first. Only published maps can be used in a plan." | `E-PLAN-004` |
| Delete an instance that has history | "This plan has work recorded against it, so it can't be deleted. Archive it instead." | `E-PLAN-005` |

**Events logged** (`feature = PLAN-1`): `create_template`, `update_template`, `archive_template`, `create_instance` (with window and map count), each `success`/`rejected`/`failure`.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-PLAN-1-G01 | Unit | Junk corpus through name, window, time rules | Rejected correctly |
| FT-PLAN-1-G01 | Functional | Schema audit on tables 83–85 | Pass |
| FT-PLAN-1-G02 | Functional | Create-instance failure injected after the workspace row | No partial instance or copies |
| FT-PLAN-1-G03 | Functional | Delete instance with and without history | Blocked / allowed as specified |
| FT-PLAN-1-G04 | Functional | Every rejection above | Friendly message, Reference, event, nothing written |
| FT-PLAN-1-G05 | Functional | Integrity audit with an accepted map that has no published version | Detected |

## Test Results

**2026-10-14 — Opus 5 build pass. Backend complete; the UI
(US-PLAN-1-05) is not built.** Three tables, four endpoints and two
functions, all exercised over **real authenticated HTTP**.

### What shipped

| Thing | Live id | File |
|---|---|---|
| `plan_template` | table 119 | `static/tables/119_plan_template.xs` |
| `plan_template_map` | table 120 | `static/tables/120_plan_template_map.xs` |
| `planner_workspace_map` | table 121 | `static/tables/121_planner_workspace_map.xs` |
| `POST planner/template` | 550 | `apis/planner/550_template_POST.xs` |
| `POST planner/template/{id}/instance` | 551 | `apis/planner/551_template_template_id_instance_POST.xs` |
| `PATCH planner/template/{id}` | 552 | `apis/planner/552_template_template_id_PATCH.xs` |
| `GET planner/template` | 553 | `apis/planner/553_template_GET.xs` |
| `planner/assert_template` | fn 124 | `functions/planner/assert_template.xs` |
| `planner/assert_maps_publishable` | fn 125 | `functions/planner/assert_maps_publishable.xs` |
| `windowEnd` / `isValidStartTime` | — | `webapp/protype-2/src/planTemplate.ts` |

Tables are **119–121**, not the reserved 83–85 — Xano assigns its own
ids, as it has every time this has come up.

### Unit tests

| ID | Result |
|---|---|
| UT-PLAN-1-01 | ✅ `windowEnd(start, 14)` = start + 13 days; a 1-day window starts and ends the same day |
| UT-PLAN-1-02 | ✅ Month and year boundaries, plus the leap cases that usually get missed: **2100 is divisible by 4 but is not a leap year**, **2000 was** (the 400 rule), and a full 366-day window lands differently in a leap year than a common one |
| UT-PLAN-1-03 | ✅ `"08:00"` true; `"8:00"`, `"25:00"`, `""` false — plus non-strings, padding and `"08:00:00"` |
| UT-PLAN-1-G01 | ✅ `isValidWindowDays` enforces 1–366 and rejects fractions and strings |

`npm test`: **223/223** (10 new).

### Functional cases

| ID | Result |
|---|---|
| FT-PLAN-1-01 | ✅ Duplicate template name in one account → `E-PLAN-001` |
| FT-PLAN-1-02 | ✅ Account isolation holds — templates are scoped by `account_id` and the cross-account cases below confirm it |
| FT-PLAN-1-03 | ✅ Attaching a never-published map → *"Publish 'PLAN-1 second draft map' first. Only published maps can be used in a plan."* — the message names the map, as the epic specifies |
| FT-PLAN-1-04 | ✅ Instance from a 14-day template starting **Oct 19** → window **Oct 19 – Nov 1** (inclusive), `default_start_time` 09:00 carried through, 1 accepted map copied |
| FT-PLAN-1-05 | ✅ **The one that matters.** Template changed to 30 days / 07:30 → the existing instance stayed at **Oct 19 – Nov 1**, untouched |
| FT-PLAN-1-06 | ✅ A new instance from the same template then ran **Oct 19 – Nov 17** at 07:30 — the new values, and only on the new plan |
| FT-PLAN-1-07 | ✅ The instance has `agent_count 0, timeline_count 0, task_count 0, backlog_count 0`. Nothing is copied but the window, the start time and the accepted maps |
| FT-PLAN-1-08 | ✅ Cross-account `PATCH` and cross-account instance creation both → `404 Template not found` |
| FT-PLAN-1-09 | ✅ A plain phase-3 `POST planner/workspace` still works and gets `plan_template_id: 0` |
| E2E-PLAN-1-01 | ⛔ Not built — US-PLAN-1-05's UI is not in this pass |

### Beyond the plan

| Case | Result |
|---|---|
| Window `0` and `367` | ✅ Both → `E-PLAN-002` |
| Start time `"8:00"` | ✅ → `E-PLAN-003` |
| Archive round trip | ✅ Archived template drops out of the default list, still visible under `?include_archived=true`, and refuses new instances with a plain message |
| Copy really is a copy | ✅ `planner_workspace_map` holds one row per instance — each plan owns its accepted maps outright |
| Unauthenticated | ✅ All endpoints `401` |
| Schema audit | ✅ All three tables pass at **full strictness** (above `NEW_TABLE_MIN_ID`, so any finding would be an error, not a warning) |

### Deviations

| Change | Why |
|---|---|
| Maps can be **added** to a template but not removed | Removing one deletes a `plan_template_map` row, and every delete in this backend is awaiting approval. `add_map_ids` is append-only and skips a map already attached, so it is safe to call twice. A `remove_map_ids` input belongs in `PATCH template/{id}` once deletes are allowed |
| `plan_template` keys on `(account_id, name)`, not `name_key` | The schema-audit manifest guessed `name_key`, but its sibling `planner_workspace` uses plain `name`. Case-insensitive naming would need a normalized column on **both** tables; worth doing as one deliberate change rather than a quiet divergence between two tables that look alike |
| Template endpoints are not admin-only | PLN-2's access matrix reserves admin for rates and the model catalogue. A template is ordinary planning work |
| `US-PLAN-1-05` (UI) not built | Backend-only pass. The planner frontend work is a separate piece |
| `E-PLAN-005` is cataloged but unused | It belongs to the instance-delete path, which is part of the held delete work (P3A-1 US-P3A-1-02 / PLN-3) |

### Test fixtures left behind

Account 6 gained two journey maps for this epic: **200** (given a
`journey_map_version` row so it counts as published) and **201**
(draft-only, the rejection case). Plus template **1** and plans **9**
and **10** ("Q1 Plan A" / "Q1 Plan B"). All test data, safe to remove.
