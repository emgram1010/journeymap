# STAGE-1 — Stage Contract

**Epic ID:** STAGE-1
**Feature:** Every stage has a real owner and clear rules for when it is done.
**Status:** Planning
**Depends on:** OBS-1, GOV-1, VAL-1 (ROLE-1 is deferred)
**Goal:** A stage's owner becomes a real reference (not a text key), and a stage declares when it is finished and whether it runs back-to-back with the previous stage.

---

## MVP scope (after review, 2026-10-12)

| In the MVP | Deferred (post-MVP) |
|---|---|
| `owner_lens_id` (01, owner part only) · owner backfill (02) · owner validation in PATCH (03) · tool compatibility (04) · owner dropdown in the stage header (05) · **new** 06 "does planned work?" switch on each row | `exit_condition`, `completion_rule`, `continuous_with_previous` and their UI and tests |

In the MVP a stage is done when **all its work tasks are done or skipped** (fixed rule in LOG-1), and **every stage is its own scheduled item** (no blocks).

## Context

`journey_stage` today has `key`, `label`, `display_order`, `stage_goal` and `primary_actor_lens`, a **text key** such as `"lens-3"`, not a foreign key. A mistyped or renamed key breaks silently. In map 178, stages 1–4 and 7 are owned by `lens-2` (Customer) and stages 5, 6, 8 by `lens-3` (Sales Coordinator).

Execution needs three things the stage does not have: who owns it (reliably), when it counts as done, and whether it continues straight from the previous stage so the planner can show one block.

## Existing Architecture (Do Not Break)

- `static/tables/7_journey_stage.xs` — all current columns stay; new ones are additive.
- MCP/AI tool `update_stage_contract` (goal + owner) must keep working and now writes **both** the text key and the new reference.
- `stage_automation_config`, `journey_cell` rows keyed by `journey_stage` are untouched.

## Non-Goals

- No removal of `primary_actor_lens`. No automatic change of any owner. No per-stage SLA.

---

## Stories

### US-STAGE-1-01 — Additive columns

**File:** `static/tables/7_journey_stage.xs`

- `owner_lens_id → journey_lens` (nullable).
- `exit_condition` text (nullable) — one line saying when the stage is finished.
- `completion_rule` enum `all_required_done | any_done | manual`, default `all_required_done`.
- `continuous_with_previous` bool, default `false`.

**Acceptance:** existing stages load unchanged with defaults; no existing endpoint breaks.

### US-STAGE-1-02 — Resolve owners with a report (no silent changes)

- Backfill function: for each stage, resolve `primary_actor_lens` text key to a lens in the same map and set `owner_lens_id`. **Dry-run by default.**
- Output lists resolved stages and **unresolved** ones (key matches no lens) without modifying them.

**Acceptance:** map 178 clone resolves all 8 stages (`lens-2` → Customer, `lens-3` → Sales Coordinator); a deliberately broken key is reported, not fixed or crashed on; idempotent.

### US-STAGE-1-03 — Stage PATCH accepts the new fields

**File:** stage update endpoint under `apis/journey_map/`

- Accepts the four new fields. Validation:
  - `owner_lens_id` must belong to the **same map**.
  - `continuous_with_previous = true` is rejected on the **first** stage.
  - `completion_rule` must be one of the three values.
- Omitted fields are untouched; old payloads keep working.

**Acceptance:** each validation fails with a clear message; legacy payloads succeed.

### US-STAGE-1-04 — Keep `update_stage_contract` compatible

**File:** `ai/tool/update_stage_contract.xs` (and its skill text)

- Setting the owner writes both `primary_actor_lens` (text) and `owner_lens_id`.
- Reading returns both.

**Acceptance:** existing tool tests pass; after a tool call the two fields agree.

### US-STAGE-1-05 — Stage header controls

**Files:** `webapp/protype-2/src/App.tsx` (stage header component)

- Owner role dropdown (from the map's lenses, work-doing roles first), exit condition text, completion rule select (default shown), "Continues from previous stage" checkbox (hidden on the first stage).

**Acceptance:** changes persist and reload; checkbox absent on stage 1. *(MVP: owner dropdown only.)*

### US-STAGE-1-06 — "Does this row do planned work?" switch (MVP replacement for ROLE-1)

- Add `journey_lens.does_planned_work` (bool, nullable). When empty, the default comes from the row's type: **yes** for `internal` and `ai_agent`, **no** for every other type.
- The switch appears in the row header. Rows switched off (for example customers) never show required fields (AUTH-1).
- A stage's owner must be a row with planned work switched on (checked by readiness, not by PATCH).
- Existing paths that delete a row that owns a stage are blocked (GOV-1, US-GOV-1-10).

**Acceptance:** default by type works; the switch overrides it; map 178's Customer row defaults to **no** and its Sales Coordinator row to **yes**.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-STAGE-1-01 | Unit | `resolveOwner(key, lenses)` with a matching key | Returns the lens |
| UT-STAGE-1-02 | Unit | Key matches nothing / empty / null | Returns unresolved reason, no throw |
| UT-STAGE-1-03 | Unit | `canBeContinuous(stageIndex)` for index 0 and 1+ | false, true |
| UT-STAGE-1-04 | Unit | Completion-rule value guard | Rejects unknown values |
| FT-STAGE-1-01 | Functional (`workflow_tests/15_stage_contract.xs`) | Load a pre-existing map | New fields default (`all_required_done`, false, null) |
| FT-STAGE-1-02 | Functional | Backfill dry-run on map 178 clone | 8/8 resolved; nothing written |
| FT-STAGE-1-03 | Functional | Real backfill, then again | Second run no-op |
| FT-STAGE-1-04 | Functional | Stage with a bad key | Listed as unresolved; stage unchanged |
| FT-STAGE-1-05 | Functional | PATCH owner from a different map | Rejected |
| FT-STAGE-1-06 | Functional | PATCH `continuous_with_previous` on the first stage | Rejected |
| FT-STAGE-1-07 | Functional | Legacy PATCH payload (label only) | Succeeds, new fields untouched |
| FT-STAGE-1-08 | Functional | `update_stage_contract` tool, then read | Text key and reference agree |
| FT-STAGE-1-09 | Functional | Regression: workflow tests 1–9 | Green |
| E2E-STAGE-1-01 | UI | Set owner, exit condition, rule; reload | Persisted |
| E2E-STAGE-1-02 | UI | Stage 1 header | No "continues from previous" checkbox *(deferred)* |
| UT-STAGE-1-05 | Unit | `doesPlannedWork(lens)` with switch empty, true, false across types | Default by type; switch wins |
| FT-STAGE-1-10 | Functional | Set and clear the row switch | Persisted; default restored when cleared |
| E2E-STAGE-1-03 | UI | Toggle the row switch | Required tags appear/disappear for that row |

Tests for deferred fields (UT-STAGE-1-03, UT-STAGE-1-04, FT-STAGE-1-06, E2E-STAGE-1-02) run when those fields are built.

**Completion gate:** all pass; existing suites green.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity**

| Column | Relation / rule | Delete behaviour |
|---|---|---|
| `journey_stage.owner_lens_id` | `→ journey_lens` (indexed, nullable); must be a lens of the **same map** | A lens that owns a stage **cannot be deleted** until the stage is reassigned |
| `completion_rule` | Enum with a default | — |
| `exit_condition` | Text, ≤ 200 characters | — |
| `continuous_with_previous` | Bool, default false, never true on the first stage | — |

**Existing-table safety:** before adding uniqueness on `(journey_map, key)` and `(journey_map, display_order)`, run the GOV-1 duplicate audit on a clone; add the index only if the report is empty.

**Validation and friendly messages**

| Rule | Friendly message | Code |
|---|---|---|
| Owner must be a lens on this map | "Pick an owner from this map's rows." | `E-STAGE-001` |
| First stage cannot continue from a previous stage | "The first stage has nothing before it to continue from." | `E-STAGE-002` |
| Unknown completion rule | "Pick when this stage counts as done." | `E-STAGE-003` |
| Exit condition too long | "Keep this to one short sentence (200 characters)." | `E-STAGE-004` |
| Delete a lens that owns a stage | "This row owns stage '{stage}'. Choose a new owner for that stage first." | `E-STAGE-005` |

**Events logged** (`feature = STAGE-1`): `set_owner`, `set_contract`, `backfill_dry_run`, `backfill_run`, `tool_update_contract`; unresolved owners are logged as `rejected` findings, not errors.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-STAGE-1-G01 | Unit | Junk corpus through `exit_condition` | Rejected or normalised correctly |
| FT-STAGE-1-G01 | Functional | Duplicate audit with a seeded duplicate key | Reported; unique index not added |
| FT-STAGE-1-G02 | Functional | Delete an owning lens | Blocked with the message above |
| FT-STAGE-1-G03 | Functional | Every rejection above | Friendly message, Reference, event, nothing written |
| FT-STAGE-1-G04 | Functional | Integrity audit with an owner on another map | Detected |

## Test Results

_Not yet run._
