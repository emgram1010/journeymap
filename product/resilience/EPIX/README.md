# Resilience Epics — Index

> Refactor program to make emgram hold up at 100k–1M+ records.
> **Read first:** `../resilience-prd.md` (scope, parallelization matrix, Snag Protocol)
> and `../EXECUTOR-PLAYBOOK.md` (how to run a story, model routing).

Each epic ends with an **Executor Contract** (real touchpoints, do-NOT-touch, verify-with,
parity). Each epic's title carries an **EXECUTOR MODEL** banner — obey it before assigning work.

## Model legend

- ✅ **4.6** — fully bounded, syntax exists in the repo to copy.
- 🟡 **4.6 with guardrails** — a higher model resolves one open decision first, then 4.6 implements.
- 🔴 **Higher model / human** — judgment or unproven platform capability; do **not** start on 4.6.

## The nine epics

| Epic | Title | Category | Model | Blocked by |
|---|---|---|---|---|
| [RES-0](EPIC-RES-0-consolidation.md) | Source-of-Truth Consolidation | Maintenance | 🔴 | — (gate, first) |
| [RES-1](EPIC-RES-1-data-integrity.md) | Data Integrity & Constraints | DB | 🟡 | RES-0 |
| [RES-2](EPIC-RES-2-indexing-scoping.md) | Indexing & Tenant-Scoped Access | DB | ✅ | RES-0 |
| [RES-3](EPIC-RES-3-table-lifecycle.md) | High-Volume Table Lifecycle | DB | 🔴 | RES-0 |
| [RES-4](EPIC-RES-4-filtering-pagination.md) | DB-Side Filtering & Pagination | Logic | 🟡 | RES-0, RES-2 |
| [RES-5](EPIC-RES-5-hotpath-denesting.md) | Hot-Path De-Nesting & Batch Writes | Logic | ✅ | RES-0, RES-1 |
| [RES-6](EPIC-RES-6-resilience-patterns.md) | Resilience Patterns: Idempotency & Errors | Logic | 🔴 | RES-0 |
| [RES-7](EPIC-RES-7-frontend-scale.md) | Frontend Scale: Virtualization & Pagination | Frontend | 🟡 | RES-0, RES-4 |
| [RES-8](EPIC-RES-8-observability.md) | Observability & Slow-Query Telemetry | Ops | 🟡 | RES-0 |

## Sequencing

- **Gate:** RES-0 runs alone, first. Nothing else starts until the canonical file set is named.
- **Critical path:** RES-0 → RES-2 → RES-4 → RES-7.
- **Can run in parallel** (after RES-0): RES-1, RES-2, RES-3, RES-8.
- **Can run in parallel** with each other: RES-4, RES-5, RES-6.
- **Why the key edges exist:**
  - RES-4 needs RES-2's indexes so its `where`/pagination is actually fast.
  - RES-5 needs RES-1's unique constraint to safely collapse the cell-lookup loop.
  - RES-7 needs RES-4's paginated/scoped endpoints to consume.

## Suggested order of execution

1. **RES-0** (🔴 higher model) — name the canonical set; unblocks everything.
2. **RES-2** (✅ 4.6) — lowest risk; indexes the critical path.
3. **RES-1** (🟡) — dedupe→constraint; higher model reviews the dedupe PR.
4. **RES-5** (✅ 4.6, with parity fixture) — de-nest hot paths.
5. **RES-4** (🟡) — resolve the `intent` + pagination decisions, then 4.6 implements.
6. **RES-6 / RES-3** (🔴) — transaction + lifecycle design on a higher model.
7. **RES-7** (🟡) — frontend, after RES-4 ships its contract.
8. **RES-8** (🟡) — pick the telemetry sink, then 4.6 wires emit calls.
