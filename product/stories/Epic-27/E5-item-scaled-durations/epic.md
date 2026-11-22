# SCALE-1 — Item-scaled durations

**Epic ID:** SCALE-1 (E5 in the founder's list)
**Status:** 📋 Written, not built (2026-11-21). **Story 00 decides how much of this is left to build.**
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

_Not run. Nothing built yet._
