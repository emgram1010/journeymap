# EPIC-RES-8 — Observability & Slow-Query Telemetry

> 🟡 **EXECUTOR MODEL — 4.6 OK once a higher model picks the telemetry sink
> (stop-and-ask).** After the sink is chosen, adding emit calls is mechanical → 4.6.

**Layer:** Ops · **Status:** Not started
**Scheduling:** **Parallel with** everything (RES-1…RES-7) · **Blocked by** RES-0

---

## Goal

Make scale problems visible before they become outages: query row-counts, latency, batch
sizes, and table growth are measured and alertable. This epic is the evidence base that
proves the other epics worked.

## Why (resilience rationale)

You cannot defend a scale target you cannot see. Several findings in this PRD (full-table
reads, `2N` writes, unbounded log growth) are invisible without instrumentation. RES-8
provides the row-count and latency telemetry that the success metrics in the PRD depend
on, and it runs in parallel with everything since it changes no behavior.

---

## Stories

### US-RES-8-01 — Query row-count & latency logging
**Change:** Instrument read endpoints to record rows scanned/returned and duration.
**Acceptance:**
- Each list/search call emits rows-returned + latency.
- A full-table read is detectable from telemetry (validates RES-4).

### US-RES-8-02 — Batch write metrics
**Change:** Record query/patch counts per batch tool invocation.
**Acceptance:**
- `fill_cells` query-count is observable (validates RES-5's `1+matched`).

### US-RES-8-03 — Table growth & retention dashboards
**Change:** Track row counts and storage for high-volume tables and the prune-job
outcomes.
**Acceptance:**
- Growth and post-prune size are charted (validates RES-3).

### US-RES-8-04 — Slow-query alerting
**Change:** Alert when a query exceeds a latency/row-count threshold.
**Acceptance:**
- A regression that reintroduces an O(table) read fires an alert.

### US-RES-8-05 — Cross-tenant access canary
**Change:** Add a periodic check asserting list/search endpoints never return
cross-tenant rows.
**Acceptance:**
- The canary fails loudly if scoping (RES-4-01) regresses.

---

## Executor Contract (read before coding)

**Touchpoints (only):** read paths in `tools/54_list_maps.xs`,
`api/journey_map/journey_map/search_GET.xs`; batch tools `tools/51_fill_cells.xs`,
`tools/5_batch_update.xs`; plus the telemetry emit point (see stop-and-ask). The existing
`table/event_log.xs` (action + metadata JSON) may be the sink for app-level events.

**⚠ Top stop-and-ask (do FIRST):** Confirm the **telemetry sink** — Xano's built-in
request history, a metrics table (`event_log`?), or an external service. Do not assume.
This is instrumentation only.

**Do NOT touch:** any business logic, query results, or response shapes. Adding
instrumentation must not change behavior — if you can't measure without changing
behavior, stop and ask.

**Verify with:** trigger a known full-table read → it appears in telemetry as high
rows-returned; trigger a `fill_cells` batch → query-count is recorded; the cross-tenant
canary (US-RES-8-05) fails when scoping is deliberately broken in a test.

**Parity:** zero behavior change — identical outputs with telemetry on or off.

**Note:** this epic is the **evidence base** for the PRD success metrics and validates
RES-3/4/5 — keep metric names aligned with those epics' claims.

## Definition of Done

- Read/write/table telemetry live and dashboarded.
- Threshold alerts wired for slow queries and scoping regressions.
- Metrics back every success metric claimed in the PRD.
