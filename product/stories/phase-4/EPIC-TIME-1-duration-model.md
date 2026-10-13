# TIME-1 — Duration Model

**Epic ID:** TIME-1
**Feature:** One consistent way to read "how long" everywhere.
**Status:** Done (see Test Results)
**Depends on:** OBS-1, GOV-1, VAL-1
**MVP:** fully in scope.
**Goal:** Every layer (map, plan, execution, variance) turns a cell's duration into **minutes** with the same rule, and everyone knows what the existing `actual_duration` column means.

---

## Context

`journey_cell` already stores duration as `time_duration_value` + `time_duration_unit` (minutes / hours / days / weeks), used by the leakage formula. It also has `planned_duration` and `actual_duration`, where `actual_duration` means *what the operator says happens today* (an observed baseline), **not** an execution actual. Plan and Execution need one minutes figure, so the conversion must be defined once and tested on both sides.

## Existing Architecture (Do Not Break)

- `static/tables/9_journey_cell.xs` — columns stay exactly as they are. No rename, no delete.
- Leakage math (`calculate_leakage`) keeps reading the existing columns unchanged.
- LEAN-1's virtual `duration_minutes` projects through this epic's function.

## Non-Goals

- No new stored duration field. No column rename. No change to leakage formulas.
- No per-account configurable workday length (constant for now).

---

## Stories

### US-TIME-1-01 — Canonical conversion function (frontend)

**File:** `webapp/protype-2/src/durationModel.ts`, `durationModel.test.ts`

- Export `WORKDAY_MINUTES = 480` and `toMinutes(value, unit)`.
- Rules: minutes ×1; hours ×60; days ×`WORKDAY_MINUTES`; weeks ×5×`WORKDAY_MINUTES`.
- Result is rounded **half-up to a whole minute**. `null`, `undefined`, negative, non-numeric, or unknown unit → `null` (never throws, never guesses).

**Acceptance:**
- Pure function; same input → same output.
- Fractions are supported (`0.5` hours = 30).

### US-TIME-1-02 — Matching backend function

**File:** `functions/duration_to_minutes.xs`

- Same rules, same constant, same rounding.
- Used by the version snapshot (PUB-1) and job generation (JOB-1).

**Acceptance:** produces identical results to the frontend for every golden fixture.

### US-TIME-1-03 — Document the meaning of `actual_duration`

- Journey-map UI label for `actual_duration` becomes **"Observed today"** (display text only).
- Execution never writes to `actual_duration`. Execution actuals live only in the activity log (LOG-1).

**Acceptance:** a code search finds no execution path that writes `journey_cell.actual_duration`; label change shows in the cell panel.

### US-TIME-1-04 — Input validation

- Duration value must be a number ≥ 0 (or empty). Unit must be one of the four enum values. Value without a unit (or unit without a value) is flagged as incomplete, not silently accepted.

**Acceptance:** invalid input is rejected by the cell PATCH endpoint with a clear message; valid and empty values are unchanged from today.

---

## Test Plan

**Golden fixtures:** `webapp/protype-2/src/fixtures/duration-golden.json` (value, unit → expected minutes), shared with the backend test.

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-TIME-1-01 | Unit | 15 minutes | 15 |
| UT-TIME-1-02 | Unit | 2 hours | 120 |
| UT-TIME-1-03 | Unit | 1 day | 480 |
| UT-TIME-1-04 | Unit | 1 week | 2400 |
| UT-TIME-1-05 | Unit | 0.5 hours | 30 |
| UT-TIME-1-06 | Unit | 1.5 minutes | 2 (half-up) |
| UT-TIME-1-07 | Unit | 0 minutes | 0 (valid, not null) |
| UT-TIME-1-08 | Unit | `null`, `undefined`, `""` | null |
| UT-TIME-1-09 | Unit | -5 minutes | null |
| UT-TIME-1-10 | Unit | unit `"fortnights"` | null |
| UT-TIME-1-11 | Unit | value `"abc"` | null |
| FT-TIME-1-01 | Functional (`workflow_tests/13_duration_model.xs`) | Backend function over every golden fixture | Equals the frontend expectations |
| FT-TIME-1-02 | Functional | PATCH cell with value `-1` | Rejected |
| FT-TIME-1-03 | Functional | PATCH cell with valid value and unit | Persisted; existing leakage result for map 178 clone unchanged |
| FT-TIME-1-04 | Functional | Automated search test over backend and app code: no execution path writes `actual_duration` | Pass (fails if one is added) |
| E2E-TIME-1-01 | UI | Cell panel shows "Observed today" label | Visible |

**Completion gate:** all cases pass, `npm test` and `workflow_tests/1–9` still green → record under Test Results.

## Governance (data integrity, validation, observability)

Follows GOV-1 standards, VAL-1 rules and OBS-1 events.

**Data integrity:** no new tables or columns. Existing duration columns stay optional but are validated as a pair (value and unit together, or both empty).

**Validation and friendly messages**

| Field | Rule | Friendly message | Code |
|---|---|---|---|
| Duration value | Number ≥ 0, up to 4 digits, decimals allowed | "Enter how long this takes as a number, like 15." | `E-TIME-001` |
| Duration unit | One of minutes, hours, days, weeks | "Pick a unit: minutes, hours, days or weeks." | `E-TIME-002` |
| Value without unit (or unit without value) | Both or neither | "Add both a number and a unit, or leave both empty." | `E-TIME-003` |

**Events logged** (`feature = TIME-1`): `duration_save` as `success` or `rejected` (with code); conversion errors never throw, they return empty.

**Governance tests**

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-TIME-1-G01 | Unit | Junk corpus through the duration rules | All junk rejected, valid values pass |
| FT-TIME-1-G01 | Functional | Rejected save | 422 with the friendly message, Reference, `rejected` event, nothing written |
| FT-TIME-1-G02 | Functional | Successful save | `success` event |

## Test Results

**2026-10-13 — Sonnet 5 build pass. Built, pushed to Xano workspace 1, smoke-tested.**

### Done and verified

| Story | State | Evidence |
|---|---|---|
| 01 canonical conversion (frontend) | ✅ | `durationModel.ts` — `toMinutes()` + `WORKDAY_MINUTES = 480`. 15 unit tests, all pass locally (`UT-TIME-1-01`…`11` + edge cases). |
| 02 matching backend function | ✅ live | `functions/duration_to_minutes.xs` (id 83). Pushed, smoke-tested via `runWorkspaceFunction` against all 13 golden-fixture-equivalent cases — **all matched the frontend exactly on the first push**, no bugs found, because the `has_X`-flag and filter-order lessons from OBS-1/GOV-1/VAL-1 were applied proactively before writing. |
| FT-TIME-1-01 (golden fixtures) | ✅ | `webapp/protype-2/src/fixtures/duration-golden.json`, 13 cases, run through both `toMinutes()` (frontend test) and `duration_to_minutes` (manual `runWorkspaceFunction` smoke test). Equal on both sides. |
| 03 document `actual_duration`'s meaning | ✅ | `StageEditPanel.tsx` label changed to **"Observed today"** with an explanatory comment. `FT-TIME-1-04` (see below) makes "no execution path writes it" an enforced tripwire rather than a one-time code search. |
| 04 input validation on the cell PATCH | ✅ live | `apis/journey_map/44_journey_cell_update_journey_cell_id_PATCH.xs` (api 44) — pushed, parses clean. `time_duration_value`/`planned_duration`/`actual_duration` must be ≥ 0 when the caller actually sent that key (checked via `$raw_input|has:"..."`, not the input value — an omitted decimal arrives as `0`, not `null`, same trap as VAL-1's `max_length`). A duration value sent without a unit, or vice versa, is rejected (`E-TIME-003`). An invalid unit is already rejected by the enum input type before the stack runs, so `E-TIME-002` needed no explicit check. |
| Error catalog | ✅ | `E-TIME-001/002/003` added to `webapp/protype-2/src/ops/errorCatalog.json`. Not synced to `functions/ops/error_catalog.xs` — see deviation note below. |

### Real bugs found

None this pass. Both backend pieces (`duration_to_minutes`, the PATCH validation) were written with the `has_X`-flag pattern and documented filter syntax (`|has:`, confirmed against the docs' `{'fizz':'buzz'}|has:'fizz'` example) applied from the start, instead of discovered after a failed push.

### Not verified: the PATCH endpoint's validation, end-to-end

`44_journey_cell_update_journey_cell_id_PATCH.xs` pushed with no parse error, and the `|has:` filter is a simple, documented object-key check (not the nested-indexing pattern that broke `array.map` in OBS-1) — but there is still no tool in this session that can make a real authenticated HTTP call, so the four new preconditions were never exercised against a live request. Same category as VAL-1's `ops/feature_flag`. Tracked in `product/learning-fixes.md`.

### Deviation from the epic, deliberate

Backend error-catalog sync (`functions/ops/error_catalog.xs`) was **not** extended with `E-TIME-*`. That file's own header says only OBS-1's codes live there, and GOV-1/VAL-1 already followed the same precedent for their own codes — it's read only by `build_diagnostic_bundle`/`group_issues` to annotate `event_log` rows, not by every feature's validation path. Adding TIME-1's would have been inconsistent with the two epics immediately before it, not a fix.

### FT-TIME-1-04, how it actually works

Rather than a one-time grep, it's a standing unit test (`durationModel.test.ts`) that walks every `.ts`/`.tsx` file under `webapp/protype-2/src` and fails if any file outside a fixed allowlist (`App.tsx`, `StageEditPanel.tsx`, `types.ts`, `xano.ts`, itself) references `actual_duration`/`actualDuration`. It passes today because no execution module exists yet; it is designed to fail the day LOG-1/APP-1 start writing to this column, forcing that to be a conscious decision.

### Deferred — and why

`FT-TIME-1-02`/`FT-TIME-1-03` (PATCH with invalid/valid duration against real data) and `E2E-TIME-1-01` (UI label visible in a browser) need either the missing authenticated-HTTP tool or a running dev server with a logged-in session — neither available this session. `UT-TIME-1-G01` (junk corpus through the duration rules) was not built as a separate suite; `durationModel.test.ts`'s existing edge cases (`-5`, `"abc"`, `"fortnights"`, empty/null/undefined) already cover the same ground as VAL-1's junk-corpus pattern for this one field shape, so a second corpus run was judged redundant rather than skipped by oversight.

`npm test`: 184/184 pass (168 prior + 16 new). `npm run lint`: pre-existing, unrelated failure in `e2e/chat-session-crud.spec.ts` (confirmed via `git log` — untouched by this epic, not introduced here).
