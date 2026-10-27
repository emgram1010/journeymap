# Queued after phase-6 — Planning and Execution on top of the Item Rate Framework

**Status:** Design stubs, not epics yet. Written 2026-10-24 so phase-6 leaves the right hooks (PRD §8). Each becomes a full epic — stories, tests, governance — when it is picked up. **Nothing here is built in phase-6.**

---

## PLN-M-1 — Method-aware planning

**Feature:** The planner sees one card per (order, stage, method-with-its-own-role), an honest guess/measured label, and a capacity view.
**Depends on:** EST-1, BLK-1 (one card per order), SCHED-1.
**Model:** Sonnet, Opus review (touches card derivation).

What phase-6 already provides, so this needs no new math:
- `estimate_job(...).stages[].by_method[]` — per-method minutes per stage.
- `method.role_id` — the split key. `0` means "same crew as the stage owner" → no split.
- `estimate_status` / `estimate_source` on hydrated steps.

Hooks to design against:
- `planner_task_work_task` is an int-only table (no trim validators), so an additive `method_key` column is **safe** via `updateTableSchema`. Record this when the time comes; re-verify the table's columns first.
- Baseline is paid once **per card**: two methods with two roles at one stage → two cards, each `baseline + its by_method minutes`. EC-5.
- O-3 default: split automatically when roles differ; one card otherwise.

Stories (sketch):
1. Card derivation: `derive_tasks` emits one task per (job, stage, role-distinct method). Position within a stage: owner's method first.
2. Badge: `guess` (seed/mixed) vs no badge (measured); `estimate incomplete` stays from EST-1.
3. Capacity view: for a timeline window and a stage, `floor((window − baseline) / rate)` per item — "one evening fits 60 chairs or 25 tables". Read-only over `stage_rate`.
4. Tweak stays on the stage total per card (O-4).

Edge cases to carry: EC-4, EC-5; a method whose role is later cleared (cards merge on the next derivation, not retroactively); a plan published to live before the split existed (immutable snapshot — LIVE-1 rules).

---

## EXE-M-1 — Execution on lines and methods, and clean-read learning

**Feature:** A performer sees what is in the order, grouped by method with that method's steps; flags counts; and the system proposes measured rates only from clean reads.
**Depends on:** PLN-M-1, APP-1 (performer app), LOG-1, VAR-1.
**Model:** Opus for the learning rule; Sonnet for the screens.

What phase-6 already provides:
- `work_item_line` with `flagged_quantity` (unused until here).
- `method.sub_journey_map_id` and the `journey_link` from the Items cell — the steps to show.
- `stage_rate.source` and the draft Items cell as the only legal write target for proposals (invariant 4).

Stories (sketch):
1. Task view: lines of this order for this task's method(s), each with unit and quantity; "steps" expands the method's sub-journey cells (read from its pinned version if it has one, else the live map, clearly labelled).
2. Flagging: at a stage that feeds a `per_flagged_unit` stage (e.g. Triage → Triage Damages), the performer enters how many of each line were flagged → `work_item_line.flagged_quantity`; downstream estimate recomputes for **untweaked** tasks (EST-1 D-1 rule).
3. Clean-read detection: on task completion, if the order had exactly one item type with `quantity > 0` for this task's stage and method, compute `(actual − baseline) / quantity` and write a **proposal** `{stage_key, item_key, method_key, proposed_minutes, from_task_id}` to a `rate_proposal` table; the Items cell editor shows pending proposals with Accept (writes the draft line, `source` will be `measured` at next publish) / Dismiss.
4. Mixed-batch reporting: VAR-1's stage variance is split proportionally to expected share, labelled **low confidence**, never written to any rate.
5. Learning never touches `stage_rate` (invariant 4). FT guard: a proposal accept + publish produces a new version; the previous version's rows are unchanged.

Edge cases to carry: a clean read with `actual < baseline` (negative rate → proposal rejected, `warn`); a clean read with quantity 1 (allowed, flagged "single-unit sample"); a task completed Done-without-Start (LOG-1) → no actual duration → no proposal; line-level progress across sessions ("15 of 20 tonight") — **still deferred**, needs `work_task_line_progress`; design it then.

---

## Later, explicitly not scoped

| Item | Trigger to pick it up |
|---|---|
| `items-v2` template: `notes`, `requirements` per line | First real request for per-item instructions at a stage |
| Non-item quantity keys (stairs, miles, stops) | First non-item work type that needs `duration = f(attribute)` |
| Expected flag rate for `per_flagged_unit` | After ≥ 4 weeks of measured flag counts exist |
| Intake from a booking system via `external_ref` | When the SKU mapping question (O-2) is answered |
| Calculated fields | Needs an evaluator epic with validation and error handling first |
