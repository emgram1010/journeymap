# The Item Rate Model — how a journey map estimates time for an order of many different things

> **Superseded by `item-rate-framework-prd.md` (2026-10-24).** Kept as the design trail.
> Where the two disagree, the PRD wins — its §12 lists each change (no `tracks_items`
> setting, no stage side table, "family" → "method", rates drafted in the Items cell
> and materialized at publish, generic `quantity_key`).

> Source: design session, 2026-10-23. Grounded against live map 193 (`item-turnaround`),
> tables `journey_cell`, `journey_stage`, `journey_link`, `work_item`, `work_task`, `planner_task`.
> Purpose: define where per-item processing time lives, so the intelligence layer can
> produce a real estimate for an order instead of a flat default.
>
> The worked examples below (tables, chairs, covers, a game) are **illustrations**.
> Nothing in the model may depend on them. The generic shape is: *a job contains a
> count of several different things, and each thing takes a different amount of time
> at each stage.*

---

## 1. The problem

The intelligence layer can create tasks, but those tasks carry almost no information.

A turnaround order is not one thing. It is:

```
Order #482
  20 x resin chair
   3 x 6-ft table
  12 x table cover
  20 x chair cover
   1 x oversized tic-tac-toe game
```

Every one of those is processed differently and takes a different amount of time.
Today the map holds **one duration per cell**, with no item dimension at all, and
`planner_task.duration_minutes` defaults to `30`. So:

- The planner cannot say how long the order will take.
- The schedule cannot be trusted, because the number behind it was never real.
- Variance has nothing meaningful to compare against.

The naive fixes are all wrong:

| Naive fix | Why it fails |
|---|---|
| A lane (lens row) per item | The lane answers *who*. 100 items becomes 100 rows, and every row then means two things at once. |
| A sub-journey map per item | 100 items becomes 100 maps, most of them identical except for a number. |
| One global "size factor" per item | The difference is **per stage**, not uniform. A 6-ft table costs more at Triage and Clean (two-handed positioning) but nothing extra at Receive. One multiplier cannot express that. |

---

## 2. The core principle: three numbers, three homes

| Number | Question it answers | Where it lives | Scales with count? |
|---|---|---|---|
| **Fixed minutes** | How long does this stage cost *per order*, regardless of what is in it? | `journey_cell.time_duration_value` (existing column, clarified meaning) | No |
| **Rate** | How long does **one unit** of this item take at this stage, by this method? | New `item_rate` table | Yes |
| **Count** | How many of this item are in this order? | New `work_item_line` table, on the job | — |

```
stage estimate = fixed_minutes + SUM over lines ( quantity x rate[item, stage, family] )
```

The map owns the **standards**. The order owns the **counts**. The log owns the **actuals**.
This is the existing three-layer architecture (Definition → Commitment → Record), unchanged.

---

## 3. The five concepts

### 3.1 Item catalog (`item_type`)

A shared list of the things the business processes. **Off the grid** — not a row, not a
column, not a cell. It sits beside the maps and is referenced by them, exactly the way
actor roles already do.

```
key              label                   unit  default_family  size  external_ref
table-6ft        6-ft banquet table      each  hard-goods      6ft   TBL-6
table-4ft        4-ft table              each  hard-goods      4ft   TBL-4
chair-resin      Resin folding chair     each  hard-goods      std   CHR-RES
chair-backyard   Backyard chair          each  hard-goods      std   CHR-BY
game-tictactoe   Oversized tic-tac-toe   set   games-props     -     GME-TTT
```

- Account level, because the same chair passes through delivery, turnaround and inventory.
- `unit` matters: the game's unit is `set`, so one line of `1` covers all its pieces.
- `size` is a **grouping label only**. It never does math (D-IR-2).
- `default_family` is a seeding convenience — it creates the first rate row, nothing more.
- `external_ref` is the optional seam to a booking or inventory SKU.

**This is not an inventory list.** Inventory answers *what do I own, can I rent it, what
does it cost*. The catalog answers *how is it processed, and how long per unit*.
Granularity differs in both directions: 40 bookable SKUs may collapse to 5 processing
types, and one SKU may split into two because its minutes differ.

### 3.2 Method family

A **way of doing the work** — one method, shared by many items.

- `hard-goods` — pressure wash and wipe down
- `textiles` — washer and dryer
- `games-props` — piece count and spot clean

It exists so that 100 items do not need 100 sets of instructions; they point at three
methods. A sub-journey map attaches to the **family**, never to the item.

Same family does **not** mean same time. Chairs and tables share `hard-goods` and keep
different minutes. Method and rate are independent.

Family is also the resource hint: textiles need a machine, hard goods need the wash bay.
That is what makes the parallel split in §6 possible.

### 3.3 Rate card (`item_rate`)

One row = *one unit of this item, at this stage, by this method, takes this long.*

Key: `(journey_map_version_id, item_type, stage_key, family)`

```
id  version  item_type       stage_key  family      min_per_unit  source
1   v3       table-6ft       s2         hard-goods  1.5           seed
2   v3       table-6ft       s8         hard-goods  4.0           measured
3   v3       table-6ft       s5         hard-goods  0.5           seed
4   v3       chair-resin     s2         hard-goods  0.5           seed
5   v3       chair-resin     s8         hard-goods  2.0           measured
6   v3       chair-backyard  s8         hard-goods  2.0           seed      (frame)
7   v3       chair-backyard  s8         textiles    6.0           seed      (cushion)
```

- `source` separates `seed` (a guess) from `measured` (variance rewrote it), so it is
  always visible which numbers are real.
- Pinned to the **map version**, like cells. A job pins a version, so editing a rate
  tomorrow cannot change the estimate of work already in flight.

### 3.4 Stage scaling flag

Per stage: does time at this stage scale with the number of items?

| Value | Meaning |
|---|---|
| `per_order` | Flat. Receiving a truck costs the same for 5 items or 500. |
| `per_unit` | Scales with every item in the order. |
| `per_flagged_unit` | Scales only with items flagged upstream (damages, exceptions). |

Lives on the **stage**, in a `journey_stage_scaling` side table — not a new column on
`journey_stage`, because `updateTableSchema` silently drops that table's text validators
(CLAUDE.md). This is the established `journey_stage_owner` / `journey_lens_planned_work`
pattern.

### 3.5 Order lines (`work_item_line`)

The counts. One row per `(work_item, item_type, quantity)`.

`work_item.attributes` **cannot** hold this: it is a flat `{key: {value, source,
entered_at}}` map, capped at 50 keys, and explicitly forbids nested objects (E-JOB-004).
Lines need their own table.

---

## 4. Where each new thing lives, against the existing model

| Level that already exists | What changes |
|---|---|
| **Journey map settings** (overall purpose and goal) | One new flag: `tracks_items` true/false. Turnaround yes; leads-to-sales no. |
| **Stage header** (label, goal, order) | `scales_with`: `per_order` / `per_unit` / `per_flagged_unit`, via side table. |
| **Lens** (the actor row) | **Nothing.** No item actor, no new field. |
| **Cell** (stage × lens intersection) | **Nothing.** `time_duration_value` simply now means *fixed per-order* minutes. |
| — | **New, off the grid:** `item_type` catalog, account level. |
| — | **New, the third axis:** `item_rate`, keyed by version + item + stage + family. |
| — | **New, job side:** `work_item_line`, the counts. Never in the map. |

Terminology, to keep the code and the conversation aligned:

- **Lens** = the actor **row** (`journey_lens`).
- **Cell** = the **intersection** of a stage column and a lens row (`journey_cell`).

Four new objects. Zero changes to lanes or cells.

---

## 5. The whole model in one picture

```
THE GRID (what already exists)

                 s1 Receive      s2 Triage       s8 Wash & Clean
                 per order       per unit        per unit
               +---------------+---------------+------------------+
 Warehouse Ops | count the load| inspect each  | clean each item  |
 (lens-2)      | fixed: 15 min | fixed: 5 min  | fixed: 10 min    |
               +---------------+---------------+------------------+
                                       |
                                       | the cell links out to the METHOD,
                                       v   which holds STEPS, never minutes
                              [hard-goods map]  [textiles map]


THE RATE CARD (the third axis, behind the grid)

                        s1      s2      s8     family
   table-6ft            -       1.5     4.0    hard-goods
   chair-resin          -       0.5     2.0    hard-goods
   chair-backyard       -       0.5     2.0    hard-goods   <- frame
                                        6.0    textiles     <- cushion


THE ORDER (counts live here, never in the map)

   Order #482  =  3 x table-6ft  +  20 x chair-resin

   s1  = 15                              =  15.0 min   (count does not matter)
   s2  = 5  + (3 x 1.5) + (20 x 0.5)     =  19.5 min
   s8  = 10 + (3 x 4.0) + (20 x 2.0)     =  62.0 min
                                            --------
                                            96.5 min  -> the planner's cards
```

The grid above is a **view**. The database stores the rate card long, never wide —
one row per combination, so a 3-stage map makes 3 rows and a 20-stage map makes 20,
with no schema change and no migration when a stage is added. This is the same shape
`journey_cell` already uses: one row per (stage, lens), not a column per stage.

---

## 6. Two methods at one stage, and the parallel split

A backyard chair with a cushion is handled **two ways** at Wash & Clean: the frame is
wiped, the cushion goes in the washer. That is why family is part of the rate card's
**key** and not a property of the item.

```
chair-backyard  s8  hard-goods  2.0   (frame)
chair-backyard  s8  textiles    6.0   (cushion)
                                ---
                                8.0 per chair at s8
```

The stage total is the sum of its rows, so the rollup math is unchanged.

Those same two rows are also the **scheduling split**: the cushion needs a machine and
the frame needs the wash bay, so they are different stations that can run in parallel.
When families at a stage have different owners, the order splits into child jobs —
`work_item.parent_work_item_id` already exists for exactly this, though nothing creates
or rolls up through it yet (G-6).

---

## 7. Resolution order for a rate

1. `item × stage × family` — explicit override.
2. `family × stage` — the family default.
3. No row → that stage does not scale for that item; fixed minutes only.
4. No number anywhere on a `per_unit` stage → the estimate is reported **incomplete**,
   the same way `calculate_leakage` returns `incomplete_cells[]`. Never silently zero.

This is what makes hundreds of item types cheap: a new item is usable the moment it is
assigned a family, and only the stages where it genuinely differs need an override.

---

## 8. Worked example — map 193 `item-turnaround`

Live stage keys, in display order. The keys are **IDs, not positions** (s8 is the fifth
column, because it was created after s1–s6). Rates point at the key, so renaming a stage
breaks nothing.

| # | key | label | scales_with |
|---|---|---|---|
| 1 | s1 | Receive at the dock | `per_order` |
| 2 | s7 | Segregate and group | `per_order` |
| 3 | s2 | Triage | `per_unit` |
| 4 | s3 | Triage Damages | `per_flagged_unit` |
| 5 | s8 | Wash & Clean | `per_unit` |
| 6 | s4 | Exception Lane | `per_flagged_unit` |
| 7 | s5 | Inventory | `per_unit` |
| 8 | s6 | Rent-Ready | `per_order` |

One actor lane: `lens-2`, Warehouse Operations. It does **not** change.

For a table and a chair, **no sub-journey is needed at all** — same method, different
rate. A sub-journey appears only when the covers arrive, because washer-and-dryer is a
genuinely different set of steps from wipe-down.

All numbers in this document are illustrative seeds. The point is not their accuracy; it
is that they are per-item and per-stage, and that variance can rewrite them from real
evenings. The founder never has to guess well — only once.

---

## 9. Decisions settled in this session

| ID | Decision | Why |
|---|---|---|
| D-IR-1 | Same stages + different speed = **data**, not structure. No sub-journey per item. | A map per item is 100 near-identical maps differing by one number. |
| D-IR-2 | A 6-ft and a 4-ft table are **two item types**, not one with a size factor. | The difference is per stage (handling and positioning), not uniform. A wrong factor skews every stage at once, invisibly; a wrong rate is visible on one card. Each item type also learns its own rate from variance, so the factor never has to be estimated. |
| D-IR-3 | The rate belongs to the **item type**, never to a map cell. | A cell holds one number with no item dimension. Putting per-item minutes on the child map would force chairs and tables to share a number. |
| D-IR-4 | The sub-journey holds the **method** (steps, done-when). It never holds minutes. | The child map says *how*; the rate card says *how long*. |
| D-IR-5 | Family lives in the rate card **key**, not on the item. | One item can need two methods at one stage (cushioned chair: frame + cushion). |
| D-IR-6 | No new actor, no new lens row, no new cell field. | The lane answers *who*; the rate answers *how long per unit*. Different axes. |
| D-IR-7 | `scales_with` lives on the **stage**, not the cell. | It is a property of the work at that step, not of one actor's view of it. |
| D-IR-8 | The rate card is **pinned to the map version**, like cells. | Otherwise editing a rate silently re-estimates work already in flight. |
| D-IR-9 | Storage is **long, not wide** — one row per (version, item, stage, family). | Every map has a different number of stages. A column per stage cannot work. |
| D-IR-10 | Emgram never owns stock levels or availability. | That is the booking system's job. The catalog is a *process* list, joined by an optional `external_ref`. |

---

## 10. Gaps to close before this reaches the plan

| ID | Gap |
|---|---|
| G-1 | No `item_type` catalog: key, label, unit, default family, size label, `external_ref`. |
| G-2 | No `work_item_line`. `work_item.attributes` is flat key/value with no nesting, so lines cannot go there. |
| G-3 | No `item_rate` table, and nothing pins it to a version on publish. |
| G-4 | No `journey_stage_scaling` side table, so nothing knows which stages scale with count. |
| G-5 | Nothing rolls map durations into `planner_task.duration_minutes` — it is hardcoded to `30` today. |
| G-6 | `work_item.parent_work_item_id` exists, but nothing creates child jobs per family or rolls estimates back up. |
| G-7 | Intake never asks *what is in this order*, which is precisely why AI-created tasks come out empty. |
| G-8 | Existing `time_duration_value` on a now-`per_unit` stage silently changes meaning to *fixed setup minutes*. Those numbers need one human review pass before publish. |
| G-9 | No "estimate incomplete" surface on the plan, equivalent to `calculate_leakage`'s `incomplete_cells[]`. |

---

## 11. PRD amendments this implies

- **§4 glossary** — add *item type*, *method family*, *rate*, *order line*. Clarify that
  cell duration means **fixed per-order** minutes on a `per_unit` stage.
- **§5 scheduling shape** — "How long" is no longer a single number on the cell; it is
  `fixed + Σ(qty × rate)`.
- **LN-5** (*AI derives candidate duration modifiers… item type Y ×1.5*, currently
  **Future**) — supersede. The ×1.5 modifier shape is rejected by D-IR-2; the learning
  target is the **rate row**, not a multiplier.
- **Three durations, three owners** — unchanged, and now actually computable. Variance
  corrects the *rate*, never the map structure.

---

## 12. Open questions

1. Is **"family"** the right user-facing word, or should it be **"method"**? Same concept,
   plainer word. Not yet decided.
2. Do the bookable SKUs already split 6-ft from 4-ft tables? If not, `external_ref` is not
   1:1 and needs a small mapping step at intake.
3. Should a `per_flagged_unit` stage estimate against an expected flag rate (say 10% of
   items), or stay at zero until items are actually flagged? The first gives a usable plan;
   the second never over-books.
4. When two families at one stage have different owners, is the child-job split automatic,
   or does the planner confirm it?

---

## 13. What this unlocks

- The planner gets a real number instead of `30`, per order, derived from the map.
- Variance finally has something honest to compare against, per item and per stage.
- The intelligence layer becomes the actual source of the standard — the DNA — because
  the standard is now expressed at the granularity the work really has.
- Adding the 10th, 50th or 300th item type is a catalog row and a handful of rates.
  It is never a new map, a new lane, or a schema change.
