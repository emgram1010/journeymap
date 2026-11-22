# SCALE-1 — Item-scaled durations

**Epic ID:** SCALE-1 (E5 in the founder's list)
**Status:** ✅ Built and verified live 2026-11-21. Story 00's report and the gaps are in Test Results.
**Size:** M as requested; likely S to M once story 00 is done (finding F-5).
**Model:** Sonnet 5.5 to build, then an **Opus review** (it changes what every planner card's length means).
**Depends on:** DEMAND-1 (order items arrive through the webhook), EST-1, ITEM-1, RATE-1, CAT-1 (phase-6).
**Read first:** `../README.md` (finding F-5), then `phase-6/EPIC-EST-1-order-lines-and-estimate.md`.

---

## 1. Goal

**Pain:** an order of 2 six-foot tables and 14 adult chairs planned about 11 hours where the
owner expects 20 minutes. The map's Items row holds minutes per unit, but the plan seems to
ignore it.

**Win:** every job's estimate matches what is in the order.

## 2. What exists today (repo files, 2026-11-21; live not compared)

The request reads as if nothing exists. The repo says most of it does.

| Fact | Where |
|---|---|
| Order lines on a job: item, quantity, unique per (job, item) | `static/tables/139_work_item_line.xs` (EST-1) |
| Endpoints to set and read a job's lines | `apis/planner/607_…lines_PUT.xs`, `608_…lines_GET.xs` |
| One function that turns lines and rates into an estimate | `functions/estimate/compute_estimate.xs` |
| Rates frozen at publish, per stage | `static/tables/138_stage_rate.xs` (RATE-1) |
| The Items row and its validation (`minutes_per_unit`) | `functions/items/validate_items_cell.xs` (ITEM-1) |
| Item catalog | `static/tables/136_item_type.xs` (CAT-1) |
| EST-1's rule: "nothing but the estimate function and its TypeScript twin may compute the formula" | EST-1 builder brief |
| EST-1 already shows "estimate incomplete" when a rate is missing | EST-1 MVP |
| EST-1 freezes lines once any task is in progress (`E-EST-007`) | EST-1, story 01 |
| **`plan_add_job` passes no lines** (`attributes: {}`, nothing else) | `ai/tool/plan_add_job.xs` |
| EST-1 lists "intake from a booking system" as deferred | EST-1 MVP line |
| No link between a catalog item and an outside product id | search, 2026-11-21 |

**Most likely cause of the 11 hours:** the job was made by a tool that cannot send lines, so
the card fell back to each stage's fixed minutes. Story 00 proves or disproves this on plan 146
before anything is built.

## 3. Rule

**One formula, one place.** This epic adds ways for items to **reach** the estimate. It does
not write a second estimate. If story 00 finds the formula itself is wrong, it is fixed inside
the existing function and its TypeScript twin, with the golden fixtures updated.

## 4. Do not break

- A job with no items behaves exactly as today.
- Existing jobs keep their current estimates. Nothing in the past is recalculated.
- The owner's manual block length (SCHED-1 tweak, SCHED-2 start override) still wins.
- Plan-vs-actual math is unchanged; only the planned input changes.
- EST-1's freeze: lines do not change under work that has started.

## 5. Non-goals

- Learning rates from actuals.
- Decimal quantities.
- A vendor-specific design. The product link is generic (`source_system`, `external_id`).

## 6. Stories

| File | Story |
|---|---|
| `US-SCALE-1-00-find-out-why-and-what-is-left.md` | Read-only: reproduce the 11 hours, list what EST-1 already covers |
| `US-SCALE-1-01-jobs-carry-their-items.md` | The plan tools accept an item list |
| `US-SCALE-1-02-estimates-scale-with-quantity.md` | Close whatever gap story 00 finds in the estimate |
| `US-SCALE-1-03-map-items-match-outside-products.md` | Link catalog items to outside product ids |

## 7. Completion gate

- The founder's own example (2 six-foot tables, 14 adult chairs) estimates to the hand
  calculation, to the minute, on plan 146.
- 14 chairs plan more than 2 and less than 50.
- An item with no rate shows "no time set" and adds 0; it never becomes a default 30.
- A fixture with no items gives the same cards as before (golden file).
- A real order, once its item times are set, arrives through the webhook with the right estimate.
- Existing suites green. Opus review pass done. Test Results filled in.

## 8. Test Results

**Built and verified live 2026-11-21 (Fable 5.2).**

### Story 00 report: why the order planned 11 hours

| Question | Answer |
|---|---|
| Where do the 11 hours come from? | Plan 146, jobs 249 and 250. Each has **no order lines** (`reasons: ["no_lines"]`), so the estimate is only the map's fixed stage times: 60 + 10 + 120 + 240 + 10 + 30 + 180 + 60 = **710 minutes** |
| Cause | The jobs were made by `plan_add_job`, which could not send items. The formula itself is right |
| Second cause, in the map's own data | Version 4 of map 193 holds test numbers: fixed stage times of 710 minutes **plus** 5 to 20 minutes per item per stage. With 14 chairs the honest answer from this map is far more than 20 minutes. The 20 minutes the owner expects needs real times typed on the map |
| Items on that map | `foldable-chair` and `moonbouncer` only. "Six-foot table" and "adult chair" are not in its Items row |
| EST-1, RATE-1, ITEM-1, CAT-1 | All live and working: lines table, lines endpoints, rates, `estimate/compute_estimate` |
| Story 01 | Built as written |
| Story 02 | Shrunk to its test: the formula already scales |
| Story 03 | Built (backend and screen) |

**What was built**
- Tables `item_external_ref` (170) and `work_item_unmatched_line` (171).
- Functions `estimate/resolve_item_lines` (426), `items/resolve_external` (427), `items/set_external_ref` (428).
- `jobs/create_job` (241) and `planner_ops/create_work_item` (348) accept order lines, written in the job's own transaction.
- `plan_add_job` (tool 173) takes `items` and returns lines, unknown items, items not on the map and the estimate.
- Endpoints `GET item_external_refs` (675), `POST item_external_ref_set` (676); an "Outside products" tab in Catalog.

| Test | Result |
|---|---|
| Job with items | Pass: job 253 on plan 146 with 14 chairs, 2 bouncers and one unknown item |
| Estimate matches a hand calculation | Pass, to the minute: 710 fixed + 910 chairs + 320 bouncers = **1,940** |
| An item with no time in a stage adds 0 and is named | Pass: chairs have no time in stage s3; estimate marked incomplete, no default added |
| Same key twice is added together | Pass (10 + 4 = 14) |
| Unknown key | Pass: job still made, key returned and kept in `work_item_unmatched_line` |
| Bad quantity (0, 2.5) | Pass: whole call refused (E-EST-001), no job made |
| No items | Pass: `plan_add_job` test suite green; the job is made as before |
| Link a product, mark "not an item", move a link | Pass (`saved`, `move_needed`) |
| Linked product becomes an item line; ignored product is skipped | Pass |
| Another account | Pass ("Not Found") |
| The owner's own example (tables and chairs) | **Cannot pass yet:** those items and their real times are not on the map |

**Different from the stories**
- The rules behind `PUT lines` (endpoint 607) were **not** moved into the new function. 607 works on item ids and refuses an item that is not on the map; the new path works on item keys and keeps such an item with "no time set", as the story asks. The 1 to 9999 range now lives in two places.
- Unknown items are kept in a small side table, not in the job's attributes.
- "Refresh jobs not yet started with one press" was not built.
- The job card does not list unknown items yet (the data is stored).
- No Opus review pass was run.

**Left in the founder's test plan:** job 253 "SCALE-1 test … (safe to cancel)" on plan 146.

