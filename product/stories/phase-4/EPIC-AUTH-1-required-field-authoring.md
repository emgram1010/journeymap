# AUTH-1 — Required-Field Authoring

**Epic ID:** AUTH-1
**Feature:** While building a journey map, the user can see exactly what is required, what is freeform, and what is still missing.
**Status:** Done (see Test Results) — logic (01) and UI (02–06) built and live-verified in a real browser session
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

### 2026-10-14 — UI build pass (02–06), live-verified with a real dev server + browser

Built with `npm run dev` running and a real Chrome session driving it end to end (registered a disposable test account, built a scratch journey map, exercised every control), per the project's own standing rule that UI changes must be seen rendering, not just type-checked.

| Story | State | Evidence |
|---|---|---|
| 02 Required tags + Notes split | ✅ | Cell detail panel: work-doing cells show Task/Duration with a red "Required" tag and a "Done when" optional field, pinned above the per-template fields; Notes label changes to "Notes (optional)". Hidden entirely for non-work rows (verified: a structural row with no actor type shows neither the tags nor the toggle). |
| 03 Stage header owner + inline note | ✅ | Owner dropdown (from STAGE-1) now shows an amber inline warning when the selected lens doesn't do planned work — verified live both ways (switching to a non-work owner shows it, switching to a work-doing owner clears it). |
| 04 Ready mark + progress line | ✅ | Green check / grey circle renders in each stage header (`jm-stage-ready-mark`); "N of M stages ready" chip in the matrix toolbar updates live. Verified going from 0/8 → 1/8 after filling one stage's owner cell. |
| 05 Checklist panel | ✅ | Slide-out panel lists every unready stage with plain-language reasons (`READINESS_REASON_COPY`); clicking a stage with an owner/name problem opens Edit Stage, clicking one with only a task/duration problem selects the owner's cell — both verified live. |
| 06 Publish-version button state | ✅ (state only — the action itself is PUB-1) | Button is disabled with a reason tooltip until `computeMapReadiness(...).ready`, styled black/enabled only when true. Clicking it shows a stub notice that the real gate is PUB-1's to build. |

**Real bugs found and fixed while live-testing** (all pre-existing, from TIME-1/STAGE-1 — this is the first time these paths were ever exercised against a running server):

1. **Stage ownership never reached readiness at all.** `journey_stage` has no `owner_lens_id` column (STAGE-1 put it in a side table, `journey_stage_owner`, to dodge the `updateTableSchema` validator bug) — but the plain `GET /journey_stage` list endpoint used to hydrate the whole map never joined it, so `Stage.ownerLensId` was always null no matter what the dropdown showed. Fixed by adding a dedicated `GET /journey_stage_owner` endpoint (api 519) and a client-side fetch (`listJourneyStageOwners`) that merges the real value in, plus fixing `handleStageDetailsSave` to read the owner back from the PATCH response (`updated.owner_lens_id`) instead of never touching it. Same fix shape as the existing `journey_lens_planned_work` pattern.
2. **Duration unit silently saved as `""` instead of `"minutes"`.** A never-touched cell's `time_duration_unit` comes back as an empty string (not null) from the backend's enum column default. Code that computed a display fallback with `?? 'minutes'` never caught it (`??` only falls through on null/undefined, not `""`), so the `<select>` visually showed "minutes" (the browser's fallback for an unmatched value) while the real state stayed `""` and silently failed the backend's pairing precondition / readiness's duration check. Fixed in both the new cell-panel duration picker and the pre-existing `StageEditPanel` by switching to `|| 'minutes'`.
3. **Stage-owner save threw a real error whenever duration fields were 0.** `handleStageDetailsSave` always sent `time_duration_unit` alongside `plannedDuration`/`actualDuration` whenever any of the three was non-null — but a freshly-created cell's duration fields default to `0` (not null) at the DB level, so `hasDurationUpdate` fired on *every* owner save, sending a duration unit with no paired value and tripping api 44's pairing precondition (`E-TIME-003`). Fixed by only sending the unit paired with an actual non-null value.
4. **"Has this cell been touched" logic was wrong.** `cellHasAnyContent` treated a non-null `timeDurationValue` as evidence the cell was started — but since duration defaults to `0` (not null) for every cell, this flagged *every untouched work cell in the entire map* as `PARTIAL_WORK_CELL`. Fixed by dropping the duration check from that function; only real task/content/actor-field text is a reliable "touched" signal.
5. **The planned-work toggle showed on structural/non-actor rows** (e.g. a map's default "Description" row). Caught by the founder reviewing the live session, not by me — "does planned work" is an actor-role concept and a row with no actor type isn't an actor at all. Fixed by only rendering the toggle (and only resolving the override) when the lens has an `actorType` set.

**New backend endpoints** (both read-only GET-all, additive, no schema changes): `GET /journey_lens_planned_work` (api 518) and `GET /journey_stage_owner` (api 519), workspace 1, apigroup 4.

**Still open, not blocking:** the Internal Employee template's own field list repeats "Task / Objective" below the new required Task field (same underlying key, shown twice) — cosmetic, not incorrect, tracked in `product/learning-fixes.md`.

`npm test`: 202/202 pass. `npm run lint`: same pre-existing, unrelated `e2e/chat-session-crud.spec.ts` failure, confirmed untouched by this epic.

Governance stories (UT-AUTH-1-G01/G02, E2E-AUTH-1-G01-G03) remain deferred — they need a forced-failure/conflict harness this pass didn't build.
