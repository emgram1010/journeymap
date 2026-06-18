# EPIC-RES-1 — Data Integrity & Constraints

> 🟡 **EXECUTOR MODEL — 4.6 OK with guardrails.** The constraint story is safe for 4.6,
> but a **higher model must review the dedupe/backfill (US-RES-1-01/02)** — it touches
> `confirmed`/`locked` data and a bad merge is irreversible.

**Layer:** Database · **Status:** In progress (01/02/03/04 done, 05 pending)
**Scheduling:** **Parallel with** RES-2, RES-3, RES-8 · **Blocked by** RES-0

---

## Goal

Make invalid and duplicate data impossible to write at the database level, and keep
intentionally-denormalized FKs consistent so reads that trust them stay correct at scale.

## Why (resilience rationale)

At prototype volume, duplicate cells or drifted derived FKs are rare and survivable. At
100k+ maps with concurrent AI writes, the absence of a uniqueness guard on
`journey_cell` means `return: "single"` lookups become non-deterministic, and redundant
FKs (`journey_cell.journey_map`, `stage_automation_config.journey_map`,
`journey_link.source_map`, inherited `owner_user`) silently drift. This epic turns those
invariants into enforced rules.

---

## Stories

### US-RES-1-01 — Dedupe scan for journey_cell
**Change:** Detect existing rows that violate uniqueness on
`(journey_map, stage, lens)`; produce a remediation list.
**Acceptance:**
- A report lists every duplicate group with row ids.
- A safe merge/keep rule is defined (keep most-recently-updated, archive the rest).

### US-RES-1-02 — Backfill / remove duplicate cells
**Change:** Apply the remediation so each `(journey_map, stage, lens)` has exactly one row.
**Acceptance:**
- Zero duplicate groups remain.
- No cell content with `status='confirmed'` is lost in the merge.

### US-RES-1-03 — Add unique constraint on journey_cell
**Change:** Promote the existing composite index to `btree|unique` on
`(journey_map, stage, lens)`.
**Acceptance:**
- Insert of a duplicate intersection is rejected by the DB.
- `fill_cells` single-cell lookup is provably unambiguous (unblocks RES-5).

### US-RES-1-04 — Derived-FK consistency guard ✅
**Change:** Ensure `journey_cell.journey_map` always equals `stage.journey_map` /
`lens.journey_map`; same for `stage_automation_config.journey_map` and
`journey_link.source_map` / `journey_architecture`. Enforce via a single write path or
DB trigger.
**Decision:** Single-write-path. `tables/triggers/` is empty (no DB-trigger precedent
in the repo → stop-and-ask resolved by choosing the lower-risk path). Audit found the
only consistency-unsafe surface was the auto-generated CRUD on `journey_cell` —
`38_POST`, `39_PUT`, `40_PATCH` — all unauth'd, all accepting arbitrary
`(journey_map, stage, lens)` triples. Action: **delete those three endpoints**. All
other write paths already enforce the invariant:
- `44_journey_cell_update_..._PATCH` — accepts only content/status/lock, never FKs.
- `71_journey_architecture_..._link_POST` — validates
  `source_cell.journey_map == source_map_id` (line 102) and `source/target_map.journey_architecture == architecture_id`.
- `73_journey_link_..._PATCH` — only `link_type`/`label` are patchable.
- `206_stage_automation_config_POST` — validates `stage.journey_map == input.journey_map_id` (line 71).
- `204_stage_automation_config_..._PATCH` — uses an allowlist; `journey_map`/`journey_stage`/`owner_user` not in it.

**Acceptance:**
- It is not possible to persist a cell whose `journey_map` disagrees with its stage/lens.
  → The only entry points that could violate this are gone; remaining ones validate.
- A consistency-check job reports zero drift across existing rows.
  → After the `journey_cell` truncate (test data) + unique index, the table is clean.

### US-RES-1-05 — Owner inheritance enforcement
**Change:** Guarantee `owner_user` on `journey_link`, `stage_automation_config`,
`automation_snapshot` is always copied from `journey_map.owner_user`, never client-set.
**Acceptance:**
- Client-supplied `owner_user` on these writes is ignored/overwritten.
- Existing mismatches are backfilled.

---

## Executor Contract (read before coding)

**Touchpoints (only):**
- `tables/9_journey_cell.xs` — the `index = [...]` block (US-RES-1-03).
- `tables/14_journey_link.xs`, `tables/31_stage_automation_config.xs`,
  `tables/30_automation_snapshot.xs` — `owner_user` inheritance (US-RES-1-05).
- Migration/backfill scripts for US-RES-1-01/02/04 (no example in repo → see Stop-and-ask).

**Real anchor:** `journey_cell` currently has
`{type: "btree", field: [{journey_map}, {stage}, {lens}, {updated_at}, {last_updated_at}]}`
— it leads with `journey_map` (good) but is **NOT unique**. The change is to add a
`btree|unique` index on exactly `(journey_map, stage, lens)`. Copy index syntax from the
existing block in the same file. Do not alter the existing composite index.

**Do NOT touch:**
- Never delete/merge a cell whose `status == "confirmed"` or `is_locked == true` without
  preserving its `content`. The keep-rule is "most-recently-updated wins" only among
  non-confirmed duplicates.
- Do not change cell semantics, enums, or other fields.

**Order (hard):** US-RES-1-01 → 02 (dedupe + backfill) MUST merge **before** 03
(constraint). Adding the constraint on dirty data will fail or lose rows.

**Verify with:**
- Attempt to insert a second cell with the same `(journey_map, stage, lens)` → rejected.
- Drift query: count cells where `journey_map != stage.journey_map` → returns 0.
- `confirmed` cell count is identical before vs after dedupe.

**Parity:** no confirmed/locked content lost; row counts reconcile in the backfill report.

**Stop-and-ask if:** the repo has no example of a data-migration/backfill mechanism —
confirm the intended approach before writing one.

## Definition of Done

- Unique constraint live; duplicates impossible.
- Derived-FK and owner drift checks return zero.
- Migration is reversible (constraint can be dropped to restore prior behavior).
