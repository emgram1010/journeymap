# PLN-4 — Settings & Model Catalog

**Epic ID:** PLN-4
**Status:** Partially done — settings and the model catalogue are live and verified over real HTTP; **model delete (US-PLN-4-05) needs the founder's approval** (see Test Results)
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

**2026-10-14 — Opus 5 build pass. Partially complete: everything except
model delete.** Six endpoints live, all exercised over **real
authenticated HTTP** as three different users (a fresh admin, an
existing admin, and a member) to prove the role and tenancy rules
rather than assume them.

### What shipped

| Endpoint | Live id | File |
|---|---|---|
| `GET planner/settings` | 528 | `apis/planner/528_settings_GET.xs` |
| `PATCH planner/settings` | 529 | `apis/planner/529_settings_PATCH.xs` |
| `GET planner/model` | 530 | `apis/planner/530_model_GET.xs` |
| `POST planner/model` | 531 | `apis/planner/531_model_POST.xs` |
| `PATCH planner/model/{id}` | 532 | `apis/planner/532_model_model_id_PATCH.xs` |
| `POST planner/model/reset-defaults` | 533 | `apis/planner/533_model_reset_defaults_POST.xs` |
| `planner/assert_model` | fn 113 | `functions/planner/assert_model.xs` |

### 🔴 Not done: model delete needs the founder's approval

`DELETE planner/model/{model_id}` and `planner/delete_model_guard` were
**written but not pushed**, for the same reason as PLN-3's cascade:
CLAUDE.md requires approval before any delete, and the push was
independently refused. The guard is in
`functions/planner/delete_model_guard.xs` for review — it names the
agents still using a model rather than just saying "in use", which is
what PLN-1's `planner_agent(model_id)` btree was added for.

**This blocks FT-PLN-4-08 and FT-PLN-4-09.**

### Fixtures used

| User | Account | Role | Used for |
|---|---|---|---|
| 7 | 4 (fresh) | admin | The lazy-seed path — account 4 had never opened the planner |
| 9 | 6 | admin | Reset-defaults on an account whose defaults were missing |
| 6 | 3 | member | Every admin-only rejection |

### Functional cases

| ID | Result |
|---|---|
| FT-PLN-4-01 | ✅ Fresh account's first `GET settings` → 4 default models at 10/50, 5/25, 2/10, 1/5, all `is_custom false`, rate `0`, symbol `$` |
| FT-PLN-4-02 | ✅ Second call → still 4 models, still one settings row. Nothing created |
| FT-PLN-4-03 | ✅ Member PATCHing the rate → `403`, *"Only account admins can change planner rates and models"* |
| FT-PLN-4-04 | ✅ Admin set `85.5` / `€`; the next GET returned both |
| FT-PLN-4-05 | ✅ Negative rate → `E-PLN-003`; 4-character symbol → `E-VAL-002` |
| FT-PLN-4-06 | ✅ Custom model created (`is_custom true`); duplicate key rejected with `E-PLN-004` |
| FT-PLN-4-07 | ✅ Seeded model's price edited to 99/123 and persisted — editing a built-in model is allowed, as the story requires |
| FT-PLN-4-08 | ⛔ Blocked — see above |
| FT-PLN-4-09 | ⛔ Blocked |
| FT-PLN-4-10 | ✅ **Both halves.** On account 4 (all defaults present, one repriced) reset returned `repriced: [all four]`, restored opus to 5/25, and left **both** custom models untouched. On account 6 (defaults missing) it returned `recreated: [all four]` and left the unrelated stray model alone |
| FT-PLN-4-11 | ✅ `GET model` as the member returned only account 3's rows; `PATCH` on another account's model → `404 Model not found`, identical to a nonexistent id |

### Beyond the plan

| Case | Result |
|---|---|
| `is_custom` cannot be forced from the client | ✅ Posting `is_custom: false` still produced a custom row. Without this, a client could make a model vanish on the next reset |
| Model ids are case-insensitive | ✅ `"My-Custom-Model"` was stored as `my-custom-model`, and a later `"my-custom-model"` was caught as a duplicate. The `lower` filter does this, not a second check |
| `model_key` is immutable | ✅ Changing it → `E-PLN-005`. Sending the **same** key alongside other edits is accepted, so a UI echoing the whole object back is not punished |
| Bad slug rejected | ✅ `"Has Spaces!"` → `E-VAL-004` |
| Member cannot create a model or reset defaults | ✅ Both `403` |
| Partial settings PATCH | ✅ Changing only the rate left `€` in place |

`npm test`: 213/213 — including the catalog lint, now widened to scan
`apis/planner` and `functions/planner`, so PLN-4's five new codes
(`E-PLN-003` … `E-PLN-006`) had to be cataloged before this passed.

### A bug found by the first live test

**The lazy seed keyed off the wrong thing.** The first version seeded
only when the account had **zero models**. Account 6 happened to hold
one stray model row from a PLN-1 tenancy test, so it got a settings row
and *no defaults at all* — a state nothing would have recovered from
except a manual fix.

Rewritten to key off the absence of the **settings row**, which is what
US-PLN-4-01 actually says, with each default insert wrapped so a
pre-existing key is swallowed rather than blocking the other three.
Verified afterwards on a genuinely fresh account (4), and account 6 was
repaired through `reset-defaults` — which is exactly the situation that
endpoint exists for.

### Deviations

| Change | Why |
|---|---|
| Added `planner/assert_model` | PLN-2 built guards for workspace/agent/timeline/task but not model. Rather than inline the tenancy check in two endpoints, it follows the same pattern. `planner_model` hangs straight off `account`, so it needs no workspace hop |
| `GET planner/model` does **not** lazily seed | Only `GET settings` creates anything, so there is one seeding path to reason about. An account that has never opened the planner gets `[]` here |
| Four new error codes, not in the epic | `E-PLN-003` (negative number), `E-PLN-004` (duplicate model id), `E-PLN-005` (id is immutable), `E-PLN-006` (model in use). The epic specifies the behaviours but names no codes; VAL-1 requires every user-facing message to have one |
| Currency symbol limited to 3 characters | US-PLN-4-02 says 1–3 chars. Enforced with `E-VAL-002` |
