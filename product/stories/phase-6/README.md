# Phase 6 — The Item Rate Framework (intelligence layer first)

**Status:** Planning (nothing built). Drafted 2026-10-24 from `product/learnings/item-rate-framework-prd.md`.
**Source of truth for the design:** that PRD. Read its §0 and §10 first. Vision: `product/emgramprd.md` §0.
**Rule:** one epic = one feature. Every epic has unit (`UT-`), functional (`FT-`) and, where there is UI, Playwright (`E2E-`) tests, **plus a Governance section** and an **MVP scope** block. An epic is done only when its in-scope tests pass **and the existing suites stay green**.

## Goal

- A journey map can say, per stage, *does time scale with what's in the job, and at what rate per thing*.
- An order can say *what's in it*.
- One function turns the two into a real per-stage estimate — replacing the hardcoded `30` — with an honest "incomplete" flag.
- Nothing built here is thrown away when planning and execution pick it up (PRD §8).

## The simple picture

```
MAP (formula)                    ORDER (counts)                 ESTIMATE
Items row: per stage,            20 x chair, 3 x table    →     baseline + Σ(qty × rate)
  per-order / per-unit,                                          per stage, with complete/missing
  minutes per item per method
```

## MVP build order

| # | Epic (feature) | Depends on | MVP delivers | Model |
|---|---|---|---|---|
| 0 | [ITEM-0 Step-0 audit](EPIC-ITEM-0-step-zero-audit.md) | — | Proof that a non-actor row is safe everywhere; hash coverage confirmed; guard tests that fail if a future change treats the Items row as an actor | **Opus** |
| 1 | [CAT-1 Catalogs: items and methods](EPIC-CAT-1-item-and-method-catalog.md) | 0 | `item_type` and `method` tables, CRUD, a small settings screen | Sonnet (Haiku for the junk-input list) |
| 2 | [ITEM-1 The Items row](EPIC-ITEM-1-items-row.md) | 0, 1 | One Items row per map; which items it uses; the Items cell editor (scaling, method, minutes per item) | Sonnet |
| 3 | [RATE-1 Publish the rate card](EPIC-RATE-1-publish-rates.md) | 2, phase-4 PUB-1 | `stage_rate` materialized at publish; snapshot + hash schema v2 on both sides; old versions still verify | **Opus** |
| 4 | [EST-1 Order lines and the estimate](EPIC-EST-1-order-lines-and-estimate.md) | 3, phase-4 JOB-1 | `work_item_line`; `estimate_job`; planner cards get the real number or baseline + "incomplete" | Sonnet, then Opus review |
| — | [Queued: planning and execution](QUEUED-planning-and-execution.md) | 4 | Design stubs for PLN-M-1 and EXE-M-1 so phase-6 leaves the right hooks. Not built in phase-6. | — |

**Model column:** the AI announces the model at the start of each epic and asks you to switch if needed (`/model sonnet`, `/model opus`, `/model haiku`). Any bug that fails twice → switch to Opus. After RATE-1 (Opus-marked), an Opus review pass before EST-1.

## New tables

> **Numbers are a record, not a reservation.** Xano assigns ids on creation (see phase-4 README). Record the id Xano gives and name the local file after it.

| local # | Table | Epic | Notes |
|---|---|---|---|
| 135 | `method` | CAT-1 | Account catalog of ways-of-doing; optional sub-journey, optional role. PUSHED — Xano assigned 135, not 136 as first drafted |
| 136 | `item_type` | CAT-1 | Account catalog of countable things. PUSHED — Xano assigned 136, not 135 as first drafted |
| (TBD) | `journey_lens_item` | ITEM-1 | Which items a map's Items row uses. Side table — `journey_lens` has trim validators |
| 138 | `stage_rate` | RATE-1 | Published, version-pinned rate card. Written only by publish. PUSHED — Xano assigned 138 |
| (TBD) | `work_item_line` | EST-1 | The counts on a job |

**Existing tables touched:** none structurally. The Items row is a `journey_lens` with `template_key = "items-v1"`; its cells are `journey_cell.actor_fields` under that template. `journey_lens_planned_work` gets a `false` row for every Items row. `journey_map_version.snapshot` gains two sections under `schema_version = 2`.

## Existing, overlapping initiative

`product/validation-publish-execution/` is **not edited**. RATE-1 extends PUB-1's single gate and single version table (D-39); it does not add a second gate or a second snapshot.

## Deferred (post-phase-6)

| Item | Where |
|---|---|
| One card per (order, stage, method-with-role); guess/measured badge; capacity view | QUEUED → PLN-M-1 |
| Lines-by-method on the performer's task; `flagged_quantity`; clean-read learning | QUEUED → EXE-M-1 |
| `notes` / `requirements` fields on item lines (`items-v2` template) | PRD D-IR-18 |
| Non-item quantity keys (stairs, miles, stops) | PRD D-IR-14/15 |
| Expected-flag-rate estimation for `per_flagged_unit` | PRD D-IR-16 |
| Line-level progress ("15 of 20 tonight") | PRD §8.2 |
| Calculated / formula fields | PRD §7 invariant 5 — needs an evaluator epic |

## Governance in one page (applies to every epic)

| Area | Rule | Where it lives |
|---|---|---|
| Database | Primary keys, declared references, `(account_id, key)` unique natural keys, enums, deactivate-not-delete when referenced by a published version, `db.transaction` for multi-row writes, schema audit passes | GOV-1 standards |
| Input | The server always re-checks. Junk rejected with a plain message; the user's typing kept. Codes under `E-CAT-`, `E-ITM-`, `E-RATE-`, `E-EST-` in `errorCatalog.json` | VAL-1 rules |
| Visibility | Every write and rejection logs a `success` / `rejected` / `failed` event with a feature code and a Reference. `estimate_incomplete` is a `warn` event naming the missing keys | OBS-1 |
| Support | Health page gains an **Estimates** panel: incomplete estimates in open plans; per-unit cells with no lines; methods whose sub-journey is gone | OBS-1 |

## Test conventions

- **Unit:** `node --test` + tsx in `webapp/protype-2/src/*.test.ts`; add each new file to `npm test`.
- **Functional:** Xano `workflow_test` files in `workflow_tests/`, numbered: ITEM-0 = **28**, CAT-1 = **29**, ITEM-1 = **30**, RATE-1 = **31**, EST-1 = **32**. Workflow tests cannot be run from a session (CLAUDE.md); drive each assertion through `runWorkspaceFunction` and say so in Test Results.
- **UI:** Playwright specs in `webapp/protype-2/e2e/`.
- **Golden fixtures:** `estimate-golden.json` (lines + rates → per-stage minutes) shared by `estimate_job` and its TypeScript twin; `versionHash` golden extended for schema v2.
- **Regression gate:** `npm test`, `workflow_tests/1–27`, every new workflow test once added, and existing e2e specs stay green on every epic.
- **Real data:** map **193** (`item-turnaround`) is the realistic fixture for this phase. Test against a **clone**, never the original. Map 178 stays the regression fixture for "a map with no Items row".

## If something breaks (for the product manager)

- Open `/health` → **Estimates**. It says which plan, which job, which stage, and which item has no rate.
- "Estimate incomplete" on a card is **not** an error. It means the map has no rate for something in that order. Fix: open the map → Items row → that stage → add the line → publish a new version.
- A plan built before the new version keeps the old estimate on purpose (the job is pinned). Create a new job to pick up new rates.
