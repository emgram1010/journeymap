# Phase 4 — MVP Foundation: Journey Map → Plan → Execution

**Status:** Planning (nothing built). Revised 2026-10-12 after an independent review (findings F1–F22, decisions D-37–D-46 in the PRD).
**Source of truth for the vision:** `product/emgramprd.md` (read §0 first).
**Rule:** one epic = one feature. Every epic has unit (`UT-`), functional (`FT-`) and, where there is UI, Playwright (`E2E-`) tests, **plus a Governance section** (data integrity, validation and friendly errors, events logged). Each epic also has an **MVP scope** block saying what is in and what is deferred. An epic is done only when its in-scope tests pass **and the existing suites stay green**.

## Goal

- Turn a journey map into real, trackable work: **define → plan → publish to live → execute → log → variance**.
- Generic for any kind of work; simple for users (five required fields); reality captured from taps, not reports.
- Solid data, no silent failures, and supportable by a non-engineer through a Health page.

## The simple picture

```
TEMPLATE (journey map)  →  JOB (a real copy)  →  LOG
task + stages + who + how long   goes through the stages   start / end / status / blocked reason
```

## MVP minimum a journey map must produce (uses existing fields)

| Required | Stored in |
|---|---|
| Work type name | `journey_map.title` (not empty or a default) |
| Stage name and order | `journey_stage.label`, `display_order` |
| Stage owner | `journey_stage.owner_lens_id` (STAGE-1), a row whose "does planned work?" switch is on |
| Task | `journey_cell.actor_fields.task_objective` |
| Expected duration | `journey_cell.time_duration_value` + `time_duration_unit` |
| Done when *(optional)* | `journey_cell.actor_fields.success_criteria` |

## MVP build order

> **Status as of 2026-10-15.** Steps 0–13 are built. Everything
> through LOG-1 is live and verified over real authenticated HTTP:
> a journey map becomes a version, a plan, a job, scheduled work, a
> published day, and finally a record of what actually happened.
>
> **The whole backend loop closes.** What is missing is the screens:
> PLAN-1, JOB-1, SCHED-1, LIVE-1 and LOG-1 all shipped backend-only.
> APP-1 (step 14) is the first UI of the execution half.
>
> **Eight things are written but NOT pushed or NOT deleted, waiting
> on the founder** — five delete paths, one nightly job and two
> scratch functions. They are listed in one table at the top of
> `product/learning-fixes.md`. Nothing else blocks the next epic.

| # | Epic (feature) | Depends on | MVP delivers | Model |
|---|---|---|---|---|
| 0 | [P3A-1 Planner amendments](EPIC-P3A-1-planner-amendments.md) | applied while building phase-3 | History-safe planner: archive/deactivate instead of delete; phase-4 columns in the first push | Sonnet, then Opus review |
| 1 | [OBS-1 Observability and heartbeat](EPIC-OBS-1-observability-and-heartbeat.md) | — | Success/failure events, error catalog, admin-only Health page, Copy diagnostic bundle | Sonnet |
| 2 | [GOV-1 Data integrity governance](EPIC-GOV-1-data-integrity-governance.md) | 1 | Standards, guards (including existing delete paths), transactions, schema and integrity audits, feature flags | **Opus** |
| 3 | [VAL-1 Input validation and friendly errors](EPIC-VAL-1-input-validation-and-friendly-errors.md) | 1 | Junk never stored; clear messages; typing preserved | Sonnet (Haiku for the junk-input list) |
| 4 | [TIME-1 Duration model](EPIC-TIME-1-duration-model.md) | 1–3 | One minutes conversion | Sonnet (Haiku for fixtures) |
| 5 | [STAGE-1 Stage contract](EPIC-STAGE-1-stage-contract.md) | 1–3 | Real stage owner; "does planned work?" switch per row | Sonnet |
| 6 | [AUTH-1 Required-field authoring](EPIC-AUTH-1-required-field-authoring.md) | 4, 5 | Required vs. freeform on existing fields; ready marks, progress, checklist | Sonnet |
| 7 | [PUB-1 Publish version](EPIC-PUB-1-publish-version.md) | 6 | One gate; one immutable version table | **Opus** |
| 8 | Phase-3 PLN-1 … PLN-8 (with P3A-1) ✅ | — | Planner backend — **done**, except the held deletes | Sonnet (Opus review of PLN-2 tenancy and PLN-8 integrity) |
| 9 | [PLAN-1 Plan template and instance](EPIC-PLAN-1-plan-template-and-instance.md) ✅ | 7, 8 | Tiny template copied into instances — **backend done**, UI not built | Sonnet |
| 10 | [JOB-1 Jobs and tasks](EPIC-JOB-1-jobs-and-tasks.md) ✅ | 9 | Jobs pinned to a version; tasks generated and hydrated — **backend done**, no UI | Sonnet |
| 11 | [SCHED-1 Scheduling and tweaks](EPIC-SCHED-1-scheduling-and-tweaks.md) ✅ | 10 | One scheduled item per task; per-job duration tweak — **done except the two deletes** | Sonnet |
| 12 | [LIVE-1 Publish to live](EPIC-LIVE-1-publish-to-live.md) ✅ | 11 | Per-timeline frozen snapshot; planner changes logged after — **MVP core done**, no bulk publish, no UI | Sonnet, then Opus review |
| 13 | [LOG-1 Activity log and status engine](EPIC-LOG-1-activity-log-and-status-engine.md) ✅ | 10, 12 | Append-only log; fixed statuses; Done allowed without Start — **done**, no UI; failure-injection tests not runnable here | **Opus** |
| 14 | [APP-1 Performer app](EPIC-APP-1-performer-app.md) ← **next** | 12, 13 | Today's items; one-tap actions | Sonnet |
| 15 | [VAR-1 Variance and outliers](EPIC-VAR-1-variance-and-outliers.md) | 13 | Per-task expected/scheduled/actual; outlier flag | Sonnet |
| 16 | [E2E-1 End-to-end validation](EPIC-E2E-1-end-to-end-validation.md) | all | Whole loop; integrity audit; supportability demo | Sonnet, then Opus final review |

**Model column:** the AI announces the model at the start of each epic and asks you to switch if needed (`/model sonnet`, `/model opus`, `/model haiku`). Any bug that fails twice → switch to Opus.

## Deferred (post-MVP)

| Item | Where it is described |
|---|---|
| Actor role registry (MVP uses the per-row switch) | [ROLE-1](EPIC-ROLE-1-actor-role-registry.md) |
| Lean cell core migration (`EPIC-LEAN-1`; file currently missing; MVP uses existing fields) | PRD §13 |
| Exit condition, configurable completion rules, continuous stages and blocks | STAGE-1, SCHED-1 |
| Role-based assignment suggestions | SCHED-1 |
| Bulk publish to live | LIVE-1 |
| Stale-map detection | PUB-1 |
| Issue acknowledgement, AI diagnostic tool, retention tiers | OBS-1 |
| Duplicate audit + unique indexes on existing tables; stale-write standard | GOV-1 |
| Stage aggregates, planner-tweak signal, variance panel, window adherence | VAR-1 |
| Offline performer app, AI-proposed improvements, capacity, automated sequencing | PRD §11 |

## Governance in one page (applies to every epic)

| Area | Rule | Where it lives |
|---|---|---|
| Database | Primary keys, declared and indexed references, unique natural keys (normalized `name_key` where case-insensitive), enums, no duplicate facts, explicit delete behaviour, append-only history, atomic writes (`db.transaction`) | GOV-1 |
| Input | The UI helps; the server always re-checks. Junk is rejected with a plain message and the user's typing is kept | VAL-1 |
| Visibility | Every important step records a success or failure event with a code and a Reference the user can quote | OBS-1 |
| Support | The founder (platform admin) opens the **Health page**, sees what broke in plain English and who can fix it, and copies a bundle for the AI | OBS-1 |

## If something breaks (for the product manager)

1. Open the **Health page** (admins only). Red or amber means look here first.
2. Each problem says **what happened**, **who can fix it** (user, you, or an engineer/AI) and a **suggested fix**.
3. If it needs an engineer or the AI, click **Copy diagnostic bundle** and paste it. It contains the story of what happened and no private data.
4. A user can quote the **Reference** shown in any error message; search it on the Health page to see the whole timeline.

## New tables

> **The numbers below are a record, not a reservation (corrected 2026-10-14).**
> Xano assigns table ids on creation and ignores whatever a plan asks for —
> STAGE-1 asked for 109 and got 110/111, PUB-1 asked for 82 and got 112,
> PLN-1 asked for 74–79 and got 113–118. Record the id Xano gives and name
> the local file after it. See `product/learning-fixes.md`.

| # | Table | Epic | MVP? |
|---|---|---|---|
| 80 | `actor_role` | ROLE-1 | Deferred (number reserved) |
| 81 | `agent_role` | ROLE-1 | Deferred (number reserved) |
| ~~82~~ **112** | `journey_map_version` | PUB-1 | Built 2026-10-14 — Xano auto-assigns table ids, so the reserved 82 was not used (see `static/tables/112_journey_map_version.xs`) |
| 83 | `plan_template` | PLAN-1 | Yes |
| 84 | `plan_template_map` | PLAN-1 | Yes |
| 85 | `planner_workspace_map` | PLAN-1 | Yes |
| 86 | `work_item` | JOB-1 | Yes |
| 87 | `work_task` | JOB-1 | Yes |
| 88 | `planner_task_work_task` | SCHED-1 | Yes |
| 89 | `plan_publication` | LIVE-1 | Yes |
| 90 | `plan_change_log` | LIVE-1 | Yes |
| 91 | `activity_log` | LOG-1 | Yes |
| 92 | `ops_issue_ack` | OBS-1 | Deferred (number reserved) |

**Additive columns (MVP):** `event_log` observability columns (OBS-1); `user.is_platform_admin` (OBS-1); `planner_workspace.is_archived`, `plan_template_id`, `planner_agent.user_id`, `is_active`, `planner_task.tweak_reason`, nullable `planner_task.title` (P3A-1); `workflow_execution.work_item_id` (JOB-1).

**Additive via new table instead of a column, deliberate (confirmed `updateTableSchema` drops `trim`/`lower` validators on every other column of the table — see CLAUDE.md):** `account_feature_flag` instead of `account.feature_flags` (GOV-1, table 108); `journey_stage_owner` instead of `journey_stage.owner_lens_id` and `journey_lens_planned_work` instead of `journey_lens.does_planned_work` (STAGE-1, tables 110–111).

## Existing, overlapping initiative

`product/validation-publish-execution/` (planned, not built) is **not edited**. Decisions (D-39): one publish gate (our MVP rules plus title; their stricter gates later, only for atomic/automation maps, using their `gate_failures[]` shape); one version table (`journey_map_version`, linked to `automation_snapshot`); one log and one status list (LOG-1); their plan-vs-actual thresholds reused in VAR-1. AI-run gates, validator row and novel exceptions are deferred.

## Test conventions

- **Unit:** `node --test` + tsx in `webapp/protype-2/src/*.test.ts`; add each new file to the `npm test` script in `webapp/protype-2/package.json`.
- **Functional:** Xano `workflow_test` files in `workflow_tests/`, numbered from **13**: TIME-1 = 13, ROLE-1 = 14, STAGE-1 = 15, PUB-1 = 16, PLAN-1 = 17, JOB-1 = 18, SCHED-1 = 19, LIVE-1 = 20, LOG-1 = 21, APP-1 = 22, VAR-1 = 23, E2E-1 = 24, OBS-1 = 25, GOV-1 = 26, VAL-1 = 27. (10–12 are reserved for LEAN-1.)
- **Failure simulation:** Xano unit-test mocks only; no test switches in production endpoints.
- **UI:** Playwright specs in `webapp/protype-2/e2e/`.
- **Golden fixtures:** shared JSON used by both frontend and backend where the same rule exists on both sides (duration, readiness, validation).
- **Schema audit:** `scripts/audit-schema.mjs` runs with `npm test` and fails on a non-compliant new table.
- **Regression gate:** `npm test`, `workflow_tests/1–9` (the ones that exist today), every new workflow test once added, and existing e2e specs stay green on every epic.
- **Real data:** map **178** (`leads-to-sales-baseline`) is the realistic fixture. Test against a **clone**, never the original.
