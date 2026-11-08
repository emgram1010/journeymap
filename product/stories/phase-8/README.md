# Phase 8 — Republish to Live

One initiative: a planner can publish a timeline **again** — until the moment an
agent starts working it. After that, the day is sealed.

## Why

- LIVE-1 allowed exactly one publication per timeline (unique index, E-LIVE-005 — now retired).
- Real days change between publish and start-of-work: a callout, a truck down, a rush job.
- Route-planning systems solve this with **re-dispatch**: a new frozen manifest replaces the old one, allowed only while the driver hasn't left. This phase is that, for timelines.

## The rule (decision from the founder, 2026-11-01)

> Republishing is **blocked once the agent initiates execution** on the published day.
> "Initiates execution" = any `activity_log` event recorded against the timeline's
> current publication (a `started`, but also a `blocked` or `skipped` — any engagement counts).

Before that moment, republish is allowed any number of times. Each republish writes a
**new** `plan_publication` row (a new frozen snapshot, new hash, version n+1). Nothing
is ever updated or deleted — the old manifests stay as history.

## MVP build order

| # | Epic | Depends on | MVP scope | Model |
|---|---|---|---|---|
| 1 | [REPUB-1 Republish to live](EPIC-REPUB-1-republish-to-live.md) | LIVE-1, APP-1, LOG-1 (all built) | US-01 through US-05 | Sonnet 5.5; **Opus 5.5** (or Fable) for US-03 (the guard + transaction) and a review pass after the epic |

## Story sequencing (what can run in parallel)

```
US-01 (readers pick latest)  ──┐
                               ├──►  US-03 (republish endpoint + guard) ──► US-05 (UI)
US-02 (table: version column) ─┘                                      └──► US-04 (tests may start once 03's contract is fixed)
```

- **US-01 and US-02 are independent** — safe in parallel (different files, no shared state).
- **US-03 must wait for both**: it inserts version-2 rows that only latest-aware readers handle safely.
- **US-05 (UI) waits for US-03** — it calls the changed endpoint.
- Never parallelize two stories that touch the same `.xs` file or the same table.

## Test data

- Clone of map 178 (`leads-to-sales-baseline`) lineage only — never the original (standing rule).
- A realistic epoch base for any stand-in timestamp (`1_800_000_000_000` + minute offsets), never `0` (CLAUDE.md, loose-null rule).

## Known traps to carry in (from CLAUDE.md, don't re-learn)

- `updateTableSchema` drops `filters=trim` validators — `plan_publication.snapshot_hash` has one. See US-02's countermeasures.
- `db.transaction` does **not** serialize overlapping requests; only a unique index refuses a race. The version unique index in US-02 *is* the race guard.
- `($pubs|first)` with no ordering is undefined once two rows exist per timeline — the whole reason US-01 ships first.
