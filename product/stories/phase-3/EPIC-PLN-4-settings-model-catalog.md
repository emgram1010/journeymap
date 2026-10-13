# PLN-4 — Settings & Model Catalog

**Epic ID:** PLN-4
**Status:** Planning
**Depends on:** PLN-1, PLN-2
**Goal:** Account-level cost rates (currency, human hourly rate) and a model pricing catalog that AI agents reference by foreign key.

---

## Context

Frontend: `SettingsModal.tsx`, `AppSettings` / `ModelPricing` in `types.ts`, `DEFAULT_MODELS` in `initialData.ts`, cost math in `utils/costUtils.ts`. Settings are global to the account (not per workspace); throughput is per workspace (PLN-3). Costs are **computed client-side from these values and never stored**.

## Existing Architecture (Do Not Break)

- `costUtils.ts` reads `humanHourlyRate`, `currencySymbol`, and model `inputPer1M`/`outputPer1M`. The API must return those values (camelCase mapping lives in the PLN-9 client).
- `humanHourlyRate` defaults to `0` so the UI never shows an invented rate.

## Non-Goals

- No per-agent hourly rates, no cost history, no currency conversion.

## Endpoints

| Verb | Path | Role |
|---|---|---|
| GET | `planner/settings` | any (lazily creates row + seeds models) |
| PATCH | `planner/settings` | admin |
| GET | `planner/model` | any |
| POST | `planner/model` | admin |
| PATCH | `planner/model/{model_id}` | admin |
| DELETE | `planner/model/{model_id}` | admin |

---

## Stories

### US-PLN-4-01 — Read settings (lazy create + seed)

- If the account has no `planner_settings` row, create it (`$`, rate `0`) and insert the four `DEFAULT_MODELS` as `planner_model` rows (`is_custom = false`) in one operation. Returns `{currency_symbol, human_hourly_rate, models[]}`.
- Idempotent: concurrent first calls must not create duplicates (the unique indexes from PLN-1 are the backstop; handle the conflict by re-reading).

**Acceptance:** First call seeds 4 models; second call creates nothing; two simultaneous first calls end with exactly one settings row and 4 models.

### US-PLN-4-02 — Update settings

- PATCH `currency_symbol` (1–3 chars), `human_hourly_rate` (decimal ≥ 0). Admin only (`assert_admin`).

**Acceptance:** Member → `accessdenied`; negative rate → `inputerror`; partial PATCH leaves the other field unchanged.

### US-PLN-4-03 — Create model

- Input `model_key` (required, unique per account, slug), `label`, `input_per_1m` ≥ 0, `output_per_1m` ≥ 0. Created rows are `is_custom = true`.

**Acceptance:** Duplicate key → `inputerror`; member → `accessdenied`.

### US-PLN-4-04 — Update model

- PATCH `label`, `input_per_1m`, `output_per_1m`. `model_key` is immutable once created.

**Acceptance:** Changing prices is reflected immediately in `GET planner/model`; attempting to change `model_key` → `inputerror`. Editing a seeded (non-custom) model is allowed (matches the UI note that every field is editable).

### US-PLN-4-05 — Delete model (guarded)

**File:** `functions/planner/delete_model_guard.xs`

- Blocked while any `planner_agent.model_id` references it: `inputerror` `"Model in use by N agent(s): <names>"`. Otherwise deletes.

**Acceptance:** Delete of an in-use model → blocked and lists agent names; after reassigning/removing those agents → succeeds. Cross-account id → `notfound`.

### US-PLN-4-06 — Reset to defaults (optional but specified)

- `POST planner/model/reset-defaults` (admin): restores any missing seed models and their default prices; never deletes custom models or in-use rows.

**Acceptance:** Deleting a seeded model then calling reset recreates it; custom models untouched.

---

## Functional Test Plan

`workflow_tests/planner_4_settings.xs`

| ID | Case | Expected |
|---|---|---|
| FT-PLN-4-01 | New account `GET settings` | 4 default models, rate 0, `$` |
| FT-PLN-4-02 | Call `GET settings` twice | Still 1 settings row, 4 models |
| FT-PLN-4-03 | Member PATCHes rate | `accessdenied` |
| FT-PLN-4-04 | Admin PATCHes rate to 85.5, symbol `€` | Persisted; next GET returns both |
| FT-PLN-4-05 | Negative rate / 4-char symbol | `inputerror` |
| FT-PLN-4-06 | Create custom model; duplicate key | OK then rejected |
| FT-PLN-4-07 | Edit seeded model price | Persisted |
| FT-PLN-4-08 | Delete model referenced by an AI agent | Blocked with agent names (needs an agent row inserted directly via `db.add`; PLN-5 not required) |
| FT-PLN-4-09 | Delete unreferenced model | Succeeds |
| FT-PLN-4-10 | Reset defaults after deleting a seed model | Recreated; custom untouched |
| FT-PLN-4-11 | Account B cannot read/modify account A's models | `notfound` |

**Completion gate:** all FT cases pass → record results → move to `completed-epics/`.

## Test Results

_Not yet run._
