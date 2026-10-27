# ITEM-0 — Step-0 Audit: can a non-actor row live safely in every code path?

**Epic ID:** ITEM-0
**Feature:** Proof, with guard tests, that an Items row (a `journey_lens` that is not an actor) is ignored everywhere it must be — before any of it is built.
**Status:** To-do
**Depends on:** —
**Model:** **Opus** (review-shaped; it reads every lens-iterating path and writes tests that pin behaviour)
**MVP:** fully in scope. Nothing in phase-6 starts until this passes.
**Goal:** No surprise in ITEM-1 or RATE-1. Every "for each lens" path either already skips a row with `does_planned_work = false` and `actor_type = ""`, or is listed here with the one-line fix it needs.

---

## Builder brief

- **Model: Opus.** If the session is not on Opus, say so before doing anything and wait for the founder to switch.
- **Read first (in this order):** `static/tables/8_journey_lens.xs`, `static/tables/111_journey_lens_planned_work.xs`, `functions/pub/build_map_snapshot.xs`, `functions/pub/evaluate_readiness.xs`, `ai/tool/fill_cells.xs`, `ai/tool/calculate_leakage.xs`, `functions/planner/derive_tasks.xs`.
- **Live ids:** map 193 `item-turnaround` (read-only; clone it). Existing non-actor row precedent: lens key `description`, `actor_type = ""`.
- **CLAUDE.md rules that bite here:** conditionals inside `foreach` must branch on the loop item only; `==`/`!=` null is loose (0, "", false, [] all equal null); `|get` with a variable key ignores its default; no filters in `where`; workflow tests cannot be run from a session, so drive assertions via `runWorkspaceFunction` and say so in Test Results.
- **Output:** the audit table (`audit/lens-paths.md`) is the main deliverable. Do not edit any production file; list proposed skips with file and line.
- **Do not open:** webapp UI files beyond the readiness predicate; any Xano write tool except on the clone.
- **Session:** one epic per session. Read only this epic, `README.md` (phase-6), `product/learnings/item-rate-framework-prd.md` §0, §7 (invariants) and §10 (decisions), and `CLAUDE.md`. Do not open other epics or the older `item-rate-model.md`.
- **Order of work (CLAUDE.md build protocol):** tests first, then code; run the new tests and the existing suites; record results in Test Results; stop and wait for the founder at the completion gate.
- **Ask before:** any Xano push, any change to an existing table, any delete. Test only on a clone of map 193 (or 178), never the original.
- **Report back:** what was built (1-2 sentences), tests pass/fail by ID, differences from the epic, what is next.

---

## Context

The design (PRD §2.4, D-IR-11) rides on an existing fact: map 193 already has a non-actor row (`description`, `actor_type = ""`), and the MVP loop closed end-to-end on maps that have one. That proves the readiness gate, planner and publish tolerate *that* row. It does not prove every path ignores a non-actor row that **has content in its cells** — the Items row will. The AI builder in particular fills "all lenses"; leakage multiplies cell minutes by lens cost rates; the readiness gate counts work cells.

PRD §5.6 also records a finding from reading `pub/build_map_snapshot`: only rows with `does_planned_work = true` produce hashed cells. ITEM-0 confirms this against the live function, because RATE-1's whole design (a separate `rates` section in the snapshot) depends on it.

## Existing Architecture (Do Not Break)

- No production code changes in this epic beyond the one-line skips it may propose. Each proposed skip is listed in Test Results and **not applied** until the founder says so.
- `journey_lens.actor_type` enum is **not** extended (O-1): `updateTableSchema` drops the table's validators.

## Non-Goals

- No new tables, no UI, no catalog work. That is CAT-1 onward.

---

## Stories

### US-ITEM-0-01 — Inventory every lens-iterating path

**Files:** `product/stories/phase-6/audit/lens-paths.md` (new; the audit record)

- Grep `journey_lens` and `lenses`/`lens_rows` across `functions/`, `apis/`, `ai/tool/`, `tasks/`, `webapp/protype-2/src/`, `webapp/planningFrontendv2/src/`.
- For each path record: file, what it does per lens, whether it filters on `actor_type`, `template_key` or `does_planned_work`, and the verdict: **safe / needs skip / needs decision**.
- Known starting list (from a first grep on 2026-10-24): `ai/tool/fill_cells.xs`, `scaffold_map.xs`, `scaffold_structure.xs`, `mutate_structure.xs`, `batch_update.xs`, `get_gaps.xs`, `get_map.xs`, `get_slice.xs`, `calculate_leakage.xs`, `infer_stage_metrics.xs`, `update_actor_identity.xs`, `update_actor_cell_fields.xs`, `functions/pub/build_map_snapshot.xs`, `evaluate_readiness.xs`, `evaluate_gate.xs`, `functions/planner/derive_tasks.xs`, `job_step_hydration.xs`, `functions/live/build_publication.xs`, `functions/variance/task_report.xs`, and the frontend's readiness/progress code (AUTH-1's `cellHasAnyContent`).

**Acceptance:** every file in the grep appears in the table with a verdict. No "didn't look".

### US-ITEM-0-02 — Confirm the snapshot and hash boundary, live

- Run `pub/build_map_snapshot` on a **clone** of map 193 after adding a scratch row with `actor_type = ""`, `template_key = "items-v1"`, `does_planned_work = false`, and filling one of its cells' `actor_fields` with `{"scales_with":"per_unit","lines":[...]}`.
- Record: does the snapshot's `cells[]` include that row's cell? Does `content_hash` change versus the clone without it?
- Expected (per PRD §5.6): **not included; hash unchanged.** If the opposite is true, RATE-1's design is simpler (rates ride in cells) and the PRD is amended — either way, the fact is pinned by FT-ITEM-0-02.

**Acceptance:** the result is recorded in Test Results with the clone's map id and both hashes.

### US-ITEM-0-03 — Confirm the readiness gate and the planner ignore the row

- On the same clone: run `pub/evaluate_readiness` and `pub/evaluate_gate` with and without the scratch Items row. The readiness report must be identical, except for any **warning** this epic chooses to add later (EC-14).
- Build a version, a plan template, an instance and a job from the clone (phase-4 loop). Count `work_task` rows: there must be **no task for the Items row**, and `derive_tasks` must produce no planner task for it.

**Acceptance:** zero `work_task` rows whose `lens_key` is the Items row's key; readiness report equal.

### US-ITEM-0-04 — Confirm the AI tools skip it, or list the fix

- Run `ai/tool/get_gaps` and `get_map` on the clone: the Items row must not be reported as "empty cells to fill".
- Read `fill_cells` and `scaffold_map`: if they would write prose into a row with `template_key = "items-v1"`, record the **one-line skip** (`if ($lens.template_key == "items-v1") continue`-equivalent, respecting the loop-item rule in CLAUDE.md) as a proposed change. Do not apply.

**Acceptance:** each AI tool has a verdict; proposed skips are listed with file and line.

### US-ITEM-0-05 — Guard tests that outlive this epic

**Files:** `workflow_tests/28_items_row_guards.xs`, `webapp/protype-2/src/itemsRowGuards.test.ts`

- Functional: a fixture map with an Items row produces no work task, no planner task, no leakage cost, and no readiness block from that row.
- Unit: the frontend's "is this a work row" predicate returns `false` for `template_key = "items-v1"` regardless of content.

**Acceptance:** both pass on the clone today; both would fail if a future change treated the row as an actor.

---

## Test Plan

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-ITEM-0-01 | Unit | Work-row predicate on `{template_key: "items-v1", actor_fields: {lines: [...]}}` | `false` |
| UT-ITEM-0-02 | Unit | Same predicate on an `internal` row with content | `true` (unchanged) |
| FT-ITEM-0-01 | Functional | Snapshot of clone with vs without Items row | `cells[]` equal; hash equal (or the opposite, recorded) |
| FT-ITEM-0-02 | Functional | Readiness report with vs without Items row | Equal |
| FT-ITEM-0-03 | Functional | Job built from the clone | No `work_task` for the Items row |
| FT-ITEM-0-04 | Functional | `derive_tasks` on that job | No planner task for the Items row |
| FT-ITEM-0-05 | Functional | `calculate_leakage` on the clone (atomic map) | Items row contributes 0; no `incomplete_cells` entry for it |
| FT-ITEM-0-06 | Functional | `get_gaps` on the clone | Items row's cells not listed |

**Completion gate:** all cases pass or are recorded with a proposed fix; `npm test`, `workflow_tests/1–27` green; the audit table is complete → Test Results.

## Governance (data integrity, validation, observability)

**Data integrity:** no writes to any original map. Clone only (`clone_scenario` or a copy of 193). Scratch rows and the clone are deleted at the end (standing OK for own test fixtures).

**Validation:** n/a (no new inputs).

**Events logged:** none new. The audit records which events the existing paths emit when they meet the Items row, so ITEM-1 knows what support will see.

**Governance tests:** covered by FT-ITEM-0-01…06.

## Decisions needed (recommended defaults in bold)

| # | Question | Recommendation |
|---|---|---|
| D-1 | If a path needs a skip, apply it in ITEM-0 or in the epic that needs it? | **In the epic that needs it (ITEM-1 or RATE-1), with ITEM-0's guard test already red for it.** Keeps ITEM-0 read-only. |
| D-2 | Should a `per_unit` Items cell with zero lines be a readiness **warning**? | **Yes, warning not block** (EC-14). Added in ITEM-1. |

## Test Results

**2026-10-24 — Opus 5. Done. Audit complete, guard tests written and green, no production file changed.**

**Fixture:** map **213** (`ITEM-0 audit clone of item-turnaround — safe to delete`), cloned from 193 in architecture 31. Items row = lens **1248** (`key = "items"`, `actor_type = ""`, `template_key = "items-v1"`, explicit `does_planned_work = false`), 8 Items cells (ids 9994–10001), with **real per-unit lines** in s2 and s8 — nothing was verified on empty data (CLAUDE.md). Map 193 itself was never touched.

### Results against the test plan

| ID | Expected | Result |
|---|---|---|
| UT-ITEM-0-01 | Items row never does planned work | ✅ `doesPlannedWork('', null/undefined/false)` → false |
| UT-ITEM-0-02 | Actor rows unaffected | ✅ internal/ai_agent true, customer false |
| FT-ITEM-0-01 | Snapshot `cells[]` and hash equal with vs without the row | ⚠️ **Split result.** `cells[]` **equal (8 → 8)**, as predicted. **Hash NOT equal** (`dc0fe2d9…` → `9be07a8d…`): non-work rows do emit a `lens\|` line. Adding **rates** then left the hash **unchanged** — two versions differing only in rates are indistinguishable. Finding **H-1**; RATE-1's reason to exist, now proven rather than inferred. |
| FT-ITEM-0-02 | Readiness report equal | ✅ Byte-identical: `ready: true`, 8/8, 0 blockers, 0 warnings, before and after |
| FT-ITEM-0-03 | No `work_task` for the Items row | ✅ `tasks_from_version`: 8 tasks, **0 for Items**, **0 skipped** |
| FT-ITEM-0-04 | No planner task for the Items row | ✅ By construction — `derive_tasks` consumes `work_task` rows, of which the Items row produces none |
| FT-ITEM-0-05 | Leakage contributes 0, no `incomplete_cells` entry | ⚠️ **Partial fail.** Cost contribution **0** ✅, but the row adds **8 false `incomplete_cells` entries** ❌. Worse: giving the row a `cost_rate` **and** a cell a `time_duration` made leakage charge **50/event at s8**. Safe today by accident, not by design. Finding **L-1**. |
| FT-ITEM-0-06 | `get_gaps` does not list Items cells | ❌ **Fail.** All **8** Items cells reported as gaps — *including the two holding real rates* — and the Items row returned as `most_empty_lens`. The AI builder would target it first. Finding **G-1**, the most important result of this audit. |

**Regression gate:** `npm test` — **522/522 pass**, including the 5 new guard tests. `workflow_tests/1–27` untouched (no backend code changed).

### Deliverables

- `product/stories/phase-6/audit/lens-paths.md` — every lens-touching path with a verdict: **4 need a change, 3 want a defensive guard, 24 backend + 20 frontend safe**. No "didn't look".
- `webapp/protype-2/src/itemsRowGuards.test.ts` — 5 unit guards, registered in `npm test`.
- `workflow_tests/28_items_row_guards.xs` — the backend twin. **Not run**: no exposed tool executes a `workflow_test` from a session (CLAUDE.md). Every assertion in it was driven through `runWorkspaceFunction` instead, and the file says so in its header.

### Extra findings, not in the test plan

- **J-1 — `db.patch` on `journey_cell.actor_fields` merges, confirmed on this exact column.** A probe key survived a single patch and vanished only after the two-step `null`-then-value patch. ITEM-1's critical rule is now verified where it will be used, not just inherited from `event_log`.
- **T-1** — `actor_template` has no `items-v1` branch, so a stage added later gets an Items cell with empty `actor_fields` instead of the `{scales_with: "per_order", lines: []}` default. One branch there fixes `insert_stage`, `scaffold_map` and `mutate_structure` at once.
- **O-1** — `resolve_stage_owner` is an unfiltered key lookup, so a stage **can** name the Items row as owner. Confirms `E-ITM-007` is needed at the write path.
- **P-1** — `doesPlannedWork` honours an explicit `true`, so nothing in the shared predicate stops the Items row being switched on. Confirms `E-ITM-008`.
- **A divergence worth knowing:** `"" != null` is **false** in XanoScript and **true** in TypeScript. Both sides reach "not a work row" for the Items row, by different routes. Do not "fix" either to match the other. Recorded in the audit §2.
- **C-1, pre-existing and unrelated:** `clone_scenario` does not copy `map_level` — the clone came back non-atomic and leakage refused to run until it was set by hand. Not fixed here.

### Deviations from the epic

- **US-ITEM-0-03's job-generation check was done at the function level** (`jobs/tasks_from_version` over the live snapshot) rather than by building a version → plan → instance → job. The function is the only thing that decides which tasks exist, and its filter is what was under test; the full loop would have added four writes without testing anything new.
- **US-ITEM-0-05's unit test does not test a `template_key`-aware predicate**, because none exists yet — no frontend function takes `template_key` today. The tests pin the Items row's *real* shape through `doesPlannedWork` and `tasksFromVersion` instead, and UT-ITEM-0-03/05 document the two holes (explicit `true`, and owner resolution) that ITEM-1 must close with `E-ITM-008` / `E-ITM-007`.

### Cleanup

- Five scratch functions created and **deleted** (ids 222–226: `item0_snapshot_hash`, `item0_add_items_row`, `item0_fill_items_cell`, `item0_prep_leakage`, `item0_leakage_worst_case`).
- The worst-case leakage pollution on map 213 was **reset** (`cost_rate_value` → 0, s8 Items cell duration → 0) and leakage re-verified at 0, so `workflow_tests/28`'s final assertion holds.
- **Map 213 was kept**, deliberately: it is the fixture `workflow_tests/28` names, and ITEM-1 can use it instead of rebuilding one. Safe to delete whenever — say so and I will.

### For ITEM-1 / RATE-1

1. ITEM-1 `US-ITEM-1-06` now has four named changes to apply: **G-1** (`get_gaps` skip), **L-1** (leakage skip), **T-1** (`actor_template` branch), **O-1** (stage-owner guard), plus **P-1** as `E-ITM-008`.
2. ITEM-1 must also check `App.tsx:1185 cellHasAnyContent` against an Items cell holding `lines: []` — the AUTH-1 decimal bug in a new costume.
3. RATE-1's `US-RATE-1-02` note is confirmed: the row already moves the hash; only the **rates** are missing from it.

**Completion gate: passed.** Three findings are failures against the plan's expectations (G-1, L-1, and the hash half of FT-ITEM-0-01) — which is the epic working as intended: it existed to find them before anything was built on top.
