# Phase 9 — Planner load-time fixes

One initiative: fix the specific, measured causes of the planner feeling slow, found in
`product/performance/planner-load-time-audit.md` (2026-11-02, real browser timing, not a guess).

## Why

The founder's own words: loading takes 3–6 seconds, and some section of creating a new
job is slow too. The audit found four concrete, separate causes — this phase fixes them
one at a time, cheapest/clearest first.

## Root cause, already diagnosed (no further investigation needed for US-01/02/03)

Opening a job's detail renders **three sibling components that each independently fetch
the same job's data**, with no sharing between them:

- `JobLinesEditor.tsx` calls `getWorkItemLines(workItemId)`
- `ExceptionSendPanel.tsx` calls `Promise.all([getWorkItemLinks(workItemId), getWorkItemLines(workItemId)])` — its own, separate call to the same `lines` endpoint

In production this is already 2× the necessary `lines` calls (one from each component)
plus the one necessary `links` call. In dev mode, React StrictMode's double-invoke
doubles ALL of it again — which is exactly the **4× `lines`, 2× `links`** the audit
measured. StrictMode is doing its job correctly; the real bug is the two components not
sharing data.

## MVP build order

| # | Epic | Depends on | MVP scope | Model |
|---|---|---|---|---|
| 1 | [PERF-1 Planner load-time fixes](EPIC-PERF-1-planner-load-time.md) | None — a focused fix to existing, shipped code | US-01 through US-05 | Sonnet for US-01/02/03/05; **Opus/Fable for US-04** (the 14.3s main-thread block — root cause not yet diagnosed, needs a real profile, and CLAUDE.md's "any bug that fails twice → Opus" rule applies on the first sign it isn't quick) |

## Story sequencing (what can run in parallel)

```
US-01 (share one fetch) ──► US-02 (cancel stale requests) ──► US-03 (fix loading-state message)   ──► US-05 (re-measure)
        [all three touch JobsModal.tsx / JobLinesEditor.tsx / ExceptionSendPanel.tsx — sequential, same files]

US-04 (profile + fix the 14.3s gap) ─────────────────────────────────────────────────────────────────┘
        [different code path (route/navigation-level), independent files — safe to run IN PARALLEL with 01-03]
```

- **US-04 is the one safe parallel track** — it touches the Planner-tab route/navigation
  code, not the job-detail modal. Everything else shares files and must be sequential.
- **US-05 waits for US-01–03** — it re-measures the fetch count after the fix, so it needs
  the fix in place to mean anything.
- **US-06 (added 2026-11-02, found during US-04)** — the backlog endpoint (559): same
  "estimate every job" waste as the board had, plus an unfiltered whole-table link
  query. Backend-only, independent of every other story.

**Status 2026-11-02:** US-01–04 done. US-04's "14.3s freeze" was a measurement error
(retracted in the audit); the real cause is a backend that handles one account's
requests roughly one at a time, so load time ≈ total server work. **US-05 and US-06 moved
to `product/stories/phase-10/` as US-LOAD-1-06 and US-LOAD-1-02 — nothing open here.**

## Test environment

- `localhost:3000` (the `protype-2` dev server), the same instance the audit used.
- Measure with `performance.getEntriesByType('resource')`, not a stopwatch — the audit file
  shows the exact pattern to reuse.
- Real plan/job data is fine here (read-only measurement); no destructive action, no schema
  change, no table touched in this whole phase.

## Governance

N/A by scope — no new table, no new validation rule, no new error code. This is a
frontend performance fix to existing, already-shipped components. The one observability
tie-in worth a note for later (not required for this phase's MVP): the Health page could
eventually surface "duplicate fetch" patterns automatically, but that is a new feature,
not part of fixing the three specific duplicates already found.
