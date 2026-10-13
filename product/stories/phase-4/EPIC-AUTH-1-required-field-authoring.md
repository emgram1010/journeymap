# AUTH-1 — Required-Field Authoring

**Epic ID:** AUTH-1
**Feature:** While building a journey map, the user can see exactly what is required, what is freeform, and what is still missing.
**Status:** Partial — readiness logic (01) done and tested; UI (02–06) deferred, see Test Results
**Depends on:** TIME-1, STAGE-1 (ROLE-1 and LEAN-1 are deferred)
**Goal:** Required structured fields live **in place** (map settings, stage header, cell panel), look different from freeform notes, and roll up into a per-stage ready mark, a map progress line and a checklist. The user never needs to know the tables.

---

## MVP scope (after review, 2026-10-12)

**Uses existing cell fields; no LEAN-1 migration** (D-37):

| Required item | Stored in (already exists) |
|---|---|
| Task | `journey_cell.actor_fields.task_objective` (written there for any work-doing row, whatever its template) |
| Done when (optional) | `journey_cell.actor_fields.success_criteria` |
| Duration | `journey_cell.time_duration_value` + `time_duration_unit` |
| Work-doing row | `journey_lens.does_planned_work` switch (STAGE-1, US-STAGE-1-06) |
| Stage owner | `journey_stage.owner_lens_id` (STAGE-1) |

Behaviour is behind the account flag `required_fields_ui` (GOV-1, US-GOV-1-12). Flag off = today's UI.

## Context

The journey-map UI is a matrix (stages as columns, actors as rows) with a cell detail panel and map settings. Today every cell field is free text, so a map can look "complete" while missing what Plan and Execution need.

## The MVP rule (what "ready" means)

- **Map:** has a work type name and at least one stage.
- **Each stage:** has a name and an **owner** row whose "does planned work?" switch is on.
- **Each stage's owner cell:** has a **task** and a **duration**.
- **Any other work-doing cell that has *anything* filled in** must also have task + duration (no half-filled work cells).
- **Customer-type (non-work) rows:** never required.
- Done-when is recommended, not required.

## Existing Architecture (Do Not Break)

- Matrix, cell panel and `cellPersistence` save path in `webapp/protype-2/src/App.tsx`, `cellPersistence.ts`.
- All other existing cell fields stay visible below, under "Notes (optional)".
- Behaviour is behind the `required_fields_ui` flag; flag off = today's UI.

## Non-Goals

- No input/output hand-off check (later). No backend gate here (PUB-1). No AI interview changes.

---

## Stories

### US-AUTH-1-01 — Readiness functions (pure)

**Files:** `webapp/protype-2/src/readiness.ts`, `readiness.test.ts`, `fixtures/readiness-golden.json`

- `computeStageReadiness(stage, lenses, cells)` → `{ ready, reasons[] }`.
- `computeMapReadiness(map, stages, ...)` → `{ readyCount, total, ready, perStage[], mapReasons[] }`.
- Reason codes: `NO_WORK_TYPE_NAME`, `NO_STAGES`, `NO_STAGE_NAME`, `NO_OWNER`, `OWNER_NOT_WORK_ROLE`, `NO_TASK`, `NO_DURATION`, `PARTIAL_WORK_CELL`.
- Uses TIME-1's validity rules for duration.

**Acceptance:** deterministic, no side effects, reasons are stable codes (never prose).

### US-AUTH-1-02 — Required tags and structured inputs in the cell panel

- Work-doing cells show **Task** (short text, required tag), **Duration** (number + unit picker, required tag), **Done when** (optional). Under them, a separate block labelled **"Notes (optional)"** for freeform.
- Customer-type cells show only the freeform context fields; no required tags.

**Acceptance:** required fields carry the tag; freeform sits visually separate; values persist through the existing save path.

### US-AUTH-1-03 — Stage header: name and owner role

- Stage header shows name and an owner dropdown listing this map's rows (rows that do planned work first). Picking a row with the switch off shows an inline note that the stage needs a work-doing owner.

**Acceptance:** owner is chosen from a list, never typed; selection persists.

### US-AUTH-1-04 — Ready mark per stage and progress line

- Each stage shows an empty circle (not ready) or a green check (ready).
- Top of the map: **"N of M stages ready"** plus the work type name field status.

**Acceptance:** updates immediately when a field changes; counts match `computeMapReadiness`.

### US-AUTH-1-05 — Checklist panel with jump links

- Panel lists every missing item in plain language ("Stage 4: no owner, no duration"), grouped by stage. Clicking an item scrolls to and focuses the field.

**Acceptance:** list is empty when everything is ready; each item focuses the correct field.

### US-AUTH-1-06 — Publish version button state

- Disabled while any blocker exists, with a visible reason ("3 stages not ready"); enabled when all are ready. (The action itself is PUB-1.)

**Acceptance:** button state always equals `computeMapReadiness.ready`.

---

## Test Plan

**Golden fixtures** (`readiness-golden.json`) include: fully ready map; missing owner; owner is a customer role; missing task; missing duration; half-filled non-owner work cell; empty map; map 178 snapshot (expected result: stages 1–4 and 7 report `OWNER_NOT_WORK_ROLE` until owners are corrected). The same file is used by PUB-1's backend tests.

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-AUTH-1-01 | Unit | Fully ready map | `ready = true`, no reasons |
| UT-AUTH-1-02 | Unit | Stage with no owner | `NO_OWNER` |
| UT-AUTH-1-03 | Unit | Owner row has "does planned work?" off | `OWNER_NOT_WORK_ROLE` |
| UT-AUTH-1-04 | Unit | Owner cell missing task | `NO_TASK` |
| UT-AUTH-1-05 | Unit | Owner cell has duration value but no unit | `NO_DURATION` |
| UT-AUTH-1-06 | Unit | Duration 0 minutes | Ready (0 is valid) |
| UT-AUTH-1-07 | Unit | Non-owner work cell with only notes filled | `PARTIAL_WORK_CELL` |
| UT-AUTH-1-08 | Unit | Non-owner work cell empty | No reason |
| UT-AUTH-1-09 | Unit | Customer-type cells empty or filled | Never required |
| UT-AUTH-1-10 | Unit | Zero stages / empty work type name | `NO_STAGES` / `NO_WORK_TYPE_NAME` |
| UT-AUTH-1-11 | Unit | `readyCount`/`total` over mixed stages | Correct counts |
| UT-AUTH-1-12 | Unit | Same input twice; input frozen | Same result; no mutation |
| UT-AUTH-1-13 | Unit | Map 178 golden | Stages 1–4, 7 `OWNER_NOT_WORK_ROLE` |
| E2E-AUTH-1-01 | UI | Required tags on Task and Duration; Notes labelled optional | Visible |
| E2E-AUTH-1-02 | UI | Fill a stage fully | Circle turns to green check; progress line increments |
| E2E-AUTH-1-03 | UI | Checklist item click | Focuses the missing field |
| E2E-AUTH-1-04 | UI | Customer-type row | No required tags |
| E2E-AUTH-1-05 | UI | Publish version button | Disabled with reason; enabled when all ready |
| E2E-AUTH-1-06 | UI | Flag off | Legacy UI unchanged; existing specs (`internal-actor`, `ai-agent-actor-fields`) green |

**Completion gate:** all pass; `npm test` and existing e2e green.

## Decision (resolved 2026-10-12, D-45)

**Which cells require task + duration?** The stage **owner's** cell, plus any other work-doing cell the user has started filling. The PRD (JM-10) uses the same rule.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity:** no new tables. This epic is the **front door** for the data defined in TIME-1, ROLE-1, STAGE-1 and LEAN-1, so it uses their field rules and never writes values the server would reject.

**Validation and friendly messages**

- The UI uses the shared VAL-1 rules: inline messages, a summary banner, submit disabled with a reason, **typing preserved** when a save fails.
- Save failures show: "We couldn't save your changes. Your work is still here. Reference: {ref}." and offer **Try again**.
- Concurrent edits: "Someone else changed this cell. Reload to see the latest." (GOV-1 concurrency standard).

| Situation | Code |
|---|---|
| Save failed (network) | `E-AUTH-001` |
| Save rejected by the server (field rule) | the field's own code |
| Someone else changed the cell | `E-AUTH-002` |
| Flag/permission prevents editing (locked cell) | `E-AUTH-003` |

**Events logged** (`feature = AUTH-1`, sent through the OBS-1 client helper): `cell_save` (`success`/`rejected`/`failure`), `readiness_computed` (info, sampled), `checklist_jump`.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-AUTH-1-G01 | Unit | Draft preservation reducer on save failure | Typed values kept |
| UT-AUTH-1-G02 | Unit | Readiness never reports ready when a field rule fails | True |
| E2E-AUTH-1-G01 | UI | Force a server failure on save | Friendly message with Reference; typing preserved; one `failure` event |
| E2E-AUTH-1-G02 | UI | Force a stale-write conflict | Reload prompt; no overwrite |
| E2E-AUTH-1-G03 | UI | Locked cell | Read-only with explanation |

## Test Results

**2026-10-13 — Sonnet 5 build pass. Logic built and tested locally; no Xano push needed (no new tables/endpoints — `required_fields_ui` flag already exists from GOV-1).**

### Done and verified

| Story | State | Evidence |
|---|---|---|
| 01 Readiness functions (pure) | ✅ | `webapp/protype-2/src/readiness.ts` — `computeStageReadiness`, `computeMapReadiness`, all 8 reason codes. Reuses TIME-1's `toMinutes` for duration validity and STAGE-1's `doesPlannedWork` for the owner/work-role check, rather than re-implementing either. 14 tests (`readiness.test.ts`) covering UT-AUTH-1-01 through 13, including the map 178 golden case: stages owned by the Customer lens (`lens-2`, `actor_type: customer`) correctly report `OWNER_NOT_WORK_ROLE`, stages owned by the Sales Coordinator (`lens-3`, `actor_type: internal`) correctly do not — read live from the real map via `getTableContentItem` to build the fixture, not guessed. |

### Deferred — and why

**US-AUTH-1-02 through 06 (all UI)** — required tags in the cell panel, the stage-header owner dropdown becoming the *required* control (US-STAGE-1-05 already wired the dropdown itself in STAGE-1), the per-stage ready mark, the map progress line, the checklist panel with jump links, and the Publish-version button's disabled state. None of this was built this pass.

**Why:** every one of these is a visual change to `App.tsx` / `StageEditPanel.tsx`, and this session has not started a dev server or used a browser tool at any point. This project's own standing rule (CLAUDE.md, and the general operating instructions) is to verify UI changes by running them in a browser before calling them done — not to type-check blind JSX edits and call that proof. Since the **logic** these UI pieces need to call (`computeStageReadiness`/`computeMapReadiness`) is now built, tested, and stable, wiring the UI is a lower-risk follow-up than building both at once — but it should be done with a running dev server, not blind.

**What's needed to pick this up:** `npm run dev`, then for each story: 02 (required tags + Notes-optional split in the cell panel, reading `actorFields.task_objective`/duration into `readiness.ts`'s cell shape), 03 (owner dropdown already exists from STAGE-1 — add the "needs a work-doing owner" inline note when a non-work row is picked), 04 (ready circle + "N of M stages ready" line calling `computeMapReadiness`), 05 (checklist panel iterating `perStage[].reasons`, with jump-to-field), 06 (disable the Publish-version button — itself still PUB-1's to build — when `computeMapReadiness(...).ready` is false). Tracked in `product/learning-fixes.md`.

Governance stories (UT-AUTH-1-G01/G02, E2E-AUTH-1-G01-G03) depend on the same deferred UI and are deferred with it.

`npm test`: 202/202 pass (188 prior + 14 new). `npm run lint`: same pre-existing, unrelated `e2e/chat-session-crud.spec.ts` failure, confirmed untouched by this epic.
