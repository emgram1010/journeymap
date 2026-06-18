> frontend — without breaking existing maps.

---

## Problem

The current architecture is correct for prototype volumes but has scale cliffs that
will degrade or break as record counts grow into the hundreds of thousands and beyond:

- **Logic** loads whole tables into memory and filters in `foreach` (`list_maps`,
  `search`), runs `2N` queries per batch write (`fill_cells`), and uses triple-nested
  loops (`calculate_leakage`). These are O(table) and O(n³) at runtime.
- **Database** lacks a uniqueness guard on `journey_cell (journey_map, stage, lens)`,
  tenant columns are missing from several composite indexes, and the high-volume
  append-only tables (`event_log`, `agent_message`, `agent_turn_log`,
  `agent_tool_log`, `workflow_execution`) have no retention or partitioning.
- **Frontend** renders full map bundles and unbounded lists with no virtualization or
  pagination.
- **Maintenance** — source files are duplicated across mirrored directories
  (`table/`↔`tables/`, `api/`↔`apis/`, `tools/`↔`ai/tool/`), so refactors risk editing
  the dead copy.

## Goal

Every read and write path stays sub-linear and tenant-scoped, high-volume tables have a
lifecycle, the frontend stays responsive on large maps, and there is exactly one source
of truth per artifact — all delivered without forcing existing maps to republish.

## Non-Goals

- No change to the journey-map domain model semantics (stages × lenses × cells).
- No multi-region / sharding work in this phase.
- No rewrite of the AI agent prompt logic (only its data-access patterns).

---

## Resilience Pillars

| Pillar | Outcome |
|---|---|
| **Integrity** | Bad/duplicate data cannot be written; derived FKs stay consistent. |
| **Scoped access** | Every list/search is tenant-filtered and index-backed. |
| **Bounded work** | No query is O(table); writes are batched; loops are de-nested. |
| **Lifecycle** | High-volume tables are partitioned and pruned. |
| **Graceful failure** | Writes are idempotent; partial failures are recoverable. |
| **Single source of truth** | One canonical directory per artifact; observable. |

---

## Epic Index

| Epic | Layer | Summary |
|---|---|---|
| [RES-0](EPIX/EPIC-RES-0-consolidation.md) | Maintenance | Collapse duplicate dirs to one source of truth |
| [RES-1](EPIX/EPIC-RES-1-data-integrity.md) | Database | Unique constraints + derived-FK consistency |
| [RES-2](EPIX/EPIC-RES-2-indexing-scoping.md) | Database | Tenant-scoped composite indexes |
| [RES-3](EPIX/EPIC-RES-3-table-lifecycle.md) | Database | Partitioning + retention for log/message tables |
| [RES-4](EPIX/EPIC-RES-4-filtering-pagination.md) | Logic | Push filters to DB + pagination |
| [RES-5](EPIX/EPIC-RES-5-hotpath-denesting.md) | Logic | Batch writes + de-nest hot loops |
| [RES-6](EPIX/EPIC-RES-6-resilience-patterns.md) | Logic | Idempotency, transactions, error handling |
| [RES-7](EPIX/EPIC-RES-7-frontend-scale.md) | Frontend | Virtualization, pagination, caching |
| [RES-8](EPIX/EPIC-RES-8-observability.md) | Ops | Slow-query telemetry + metrics |

---

> **Executor note:** This work will be built by a cost-efficient model (Sonnet 4.6)
> driving Augment. Before writing any code, that model **must** read
> [`EXECUTOR-PLAYBOOK.md`](EXECUTOR-PLAYBOOK.md) and the `## Executor Contract` block at
> the bottom of each epic. The Ground Rules and Snag Protocol below are binding.

## Parallelization & Sequencing Matrix

This is the canonical scheduling contract. "Parallel with" means the epics touch
disjoint files/concerns and can be worked simultaneously. "Blocked by" means the
dependency must merge first.

| Epic | Can run in PARALLEL with | Must run AFTER (sequential dep) |
|---|---|---|
| **RES-0** | — (run alone, first) | none — **this is the gate** |
| **RES-1** | RES-2, RES-3, RES-8 | RES-0 |
| **RES-2** | RES-1, RES-3, RES-8 | RES-0 |
| **RES-3** | RES-1, RES-2, RES-4, RES-5, RES-6, RES-7, RES-8 | RES-0 |
| **RES-4** | RES-5, RES-6, RES-3, RES-8 | RES-0, RES-2 |
| **RES-5** | RES-4, RES-6, RES-3, RES-8 | RES-0, RES-1 |
| **RES-6** | RES-4, RES-5, RES-3, RES-8 | RES-0 |
| **RES-7** | RES-3, RES-8 | RES-0, RES-4 |
| **RES-8** | everything (RES-1…RES-7) | RES-0 |

### Rules in plain language

1. **RES-0 is a hard gate.** Nothing else starts until the duplicate directories are
   collapsed — otherwise every later epic risks editing a dead copy.
2. **RES-1, RES-2, RES-3 are fully parallel** with each other (additive DB-schema work,
   disjoint tables/indexes).
3. **RES-4 is blocked by RES-2** — DB-side filtering is only fast once the tenant
   composite indexes exist.
4. **RES-5 is blocked by RES-1** — collapsing the per-cell lookup loop into a single
   keyed query is only safe once the cell uniqueness constraint guarantees one row per
   (map, stage, lens).
5. **RES-4, RES-5, RES-6 run in parallel** but all touch write/read paths — coordinate
   merges on shared endpoint files.
6. **RES-7 is blocked by RES-4** — the frontend can only consume paginated/filtered
   endpoints once they exist.
7. **RES-8 runs in parallel with everything** after RES-0 (pure instrumentation, no
   behavior change).

### Recommended build order (critical path)

```
RES-0  →  ┌ RES-1 ┐         ┌ RES-5 ┐
          ├ RES-2 ┤  →  RES-4 → RES-7
          └ RES-3 ┘         ├ RES-6 ┤
                            └ (RES-8 in parallel throughout) ┘
```

Critical path = **RES-0 → RES-2 → RES-4 → RES-7**. RES-1/RES-3/RES-5/RES-6/RES-8 fill
in around it without extending the path.

---

## AI Executor Ground Rules (binding)

These apply to every story in every epic. Violating any of them is a failed PR.

1. **Read before you write.** Open and read the real file. Never edit from memory or
   assume a function/field/path exists — confirm it in the file first.
2. **Never invent Xano DSL.** Copy `.xs` syntax (db.query, where, index types,
   filters) from an existing file in this repo. If the exact syntax for an operation
   is not present anywhere in the repo, **stop and ask** — do not guess.
3. **Confirm the canonical copy.** The live source is the file inside a directory
   listed in `.xano/config.json`'s `paths` block — currently `tables/`, `apis/`,
   `functions/`, `tools/`, `workflow_tests/`, `agents/`, `mcp_servers/`. Edit only
   that copy. If you find yourself in `table/`, `api/`, `function/`, or
   `workflow_test/`, RES-0 is not done — stop.
4. **One story = one PR = one focused diff.** Do not bundle stories. Do not "while I'm
   here" fix unrelated code.
5. **No response-shape change without its paired frontend story** (RES-4 ↔ RES-7).
6. **DB constraints are always preceded by a dedupe/backfill story** — never add a
   unique constraint before the data is proven clean.
7. **Refactors must prove parity.** A behavior-changing refactor (RES-5) must produce
   byte-identical output against a fixture before merge.
8. **Never modify a cell with `status == "confirmed"` or `is_locked == true`** unless a
   story explicitly says so.
9. **Tests are the gate, not your judgment.** A story is done when its `Verify with`
   command passes — not when the code "looks right."

## Snag Protocol (anti-hallucination keystone)

When you hit a snag — missing info, uncertain syntax, a field that isn't where expected,
a platform capability you're unsure of:

> **STOP. State the assumption. Ask. Do not guess.**

Specifically, do not:
- scaffold a plausible-looking placeholder and move on,
- invent a Xano/SQL feature to make the code compile,
- widen scope to "fix" something nearby,
- silently drop a filter/branch you don't understand (e.g. the `intent` filter in
  `list_maps`) — flag it instead.

Known snag triggers already identified (each is a **stop-and-ask**, not a guess):
- Whether Xano supports native table partitioning (RES-3).
- Whether Xano exposes a transaction primitive for atomic batch writes (RES-6).
- Where `intent` actually lives on `journey_map` — it is referenced in `list_maps` but
  is not a column in `table/journey_map.xs` (RES-4).
- Which telemetry sink to emit metrics to (RES-8).

## Success Metrics

- `list_maps` / `search` read a bounded page, never the full table (verified by query
  row-count telemetry from RES-8).
- `fill_cells` of N cells issues `1 + matched` writes, not `2N`.
- `calculate_leakage` runs in a single pass (no nested cell×lens loop).
- Zero cross-tenant rows returnable from any list/search endpoint.
- High-volume tables have an enforced retention window and time-based partitions.
- p95 map-load and list latency stays flat as record count grows 10×.

## Risks

1. **Migration safety** — adding a unique constraint can fail if duplicates already
   exist. Mitigation: dedupe-scan + backfill step inside RES-1 before constraint apply.
2. **Behavior drift during dedup** — RES-0 must verify the two mirrored copies are
   byte-identical (or reconcile) before deleting one.
3. **Pagination contract change** — RES-4 changes response shape; RES-7 must land in the
   same release train to avoid a broken frontend.
