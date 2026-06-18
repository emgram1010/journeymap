# EPIC-RES-5 — Hot-Path De-Nesting & Batch Writes

> ✅ **EXECUTOR MODEL — 4.6, but ONLY after you give it the parity fixture.** With a
> golden-output fixture as the gate and `tools/2_get_map_state.xs` as the pattern, this is
> pure bounded execution. Without the fixture, do not start.

**Layer:** Logic · **Status:** Not started
**Scheduling:** **Parallel with** RES-4, RES-6, RES-3, RES-8
**Blocked by** RES-0, RES-1

---

## Goal

Replace per-item query loops and nested-loop joins in the write/compute hot paths with
single bounded queries plus in-memory keyed lookups.

## Why (resilience rationale)

`fill_cells` runs one `db.query` + one `db.patch` **per** update — `2N` round-trips for
N cells. `calculate_leakage` is a triple-nested `foreach` (stage × cell × lens), i.e.
O(n³). `get_map_state` already shows the correct pattern: query once, build a lookup
dict, join in memory. This epic applies that pattern everywhere it's missing. (Depends
on RES-1's uniqueness guard so a keyed cell lookup is unambiguous.)

---

## Stories

### US-RES-5-01 — Batch the fill_cells lookup
**Change:** Load all cells for the map once, build a `(stage_id|lens_id) → cell` map,
and resolve each update against it instead of a per-update `db.query`.
**Acceptance:**
- N updates issue at most `1` read query plus `matched` patches (no `2N`).
- Skip logic (locked/confirmed) is preserved.

### US-RES-5-02 — Batch the writes
**Change:** Where the platform supports it, group the patches; otherwise ensure only
matched cells are written (no write for unmatched/duplicate updates).
**Acceptance:**
- Unmatched updates produce zero writes.
- Returned applied/skipped counts are unchanged in meaning.

### US-RES-5-03 — De-nest calculate_leakage
**Change:** Build a `lens_id → lens` dict and a `stage_id → [cells]` dict once, then a
single pass to compute per-event/monthly/annual/3yr figures.
**Acceptance:**
- No nested cell×lens loop remains.
- Output values match the previous implementation on fixture maps.

### US-RES-5-04 — De-nest remaining tool loops
**Change:** Audit `batch_update`, `batch_set_status`, and similar tools for inner
`db.query` calls inside `foreach`; convert to load-once + in-memory match.
**Acceptance:**
- No write tool issues a DB query inside a per-item loop.

### US-RES-5-05 — Complexity regression test
**Change:** Add tests asserting query count scales with input size as O(1)/O(n), not
O(n) queries or O(n³) compute.
**Acceptance:**
- A test fails if a per-item query loop is reintroduced.

---

## Executor Contract (read before coding)

**Touchpoints (only):**
- `tools/76_calculate_leakage.xs` — nested `foreach` at lines ~62 (stages), ~68 (cells),
  ~80 (lenses). De-nest to: build a `lens_id → lens` dict + `stage_id → [cells]` dict
  once, then single pass.
- `tools/51_fill_cells.xs` — the `db.query journey_cell` inside the `foreach` loop.
- `tools/5_batch_update.xs`, `tools/10_batch_set_status.xs` — same per-item-query pattern.
- **Pattern to copy:** `tools/2_get_map_state.xs` already builds `stage_map`/`lens_map`
  lookups correctly — mirror its approach.

**PARITY SPEC — `calculate_leakage` math must be preserved byte-for-byte:**
- Time→hours: `minutes`→`/60`, `days`→`×8`, `weeks`→`×40`, `hours`→as-is.
- Cell cost by `cost_rate_unit`: `per_event`→`rate` (flat); `per_minute`→`hours×(rate×60)`;
  `per_day`→`hours×(rate/8)`; `per_week`→`hours×(rate/40)`; else→`hours×rate`.
- Rollups: `annual = per_event × frequency`; `monthly = annual / 12`; `3yr = annual × 3`.
- `incomplete_cells[]` pushes `{stage_key, lens_id, missing}` where `missing` is
  `"cost_rate"` or `"time_duration"`. **Do not change this shape or the math.**

**Do NOT touch:**
- `fill_cells` skip-logic for `is_locked == true` / `status == "confirmed"`.
- The `applied`/`skipped` count semantics returned by the batch tools.

**Verify with:**
- Golden-fixture test: run each tool on a real map id, output **byte-matches** the
  pre-refactor output.
- Query-count test: N updates → ≤ `1 + matched` queries (fails if a per-item query
  loop is reintroduced).

**Parity:** identical outputs on fixtures; only query/loop structure changes.

## Definition of Done

- Hot paths issue bounded query counts; leakage is single-pass.
- Behavior parity proven against fixtures.
- Query-count guard tests in CI.
