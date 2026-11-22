# DEMAND-1 — On-demand jobs and the order webhook

**Epic ID:** DEMAND-1 (E4 in the founder's list)
**Status:** 🟡 Order intake built and verified live 2026-11-21. Placing work on a live day, the webhook and polling are NOT built. See Test Results.
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

**Partly built and verified live 2026-11-21 (Fable 5.2). The order intake works; placing work on a live day does not exist yet.**

**The one decision I did not take (critical)**
An order usually arrives on a day that has already started. Publishing refuses to re-publish a started day on purpose (E-LIVE-007), because the activity log points at the frozen day. Putting on-demand work onto that day means overriding that rule in the most protected write path. I did not do that unattended.
**So today an order becomes a job in the plan's backlog**, with its items and a correct estimate, flagged unplanned, exactly once. A person drags it onto a day.
**Recommended next step:** an append-only republish (old items must be unchanged, new ones added at the end), built on Opus with a review.

**Other decisions taken**
1. **No webhook was registered and nothing was built in the order system's workspace (Xano 5).** That is an outward action on a real booking system and needs its credentials. Emgram's side is ready: one address that accepts an order.
2. **The sender proves itself with an order key** (shown once, only its hash stored), not a vendor signature. The small workspace that listens to the order system checks the vendor's signature and then calls Emgram with the key.
3. **The routing rule (D-5)** is: order system + fulfilment type (or any) → one plan and one map.
4. **A cancelled order flags the job; it does not cancel it**, started or not. A person decides.
5. **Only structured fields are accepted.** There is no field a customer note could arrive in.
6. **"Pause all AI" also holds incoming orders.** They are kept and can be tried again.

**What was built**
- Tables `work_item_origin` (175), `order_route` (176), `order_inbox` (177).
- Functions `orders/process` (441), `ingest` (442), `admin` (443), `overview` (444).
- Endpoints `POST order-inbound` (679, key instead of sign-in), `GET order-setup` (680), `POST order-setup-change` (681).
- App: an "Incoming orders" tab in Catalog (routing rules, order key shown once, orders that need a person, jobs to check).

| Test | Result |
|---|---|
| The same order 10 times at once | Pass: 1 created, 9 duplicates, one job (255) |
| The same order again | Pass: duplicate, no second job |
| Wrong key, no key | Pass: refused (E-HOOK-001) |
| No routing rule | Pass: nothing added, listed for the owner, can be tried again |
| A route to a map the plan does not use | Pass: refused (E-HOOK-005) |
| Order changed before work started | Pass: the job's items were replaced |
| Order cancelled | Pass: job flagged; the flag can be cleared, logged with who |
| Order changed after work started | **Not run** (no started job on the test plan) |
| Held while paused, then tried again | Pass |
| Unlinked products | Pass: kept by name on the job and listed under Outside products |
| A customer note in the request | Pass: not accepted, not stored |
| Another account, a member, an AI login | Pass: refused |

**Not built**
- Story 01: `plan_add_on_demand_job`, the on/off switch per plan, time zone handling, over-capacity message.
- Story 02: the planned / unplanned split in reports.
- Story 03: the receiver in the order system's workspace, the webhook, retries with growing gaps, the Health page panel, the 30-day clean-up of the inbox.
- Story 04: backup polling.
- The flag does not show on the job in Planning or Execution yet (it is on the Incoming orders tab).
- No Opus review pass was run.

**Left on the test account (13):** jobs 254, 255, 256 on plan 115 and their inbox rows.

