# EPIC-RES-3 — High-Volume Table Lifecycle

> 🔴 **EXECUTOR MODEL — HIGHER MODEL. Do NOT run on 4.6.** Depends on Xano
> partitioning/scheduled-job support that the repo does not demonstrate — high risk 4.6
> hallucinates raw Postgres DDL. Decide the mechanism up top; 4.6 may implement after.

**Layer:** Database · **Status:** Not started
**Scheduling:** **Parallel with** everything after RES-0 · **Blocked by** RES-0

---

## Goal

Give the append-only, fastest-growing tables a defined lifecycle — partitioning and
retention — so they never become an unbounded scan or storage liability.

## Why (resilience rationale)

These tables dwarf everything else and only grow: `event_log`, `agent_message`,
`agent_turn_log`, `agent_tool_log`, `workflow_execution`. With no retention or
partitioning, deletes and time-range queries eventually scan the whole table, vacuum/IO
costs climb, and the working set stops fitting in memory. A lifecycle keeps hot data
small and cold data cheap.

---

## Stories

### US-RES-3-01 — Classify tables by growth & access
**Change:** For each high-volume table, document write rate, dominant query window
(e.g. "last 30 days"), and whether old rows are ever read.
**Acceptance:**
- A table records growth class and a proposed retention window per table.

### US-RES-3-02 — Time-based partitioning
**Change:** Partition the high-volume tables by `created_at` (monthly) so queries and
pruning operate on a single partition.
**Acceptance:**
- New writes land in the current partition.
- A time-windowed query touches only the relevant partition(s) in EXPLAIN.

### US-RES-3-03 — Retention / archival policy
**Change:** Define and implement a TTL: rows past the retention window are archived to
cold storage or dropped (per table policy from US-RES-3-01).
**Acceptance:**
- A scheduled job prunes/archives expired partitions.
- Retention windows are configurable, not hard-coded per row.

### US-RES-3-04 — JSON payload size guard
**Change:** Cap / monitor oversized JSON blobs (`agent_message.content`,
`workflow_execution.stage_outputs`, `automation_snapshot.graph`) so a single row can't
balloon a partition.
**Acceptance:**
- Oversized payloads are flagged; a size budget is documented.

### US-RES-3-05 — Verify pruning at volume
**Change:** Seed scaled data, run a retention cycle, confirm space reclaimed and query
latency stable.
**Acceptance:**
- Post-prune table size and p95 query latency match targets.

---

## Executor Contract (read before coding)

**Touchpoints (only):** `table/event_log.xs`, `table/agent_message.xs`,
`table/agent_turn_log.xs`, `table/agent_tool_log.xs`, `table/workflow_execution.xs`, plus
the scheduled prune/archive job (no example in repo → Stop-and-ask).

**⚠ Top stop-and-ask (do FIRST):** Confirm whether Xano supports **native table
partitioning** and **scheduled jobs**. There is no partitioning example in this repo.
**Do NOT emit raw Postgres `CREATE TABLE ... PARTITION BY` DDL** or invent a Xano feature.
If native partitioning is unavailable, stop and ask — the fallback (e.g. a rolling
archive table + scheduled delete) is a design decision, not a guess.

**Do NOT touch:** table field schemas, FKs, or any read/write logic. Lifecycle config
only. Never delete rows outside the agreed retention window.

**Verify with:** seed scaled data → run one retention cycle → confirm space reclaimed and
a time-windowed query (EXPLAIN) touches only the relevant partition(s)/window.

**Parity:** data **inside** the retention window is untouched and identical; only
expired/cold data is moved or dropped.

**Retention is configurable:** windows live in config, never hard-coded per row.

## Definition of Done

- All five tables partitioned by time with an enforced retention window.
- A scheduled prune/archive job is live and observable (ties to RES-8).
- Time-windowed reads touch bounded partitions.
