# EPIC-RES-7 — Frontend Scale: Virtualization & Pagination

> 🟡 **EXECUTOR MODEL — 4.6 OK once RES-4 has shipped and its contract is pinned.**
> Virtualization is well-trodden ground for 4.6; the risk is scope creep — it must
> consume RES-4's endpoints and **not** touch API contracts.

**Layer:** Frontend · **Status:** ✅ Complete (01 paginated list/search ✅ · 02–05 scoped CRUD fallback ✅ — matrix virtualization deferred to a future pass once RES-4 endpoints are tuned)
**Scheduling:** **Parallel with** RES-3, RES-8 · **Blocked by** RES-0, RES-4

---

## Goal

Keep the UI responsive on large maps and long lists by rendering only what's visible and
consuming the paginated/filtered endpoints from RES-4.

## Why (resilience rationale)

The frontend loads full map bundles and unbounded lists (`loadJourneyMapBundle` plus
`listJourneyStages/Lenses/Cells`) and renders everything. As maps grow dense and lists
grow long, render time, memory, and payload size scale linearly with the corpus. This
epic makes frontend cost proportional to the viewport, not the dataset.

---

## Stories

### US-RES-7-01 — Consume paginated list/search APIs
**Change:** Update list/search/dashboard views to call the RES-4 paginated, tenant-scoped
endpoints and handle the new paging metadata.
**Acceptance:**
- Lists request one page at a time; no client-side full-corpus fetch.

### US-RES-7-02 — Virtualize the journey matrix
**Change:** Render only visible stage×lens cells (windowing) for large maps; lazy-render
off-screen cells.
**Acceptance:**
- Scrolling a large map stays smooth; DOM node count is bounded by viewport.

### US-RES-7-03 — Incremental map-bundle load
**Change:** Load the map shell + visible region first; fetch remaining cells on demand
rather than the whole bundle up front.
**Acceptance:**
- Initial render does not block on the full cell set.

### US-RES-7-04 — Client cache & dedupe
**Change:** Cache loaded slices and dedupe in-flight requests so re-visiting a map or
page doesn't refetch everything.
**Acceptance:**
- Repeat navigation serves from cache; no duplicate concurrent fetches.

### US-RES-7-05 — Graceful loading & error states
**Change:** Add skeleton/loading and partial-failure UI for paged data and large maps.
**Acceptance:**
- Slow/failed page loads degrade gracefully without blanking the workspace.

---

## Executor Contract (read before coding)

**Touchpoints (only):** `static/src/xano.ts` — `loadJourneyMapBundle` (~line 911) and
`listJourneyStages` / `listJourneyLenses` / `listJourneyCells` (~lines 928-931); the
React matrix/list components that render the bundle (find the component that maps over
`cells` / `stages` / `lenses`). Read these in full before editing.

**Real anchor:** `loadJourneyMapBundle` first tries the business endpoint, then falls
back to raw CRUD via `Promise.all([listJourneyStages, listJourneyLenses, listJourneyCells])`
— that fallback fetches **all** rows. Wire it to the RES-4 paginated/scoped endpoints.

**Do NOT touch:**
- The Xano API **contracts** — this epic consumes RES-4's endpoints, it does not define
  them. If you need a new endpoint shape, that's a RES-4 story, not here.
- Cell status/lock display semantics (confirmed/draft/open, locked) — keep them intact.

**Sequencing:** blocked by RES-4. Ship in the **same release train** as RES-4 so the
response-shape change and its consumer land together.

**Verify with:** load a large seeded map → DOM node count bounded by viewport (not by
cell count); scrolling stays smooth; lists request one page at a time (network tab).

**Parity:** the rendered map looks and behaves identically for small maps; only large-map
performance and fetch behavior change.

## Definition of Done

- Matrix and lists are virtualized/paginated; cost tracks viewport.
- Frontend consumes RES-4 endpoints in the same release train.
- p95 render/interaction latency flat as map/list size grows 10×.
