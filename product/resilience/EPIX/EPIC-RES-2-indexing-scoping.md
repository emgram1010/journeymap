# EPIC-RES-2 — Indexing & Tenant-Scoped Access

> ✅ **EXECUTOR MODEL — 4.6.** Fully bounded: edit `index` blocks, verify with EXPLAIN,
> copy syntax from existing table files. Lowest risk in the PRD.

**Layer:** Database · **Status:** ✅ Complete (01 audit ✅ · 02 journey_map ✅ · 03 high-volume tables ✅ · 04 child tables verified ✅ · 05 deploy verified on push)
**Scheduling:** **Parallel with** RES-1, RES-3, RES-8 · **Blocked by** RES-0
**Unblocks:** RES-4 (filtering depends on these indexes)

---

## Goal

Every list/search/filter access pattern is backed by a composite index that leads with
the tenant column, so per-account queries stay fast as global row counts grow.

## Why (resilience rationale)

Filtering pushed down to the DB (RES-4) is only fast if the index supports it. Several
high-traffic access patterns scope by `account_id` / `owner_user` but the index either
omits the tenant column or leads with the wrong field. Without tenant-leading indexes,
a scoped query still scans large portions of the table.

---

## Stories

### US-RES-2-01 — Audit access patterns vs indexes
**Change:** Map each list/search/filter query (`journey_map`, `journey_architecture`,
`workflow_execution`, log/message tables) to the index it should use.
**Acceptance:**
- A table documents each query → required index → current index → gap.

### US-RES-2-02 — Tenant-leading index on journey_map
**Change:** Ensure a composite index leads with `account_id` (then `status`,
`map_level`, `journey_architecture`, `updated_at desc`) covering list/search/dashboard.
**Acceptance:**
- Scoped `list_maps` / `search` use an index scan, not a seq scan.

### US-RES-2-03 — Tenant column on high-volume table indexes
**Change:** Add the owning tenant/parent column to the leading position of composite
indexes on `event_log`, `agent_message`, `agent_turn_log`, `agent_tool_log`,
`workflow_execution` (alongside `created_at desc`).
**Acceptance:**
- Per-account/per-conversation queries on these tables are index-backed.

### US-RES-2-04 — Child-table scoping indexes
**Change:** Confirm `journey_stage`, `journey_lens`, `journey_cell` queries by
`journey_map` are covered (cell composite already exists — verify it leads with
`journey_map`).
**Acceptance:**
- Loading a full map bundle uses index scans on all three child tables.

### US-RES-2-05 — Verify with EXPLAIN at volume
**Change:** Seed a scaled dataset and capture query plans before/after.
**Acceptance:**
- Each target query shows index usage and bounded row reads in the plan.

---

## Executor Contract (read before coding)

**Touchpoints (only):** `index = [...]` blocks in `table/journey_map.xs`,
`table/event_log.xs`, `table/agent_message.xs`, `table/agent_turn_log.xs`,
`table/agent_tool_log.xs`, `table/workflow_execution.xs`,
`table/journey_stage.xs`, `table/journey_lens.xs`, `table/journey_cell.xs`.

**Real anchors:**
- `table/journey_map.xs` index leads with `owner_user` then `account_id`, and
  `last_interaction_at` (the `list_maps` sort field) is the **4th** column — so an
  `account_id`-only scoped+sorted query is not well-served. Add/adjust a composite that
  leads with `account_id` and supports the `last_interaction_at desc` / `updated_at desc`
  sorts. Keep the existing index.
- `table/event_log.xs` only indexes `created_at desc` — no `user_id`/`account_id` index.
  Add a composite leading with the tenant column + `created_at desc`.
- `journey_cell` composite already leads with `journey_map` — just **verify**, don't change.

**Do NOT touch:** existing indexes (add alongside, never drop), or any non-index field.
No logic/query files change in this epic — schema only.

**Verify with:** seeded scaled dataset + EXPLAIN before/after on each target query →
plan shows index scan (not seq scan) and bounded rows read.

**Parity:** query **result sets are identical** before/after — only the plan changes.

**Stop-and-ask if:** Xano's index DSL can't express a needed composite/sort-order — copy
syntax from the existing blocks; if still unexpressible, ask.

## Definition of Done

- Every scoped access pattern has a tenant-leading index.
- EXPLAIN evidence attached for the top queries.
- No index regressions on write throughput beyond agreed budget.
