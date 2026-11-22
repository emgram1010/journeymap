# DEMAND-1 — On-demand jobs and the order webhook

**Epic ID:** DEMAND-1 (E4 in the founder's list)
**Status:** 📋 Written, not built (2026-11-21).
**Size:** L
**Model:** **Opus 5.5** for story 01 (it writes to a live day and must not double); Sonnet 5.5
for stories 02–04; Opus review pass at the gate.
**Depends on:** AIM-1 (so AI-run jobs log under the agent), LIVE-1 / REPUB-1 (live days),
JOB-1 (jobs pinned to a version), WIN-1 (plan window).
**Read first:** `../README.md` (findings F-6 to F-9, F-11; decisions D-5, D-6, D-7).

---

## 1. Goal

**Pain:** live days are locked and there are no triggers, so a new booking cannot become work
until someone plans and publishes a day.

**Win:** a new order appears in Execution within seconds as unplanned work, still timed, and
nothing already planned is moved.

**Two workspaces, kept separate.** The order source's workspace (Booqable, Xano id 5) receives
the event and calls Emgram (Xano id 1). Emgram never calls the order system directly.

Booqable is the first order source, **not the design**. Names in Emgram are generic:
`source_system`, `source_ref`, `external_id`.

## 2. What exists today (repo files, 2026-11-21; live not compared)

| Fact | Where |
|---|---|
| A job is created by one function, used by the planner endpoint and by `plan_add_job` | `planner_ops/create_work_item` |
| `work_item` has `attributes` (JSON, records where each value came from) and text validators on `title` | `static/tables/122_work_item.xs` |
| So a new column on `work_item` risks dropping its validators; use a side table | CLAUDE.md |
| No "unplanned", "on demand" or `source_ref` anywhere in the backend | search, 2026-11-21 |
| A plan publishes a day to live, and can republish | LIVE-1, REPUB-1 (`apis/planner/562_…publish_POST.xs`) |
| Plan-vs-actual reports exist | `EPIC-RPT-1-reports-plan-vs-action.md` |
| A transaction does **not** stop two overlapping requests; only a unique index does | CLAUDE.md (EXC-1, endpoint 610) |
| `redis.*` is not available on this plan; rate limits are counts on `event_log` | CLAUDE.md (APP-1) |
| A scheduled task once failed silently for 8 hours | CLAUDE.md (OBS-1 heartbeat) |

## 3. Rule

**On-demand work is added, never squeezed in.** It lands at the end of a live day that already
exists, flagged unplanned. It never moves, resizes or removes planned work, never creates a
day, and never publishes one. The same order can arrive any number of times and still makes one job.

## 4. Do not break

- Planned work on a live day: same order, same times, same statuses, before and after.
- A day is still made live only by a person (or an approved action), never by a webhook.
- The order system's access stays **read-only**.
- Plan-vs-actual math is unchanged; reports gain a split, they do not change a total.

## 5. Non-goals

- Auto-planning or auto-assigning by load.
- Writing anything back to the order system.
- Customer names, addresses, phone numbers or prices in Emgram. Only what the work needs:
  order number, dates, fulfilment type, items and quantities.

## 6. Stories

| File | Story |
|---|---|
| `US-DEMAND-1-01-add-an-on-demand-job.md` | The tool and endpoint that add a job to a live day |
| `US-DEMAND-1-02-plan-vs-actual-shows-unplanned.md` | Reports split planned and unplanned |
| `US-DEMAND-1-03-order-webhook.md` | The receiver, the routing rule, the forward and the retry |
| `US-DEMAND-1-04-backup-polling.md` | The scheduled check for missed orders |

## 7. Completion gate

- The same order sent 10 times at once makes exactly one job (parallel test).
- A live day's planned blocks are byte-for-byte the same before and after an on-demand add.
- A test order in the order system appears in Execution in under 60 seconds.
- The polling task is switched off for an hour, then on: every missed order arrives once.
- The per-plan switch off: nothing is added, nothing is lost, and the Health page says why.
- Existing suites green. Opus review pass done. Test Results filled in.

## 8. Test Results

_Not run. Nothing built yet._
