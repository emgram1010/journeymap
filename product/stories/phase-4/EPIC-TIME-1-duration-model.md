# TIME-1 — Duration Model

**Epic ID:** TIME-1
**Feature:** One consistent way to read "how long" everywhere.
**Status:** Planning
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

_Not yet run._
