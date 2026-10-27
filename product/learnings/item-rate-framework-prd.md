# PRD — The Item Rate Framework

> **Status:** Approved for planning, 2026-10-24. Nothing built.
> **Supersedes:** `product/learnings/item-rate-model.md` (2026-10-23) where the two disagree — see §12 for exactly what changed and why.
> **Parent PRD:** `product/emgramprd.md`. This document extends §4 (glossary), §5 (scheduling shape) and supersedes LN-5.
> **Build plan:** `product/stories/phase-6/README.md`.
>
> Every example in this document (chairs, tables, covers, a game) is an **illustration**.
> No requirement may depend on one. The generic statement of the problem is:
> *a job contains counts of several different things, and each thing takes a different
> amount of time at each stage.*

---

## 0. Orientation — read this first

- **The problem.** The intelligence layer stores one duration per cell. A real job is a mix of things with different per-unit times, so the planner gets `30` minutes for everything and variance has nothing honest to compare against.
- **The first principle.** *How long* is not a number. It is a function of what is in the job: **estimate = baseline + Σ (quantity × rate)**.
- **The design.** Four new objects, one new row kind, zero changes to actors or cells. The map stores a **formula**; the order supplies the **counts**; the number is computed when the order exists.
- **The build.** Five epics for the intelligence layer (phase-6, steps 0–4). Planning and execution are designed here so none of it is thrown away, and built after.

---

## 1. Problem statement

The intelligence layer can create tasks, but they carry almost no information.

```
Order #482
  20 x resin chair
   3 x 6-ft table
  12 x table cover
  20 x chair cover
   1 x oversized tic-tac-toe game
```

Every line is processed differently and takes a different amount of time. Today:

| Fact | Consequence |
|---|---|
| `journey_cell.time_duration_value` is one number per cell, no item dimension | The map cannot express "20 chairs take longer than 3 chairs" |
| `planner_task.duration_minutes` defaults to `30` | Every schedule is built on a number nobody chose |
| `work_item.attributes` is flat key/value, max 50 keys, no nesting (E-JOB-004) | An order cannot even record what is in it |
| Variance compares actual against that `30` | Learning is impossible |

The naive fixes are all rejected:

| Naive fix | Why it fails |
|---|---|
| A lane (lens row) per item | A lane answers *who*. 100 items → 100 rows, every row meaning two things at once |
| A sub-journey map per item | 100 items → 100 maps, identical except for a number |
| One global "size factor" per item | The difference is **per stage** (a 6-ft table costs more at Triage and Clean, nothing extra at Receive). One multiplier cannot say that, cannot be estimated, and when wrong skews every stage invisibly |

---

## 2. First principles

### 2.1 The core rule

```
stage estimate = baseline_minutes + SUM over lines ( quantity × rate[stage, quantity_key, method] )
```

| Number | Answers | Lives in | Scales with count? |
|---|---|---|---|
| **Baseline** | What does this stage cost *per order*, whatever is in it? (setup, teardown, paperwork) | `journey_cell.time_duration_value` on the actor's cell — **existing column, clarified meaning** | No |
| **Rate** | How long does **one unit** of this thing take at this stage, by this method? | `stage_rate` (published) ← Items cell JSON (draft) | Yes |
| **Count** | How many of this thing are in this order? | `work_item_line`, on the job | — |

The map owns the **standards**. The order owns the **counts**. The log owns the **actuals**. This is the existing three-layer architecture — Definition → Commitment → Record — unchanged.

### 2.2 Quantities are general; items are the common case

"20 chairs" is a quantity. So is "3 flights of stairs", "12 miles", "40 stops", "15 leads in the batch". The rate rule is the same for all of them. The framework therefore keys a rate by a **quantity key**, and a catalog item is the most common kind of quantity key.

**MVP decision (D-IR-15):** the catalog holds physical, countable items only. The *key shape* is generic so a later map can register "flight of stairs" as a countable thing without a redesign. This is what retires PRD LN-5.

### 2.3 Deviation has three sizes

| Size | Example | Answer |
|---|---|---|
| Slower only | A 6-ft table vs a 4-ft table | A different **rate**. Same method. No structure. |
| Different steps at one stage | Covers go in a washer; chairs get pressure-washed | A second **method** at that stage, linked to its own sub-journey |
| Different steps at most stages | A bounce house is not a turnaround item | A different **work type** — a different map. Do not bend one map to hold two processes. |

### 2.4 The Items row is a perspective, not an actor

The grid is *stage × perspective*. Actor rows are perspectives on *who*. `description` (already live on map 193, `actor_type = ""`) is a perspective on *what happens*. The **Items row** is the perspective on *what flows through* — per stage: does time scale with count, and at what rate per thing.

It is the only place in the map a user touches to enable this framework. Its presence **is** the switch.

---

## 3. Concepts and glossary (adds to PRD §4)

| Term | Meaning |
|---|---|
| **Item type** (`item_type`) | A countable thing the business processes. Account-level catalog, shared by every map. Not inventory: it answers *how is this processed*, not *how many do I own*. |
| **Method** (`method`) | A way of doing the work, shared by many items (e.g. `hard-goods`, `textiles`, `sanitize`). A real record: key, label, optional sub-journey (the steps), optional role (who does it). Was called "family" during design; **"method"** is the settled word. |
| **Items row** | The one non-actor row on a map that holds the item framework. Exactly one per map. Switched on like a financial lens. |
| **Items cell** | Items row × one stage. Holds: `scales_with`, and one **line per item** (`method`, `minutes_per_unit`, later `notes`, `requirements`). Draft store only. |
| **Scaling** (`scales_with`) | Per stage: `per_order` (flat), `per_unit` (every item), `per_flagged_unit` (only items flagged upstream). |
| **Rate** | Minutes for one unit of one item at one stage by one method. |
| **Rate card** (`stage_rate`) | The published, version-pinned, long-form table of rates. Written only at publish. |
| **Baseline** | The existing cell duration on the stage owner's cell, now explicitly *per order*. |
| **Order line** (`work_item_line`) | One (job, item type, quantity). The counts. Never in the map. |
| **Estimate** | `estimate_job` output: per-stage minutes, total, and a `complete` flag with what is missing. |
| **Source** | On every rate: `seed` (a human guess) or `measured` (variance proposed it from a clean read). |
| **Clean read** | A stage run whose order contained one item type only. The only input learning may use to promote a rate. |

Terminology guard: **lens** = the row (`journey_lens`); **cell** = stage × lens (`journey_cell`).

---

## 4. Where everything lives — against the map the founder already knows

| Level that exists today | What this framework changes |
|---|---|
| **Journey map settings** | Nothing. (An earlier draft added `tracks_items`; dropped — the row's presence is the switch.) |
| **Stage header** | Nothing. (An earlier draft added a scaling side table; dropped — scaling lives in the Items cell.) |
| **Actor rows (lenses)** | Nothing. No item actor. |
| **Actor cells** | Nothing. `time_duration_value` keeps its column and simply means *baseline, per order*. |
| **New: Items row** | One `journey_lens` with `template_key = "items-v1"`, `actor_type = ""`, `does_planned_work = false`. |
| **New: Items cells** | The existing `journey_cell.actor_fields` JSON, under an `items-v1` template: `{scales_with, lines: [{item_key, method_key, minutes_per_unit}]}`. |
| **New, off the grid** | `item_type` and `method` — account-level catalogs, like actor roles. |
| **New, row config** | `journey_lens_item` — which catalog items this map's Items row uses. |
| **New, on the version** | `stage_rate` — materialized from the Items cells at publish; immutable; queryable. |
| **New, on the job** | `work_item_line` — the counts. |
| **New, one function** | `estimate_job` — the only place the formula is computed. |

```
THE GRID

                 s1 Receive      s2 Triage        s8 Wash & Clean
               +---------------+----------------+-------------------+
 Warehouse Ops | baseline 15   | baseline 5     | baseline 10       |
 (actor row)   | task, done... | task, done...  | task, done...     |
               +---------------+----------------+-------------------+
 Items         | per order     | per unit       | per unit          |
 (items row)   | -             | chair  0.5     | chair  2.0  hard  |
               |               | table  1.5     | table  4.0  hard  |
               |               |                |  -> [hard-goods]  |
               +---------------+----------------+-------------------+

OFF THE GRID           item_type: chair-resin, table-6ft, ...
                       method:    hard-goods -> sub-journey, role
ON THE VERSION         stage_rate: one row per (stage, item, method)
ON THE JOB             work_item_line: 20 x chair-resin, 3 x table-6ft
```

---

## 5. Data model

### 5.1 `item_type` — account catalog

| Column | Type | Notes |
|---|---|---|
| `account_id` | ref `account` | Tenancy |
| `key` | text, trim+lower | Unique per account; stable; what rates and lines reference |
| `label` | text, trim | 1–80 chars, no HTML |
| `unit` | enum `each`, `set`, `pair` | A `set` line of 1 covers all its pieces |
| `default_method_id` | ref `method`, 0 = none | Seeds the first line in each per-unit Items cell. Nothing more. |
| `size_label` | text, trim, optional | Grouping and reporting only. **Never math** (D-IR-2). |
| `external_ref` | text, trim, optional | Seam to a booking/inventory SKU. Emgram never owns stock or availability (D-IR-10). |
| `is_active` | bool, default true | Deactivate, never delete, once referenced by a published version |

### 5.2 `method` — account catalog

| Column | Type | Notes |
|---|---|---|
| `account_id` | ref `account` | |
| `key` | text, trim+lower | Unique per account |
| `label` | text, trim | |
| `sub_journey_map_id` | ref `journey_map`, 0 = none | The steps. Optional: a method with no sub-journey is "same steps as the owner's cell, just a different rate". |
| `role_id` | ref actor role / `0` | Who performs it. Optional in MVP (ROLE-1 is deferred); when set, planning splits on it. |
| `is_active` | bool | |

### 5.3 The Items row and cells — existing tables, new template

- `journey_lens`: `template_key = "items-v1"`, `actor_type = ""` (mirrors `description`, proven to pass the readiness gate and the planner), `label = "Items"`.
- `journey_lens_planned_work.does_planned_work = false` for that row, always. Enforced by the API, not left to the UI.
- `journey_lens_item` (new side table): `(journey_lens_id, item_type_id)`, unique. The row's item list.
- `journey_cell.actor_fields` for an Items cell:

```json
{
  "scales_with": "per_unit",
  "lines": [
    {"item_key": "chair-resin", "method_key": "hard-goods", "minutes_per_unit": 2.0},
    {"item_key": "table-6ft",   "method_key": "hard-goods", "minutes_per_unit": 4.0},
    {"item_key": "chair-backyard", "method_key": "hard-goods", "minutes_per_unit": 2.0},
    {"item_key": "chair-backyard", "method_key": "textiles",   "minutes_per_unit": 6.0}
  ]
}
```

- Writes to this JSON use the **two-step patch** (null, then value) — `db.patch` on a `json` column merges, it does not replace (CLAUDE.md, critical).
- Future fields (`notes`, `requirements`) are added to the `items-v1` → `items-v2` template, not to the schema. Anything the system later *computes with* is promoted to a column when that happens.

### 5.4 `stage_rate` — published rate card

| Column | Type | Notes |
|---|---|---|
| `journey_map_version_id` | ref `journey_map_version` | Pinned |
| `stage_key` | text | The stage's key, not its id |
| `quantity_key` | text | An `item_type.key` in MVP; generic by design (§2.2) |
| `method_key` | text | `method.key` |
| `minutes_per_unit` | decimal | ≥ 0, ≤ 1440 |
| `source` | enum `seed`, `measured` | |

Unique: `(journey_map_version_id, stage_key, quantity_key, method_key)`. Rows are written **only** by publish. Never patched. A new version writes new rows.

### 5.5 `work_item_line` — the counts

| Column | Type | Notes |
|---|---|---|
| `work_item_id` | ref `work_item` | |
| `item_type_id` | ref `item_type` | |
| `quantity` | int | 1–9999 in MVP (decimal quantities arrive with non-item quantity keys, later) |
| `flagged_quantity` | int, default 0 | How many of this line were flagged upstream. Written by execution, later. Exists now so `per_flagged_unit` has a home. |

Unique: `(work_item_id, item_type_id)`.

### 5.6 The version snapshot and hash — schema version 2

`pub/build_map_snapshot` today emits cells **only for rows whose `does_planned_work` is true**. The Items row is deliberately not one of those, so its cells — and the rates in them — are **not** in the hashed snapshot today. They must be, or two versions with different rates hash identically.

Add two sections to `MapSnapshot` (both sides, `versionHash.ts` ↔ `canonical_hash.xs`):

```
scaling: [{stage_key, scales_with}]                                   # one per stage that has an Items cell
rates:   [{stage_key, quantity_key, method_key, minutes_per_unit, source}]   # sorted by stage order, then quantity_key, then method_key
```

Canonical lines: `scale|<stage_key>|<scales_with>` and `rate|<stage_key>|<quantity_key>|<method_key>|<minutes>|<source>`. `schema_version` becomes `2`. A `v1` snapshot emits neither line, so every existing version still verifies byte-for-byte. Pin a new golden on both sides.

---

## 6. Behaviour

### 6.1 Resolution order for a rate at a per-unit stage

1. Explicit line: `(stage, item, method)` in the Items cell.
2. Else the item's `default_method` and the method's default line for that stage, if one is set.
3. Else: **no rate**. The item is listed in `estimate.missing[]`; the estimate is `complete = false`.
4. Never silently zero. Never silently `30`.

### 6.2 `estimate_job(work_item_id)` — the one formula

```
for each stage in the pinned version (display order):
  baseline  = owner cell's duration_minutes (TIME-1 rule) or 0
  scaling   = Items cell scales_with, or per_order if the map has no Items row
  variable  = 0; missing = []
  if scaling == per_unit:
      for each line: for each rate row matching (stage, line.item, *):
          variable += line.quantity × minutes_per_unit
      any line with no matching rate row -> missing
  if scaling == per_flagged_unit:
      same, using line.flagged_quantity (MVP: usually 0 -> contributes 0, complete stays true; D-IR-16)
  total = baseline + variable
  source = measured if every rate used is measured; seed if any is seed; n/a if no rates used
return {stages[], total_minutes, complete, missing[]}
```

- Planning calls this. Nothing else recomputes the formula — not the card, not the badge, not variance.
- When `complete = false`, the planner card shows **baseline only** with an "estimate incomplete" badge. It never falls back to `30`.
- A map **with** an Items row and a job **with no lines** → `complete = false`, reason `no_lines`.
- A job with lines on a map **without** an Items row → rejected at line creation (`E-EST-004`).

### 6.3 Two methods at one stage, and the split

A cushioned chair at Wash & Clean is two lines: frame (`hard-goods`, 2.0) + cushion (`textiles`, 6.0) = 8.0 per chair. The stage total is simply the sum — the formula does not change.

When two methods at one stage name **different roles**, the work happens at different stations and may run in parallel. Planning then needs one card per (order, stage, method-with-distinct-role), extending BLK-1's one-card-per-order. The baseline is paid once per card — two setups genuinely happen. This is designed in §8 and built after the intelligence layer.

### 6.4 Learning (designed now, built with execution)

- One log entry covers a whole stage run. In a mixed batch nothing says which item ate the time. **A mixed batch never rewrites a rate.**
- Variance may split a mixed batch's overshoot proportionally *for reporting*, flagged low-confidence.
- Only a **clean read** (one item type in the run) may propose `rate = (actual − baseline) / quantity`, `source = measured`.
- A proposal is written to the **draft** Items cell, never to `stage_rate`. A human publishes a new version. Same rule as cells today: *Expected changes only via a new version.*

```
MIXED (report only)      s8 expected 10 + 3×4.0 + 20×2.0 = 62, actual 90 → +28, rates stay seed
CLEAN (learn)            20 chairs only: expected 10 + 20×2.0 = 50, actual 68 → (68−10)/20 = 2.9 → draft, measured
```

---

## 7. Invariants — the rules that stop the bloat

1. **Exactly one Items row per map.** Items are lines inside its cells, never rows on the map.
2. **Sub-journeys attach to methods, never to items.**
3. **Anything the system computes with is a column** (`stage_rate`, `work_item_line`). **Anything a human only reads is a template field** in cell JSON.
4. **Learning never edits a published rate.** It writes a draft; a human publishes.
5. **No formulas or calculated fields in the map** until there is an evaluator epic. `notes` is the only cheap next field.
6. **The Items row is never an actor**: it is never a stage owner, never assigned in a plan, never costed in leakage, never filled with prose by the AI builder.
7. **Rates key on the stage `key`, not the stage id or label.** Renaming a stage breaks nothing. Deleting a stage removes its draft lines; published versions are untouched.
8. **Catalog rows referenced by any published version cannot be deleted** — deactivate instead.

---

## 8. Holistic view — planning and execution, designed so nothing is thrown away

### 8.1 What planning consumes

| Need | Comes from | Built in |
|---|---|---|
| A real per-stage duration per job | `estimate_job(...).stages[].total_minutes` → `planner_task.duration_minutes` via `job_step_hydration` / `derive_tasks` | EST-1 (phase-6) |
| Guess vs measured | `estimate_job(...).stages[].source` | EST-1 |
| "Estimate incomplete" | `estimate_job(...).complete`, `missing[]` | EST-1 |
| One card per (order, stage, method-with-role) | `method.role_id` + a `method_key` on `planner_task_work_task` (int-only table today, so an additive column is safe) | PLN-M-1 (after phase-6) |
| Capacity: "how many chairs fit in one evening" | window ÷ rate — pure read over `stage_rate` | PLN-M-1 |
| Three durations intact | expected = `estimate_job`; scheduled = planner tweak (SCHED-1); actual = log (LOG-1) | unchanged |

### 8.2 What execution consumes

| Need | Comes from | Built in |
|---|---|---|
| "What am I processing" on a task | `work_item_line` grouped by `method`, each with the method's sub-journey steps | EXE-M-1 (after planning) |
| Actuals | already on `work_task` / `activity_log` | unchanged |
| Flag counts for `per_flagged_unit` | `work_item_line.flagged_quantity`, written by execution | EXE-M-1 |
| Clean-read learning | lines at completion + actual minutes → draft proposal | EXE-M-1 |
| Line-level progress ("15 of 20 tonight") | **deferred**; nothing in this schema blocks a later `work_task_line_progress` | later |

### 8.3 Sequence, zero throwaway

```
phase-6 (intelligence layer)
  ITEM-0  step-0 audit — lens loops, non-actor row mechanics, hash coverage     (Opus)
  CAT-1   item_type + method catalogs, CRUD, settings UI                        (Sonnet)
  ITEM-1  Items row kind, journey_lens_item, Items cell editor                  (Sonnet)
  RATE-1  publish materializes stage_rate; snapshot + hash schema v2            (Opus)
  EST-1   work_item_line + estimate_job → planner cards; incomplete badge       (Sonnet, Opus review)
after
  PLN-M-1 method-aware cards, guess/measured badge, capacity view
  EXE-M-1 lines-by-method on the task, flag counts, clean-read learning
```

---

## 9. Edge cases the architecture must hold

| # | Case | Expected behaviour |
|---|---|---|
| EC-1 | Map has an Items row; job has no lines | `complete = false`, reason `no_lines`; card shows baseline + badge |
| EC-2 | Job has a line for an item not in this map's `journey_lens_item` | Rejected at line creation, `E-EST-003` |
| EC-3 | Item deactivated after a version was published | Pinned version keeps its rate; new drafts cannot add the item |
| EC-4 | Two methods at one stage, same role | One card; total is the sum |
| EC-5 | Two methods at one stage, different roles | Two cards (PLN-M-1); each pays its baseline |
| EC-6 | `per_flagged_unit` stage, nothing flagged yet | Contributes 0; `complete` stays true (D-IR-16) |
| EC-7 | Quantity 0 or negative | Rejected, `E-EST-001` |
| EC-8 | Stage renamed after rates set | Nothing changes — keyed by `key` |
| EC-9 | Stage deleted in draft | Its Items cell and lines go with it; published versions untouched |
| EC-10 | Map without an Items row, job with lines | Rejected, `E-EST-004` |
| EC-11 | Verifying a `schema_version = 1` version after RATE-1 ships | Still verifies byte-for-byte |
| EC-12 | Items cell line edited | Two-step JSON patch; old lines never survive a "replace" |
| EC-13 | AI `fill_cells` / `scaffold_map` runs on a map with an Items row | Skips the Items row entirely; never writes prose into it |
| EC-14 | Readiness gate on a map with an Items row | The Items row is not a work row; it cannot block or satisfy the gate — but a `per_unit` Items cell with zero lines is a **warning** in the readiness report |
| EC-15 | Second Items row attempted | Rejected, `E-ITM-001` |
| EC-16 | A method's sub-journey is deleted | Method keeps working as "same steps, different rate"; event logged |
| EC-17 | Same item twice in one order | Rejected by the unique key; the UI merges quantities instead |
| EC-18 | 300 items on one map | One row, 300 lines per per-unit cell; the editor paginates/filters; the JSON stays small |

---

## 10. Decisions

Settled in design (carried from the 2026-10-23 session, renumbered where changed):

| ID | Decision | Why |
|---|---|---|
| D-IR-1 | Same stages + different speed = **data**, not structure. No sub-journey per item. | 100 near-identical maps otherwise |
| D-IR-2 | A 6-ft and a 4-ft table are **two item types**, not a size factor. | The difference is per stage; a factor can't be estimated and fails invisibly |
| D-IR-3 | The rate belongs to the **item**, never to a cell's duration. | A cell has no item dimension |
| D-IR-4 | A sub-journey holds the **method's steps**, never minutes. | *How* vs *how long* |
| D-IR-5 | Method is part of the rate **key**. | One item can need two methods at one stage |
| D-IR-6 | No new actor, no new lens kind that behaves as an actor, no new cell column. | The lane answers *who* |
| D-IR-7 | Scaling lives in the **Items cell**, not on the stage. | *(changed from the 23rd: was a stage side table)* One place per stage, inside the row that owns the concept |
| D-IR-8 | Rates are **pinned to the version**. | Otherwise a rate edit re-estimates live work |
| D-IR-9 | Storage is **long, not wide**. | Every map has a different number of stages |
| D-IR-10 | Emgram never owns stock levels or availability. | The booking system's job |
| D-IR-11 | **The Items row's presence is the switch.** No map setting. | *(changed: drops `tracks_items`)* |
| D-IR-12 | **Method is a table**, not a string. | Planning splits on it; execution shows its steps |
| D-IR-13 | **Draft rates live in the Items cell JSON; publish materializes `stage_rate`.** | Editor = draft store; version = queryable store; readiness and hash already walk cells |
| D-IR-14 | **The rate key is a generic `quantity_key`.** | Retires LN-5 without a second mechanism |
| D-IR-15 | **MVP catalog = physical items only**; key shape generic. | Smallest useful slice; no redesign for stairs/miles later |
| D-IR-16 | **`per_flagged_unit` contributes 0 until flagged**, in MVP. | Never over-books; the expected-flag-rate option is a later, measured feature |
| D-IR-17 | **"Method"** is the word. "Family" retired. | Plainer |
| D-IR-18 | MVP template `items-v1` = `method` + `minutes_per_unit`. `notes` is the first add-on (`items-v2`). | Shape decided now, fields added later without schema change |

Still open (recommended defaults in bold):

| # | Question | Recommendation |
|---|---|---|
| O-1 | Should the Items row use `actor_type = ""` (as `description` does) or a new enum value `items`? | **`""` + `template_key = "items-v1"`.** Adding an enum value needs `updateTableSchema` on `journey_lens`, which drops its validators. |
| O-2 | Do the booking SKUs already split 6-ft from 4-ft tables? | Unknown. Decides whether `external_ref` is 1:1 or needs a mapping step at intake. |
| O-3 | Is the card split per method automatic, or confirmed by the planner? | **Automatic when roles differ; otherwise one card.** Confirmation can be added if it misfires. |
| O-4 | Should the planner be allowed to tweak a *rate* for one job, or only the stage total (today's tweak)? | **Stage total only.** Keeps SCHED-1 unchanged. |

---

## 11. Governance (applies to every phase-6 epic)

- **Tables:** primary keys, declared references, unique natural keys (`account_id + key`), enums, explicit delete behaviour (deactivate when referenced; cascade drafts only), `db.transaction` for multi-row writes, schema audit passes.
- **Validation:** server re-checks everything; junk rejected with a plain message and the user's typing kept; error codes in the catalog under `E-CAT-`, `E-ITM-`, `E-RATE-`, `E-EST-`.
- **Observability:** every write and every rejection logs a `success` / `rejected` / `failed` event with a feature code (`CAT-1`, `ITEM-1`, `RATE-1`, `EST-1`) and a Reference. `estimate_job` logs `estimate_incomplete` as `warn`, with the missing keys, so the Health page can show *why* a plan is a guess.
- **Health page:** one new panel, "Estimates": incomplete estimates in open plans, items with no rate on a per-unit stage, methods with a deleted sub-journey.

---

## 12. What changed from the 2026-10-23 model, and why

| 23 Oct draft | Now | Why |
|---|---|---|
| `tracks_items` map setting | Dropped | The Items row's presence is the switch (D-IR-11) |
| `journey_stage_scaling` side table | Dropped | Scaling lives in the Items cell (D-IR-7) |
| "Rates drawer" under the stage header | Items **row** + Items **cells** | Uses the grid the founder already knows; one fewer UI concept |
| Family = a string in the key | `method` table | Planning and execution need to reference it (D-IR-12) |
| `item_rate` keyed by item | `stage_rate` keyed by generic `quantity_key` | Covers stairs/miles/stops later (D-IR-14) |
| Rates stored directly in a table while drafting | Draft in cell JSON, materialized at publish | Editor and store aligned; hash and readiness already walk cells (D-IR-13) |
| Hash: unstated | Snapshot `schema_version 2` with `scale|` and `rate|` lines; v1 still verifies | Found by reading `build_map_snapshot`: non-work rows are not hashed today |

---

## 13. Success criteria for the intelligence-layer slice

1. On map 193, a planner can add the Items row, pick two items, set scaling on 8 stages and type 6 rates, publish, and the version's hash changes — and verifies.
2. A job with `20 × chair-resin, 3 × table-6ft` returns a per-stage estimate from `estimate_job` that matches the hand calculation to the minute, with `complete = true`.
3. Remove one rate and republish: the same job returns `complete = false`, names the missing item and stage, and the card shows baseline + badge — never `30`.
4. Every existing published version still verifies. `npm test`, `workflow_tests/1–27` and the e2e specs stay green.
5. The AI builder, the readiness gate, leakage and the planner all ignore the Items row as an actor — proven by ITEM-0's audit tests, not by inspection.
