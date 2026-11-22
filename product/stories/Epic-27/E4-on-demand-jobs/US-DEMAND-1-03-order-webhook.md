# US-DEMAND-1-03 — Order webhook

**Epic:** DEMAND-1 · **Size:** L · **Model:** Sonnet 5.5, Opus review · **Status:** 📋 Not built
**Depends on:** US-DEMAND-1-01, AIM-1 story 03
**Decisions (2026-11-21):** D-5 ✅ routing table the owner fills once; unmatched orders listed on
the Health page, nothing added. D-6 ✅ started work is never changed; "order changed" and "order
cancelled" show in **both Planning and Execution**, built as a flag beside the status (the five
step statuses are fixed by design).
**Outward action:** registering the webhook in the order system needs the owner's yes.

## Description

Today a booking only becomes work when someone types it in. The order system can send an event
when an order is created or changed. A small receiver in the order system's own workspace
(Xano id 5) checks the event, fetches the order, and forwards the few facts the work needs to
Emgram (Xano id 1).

**The request as written has a gap (finding F-6).** An order has a number, dates and items. It
does not say which plan, which map, which member or which day it becomes. That rule has to
exist somewhere the owner can see and change. This story adds it as a small routing table.

## User story

**As** the owner, **I want** every new or changed order sent to Emgram, **so that** booking
work appears without anyone typing it.

## Acceptance criteria

```gherkin
Scenario: a new order
  Given the webhook is registered and a routing rule matches the order
  When an order is created
  Then within 60 seconds an on-demand job exists on the right member's live day
  And it carries the order number, dates, fulfilment type, and items with quantities

Scenario: the sender is checked
  When an event arrives with a missing or wrong signature
  Then it is refused, logged, and nothing is forwarded

Scenario: the same event twice
  Then it is processed once

Scenario: events out of order
  Given "updated" arrives before "created"
  Then the receiver fetches the order as it is now and acts on that, so the order of events does not matter

Scenario: an order is changed before work started
  Then the existing job's items and quantities are updated, and no second job is made

Scenario: an order is changed or cancelled after work started (D-6)
  Then started work is not changed
  And the job carries the flag "order changed" or "order cancelled"
  And the flag shows on the job in Planning and in Execution, next to its normal status
  And the step statuses stay one of the five fixed values

Scenario: the owner deals with a flagged job
  When the owner opens a flagged job
  Then they can see what changed in the order (items and quantities, before and after)
  And they can clear the flag once handled, which is logged with who and when

Scenario: an order is cancelled before work started
  Then the job is cancelled, not deleted

Scenario: no routing rule matches
  Then nothing is added, and the order is listed under "Orders with no route" on the Health page

Scenario: no live day for that member and date
  Then the order waits in the queue and is tried again; it is listed as "waiting for a live day"

Scenario: Emgram is down
  Then the forward is retried with growing gaps (1, 5, 15, 60 minutes), up to 8 tries
  And after the last try it is marked failed and shown on the Health page

Scenario: every event is logged
  Then each event has a row: received, checked, fetched, forwarded or failed, with times
```

**The routing table (lives in the order system's workspace; generic by design):**

| Field | Meaning |
|---|---|
| match | fulfilment type (and optionally a product group) |
| plan, map, member | where the work goes in Emgram |
| date rule | which order date becomes the work date (for example start date, or the day before) |
| on / off | one rule can be switched off without deleting it |

## Counter-measures

| Risk | Prevention |
|---|---|
| The signature method is guessed | Read the order system's webhook documentation first and record the exact scheme in this file. If it has none, use a long secret in the URL path plus an allow-list, and say so plainly |
| A replayed old event is accepted | Unique index on the event id; reject events older than the allowed window |
| Two deliveries overlap | The unique index decides; Emgram's own `source_ref` index is the second net |
| The receiver times out and the sender retries forever | Answer 200 as soon as the event is stored; fetch and forward from a queue table worked by a scheduled task |
| Retries need redis (not available) | A queue table with next-try time and try count |
| Customer personal data ends up in logs or in Emgram | Forward and log only: order number, ids, dates, fulfilment type, item ids and quantities. No names, emails, phones, addresses or prices |
| The secret or the Emgram token is in code | Environment variables in the order workspace; never in a file or a log; rotation steps written in the epic |
| The receiver's access to the order system could write | Use a read-only key; a test proves a write is refused |
| The forward runs as the owner | It uses an AI member's scoped token from AIM-1 story 03, so the job is logged under the agent |
| A flood of events hits Emgram | Rate-limit the receiver (count on its own log, not redis) and respect DEMAND-1 story 01's daily limit |
| An order that never finds a live day waits forever | After 24 hours it is marked "needs the owner" and shown on the Health page |
| A static path next to a dynamic one is never reached | Give the receiver its own path prefix (for example `/hooks/order`), not a sub-path of an id route |
| Wrong API group base URL | Confirm the group and its canonical address before wiring anything |
| The registration happens without consent | Ask the founder, state the exact URL and events, wait for a yes |
| "Order changed / cancelled" is added as a sixth status and breaks the status engine | It is a flag on the job's origin side-table row (DEMAND-1 story 01), not a status. `log/next_status` is not touched |
| The flag shows in Execution but not in Planning (or the reverse) | Both screens read it from the same side-table GET; a UI test checks both. **Assumed:** screen changes, frontend not read |

## Governance

- **Errors (suggested):** `E-HOOK-001` bad signature · `E-HOOK-002` event too old ·
  `E-HOOK-003` no route · `E-HOOK-004` order fetch failed · `E-HOOK-005` forward failed.
- **Events:** `order_event.received`, `.rejected`, `.forwarded`, `.retry_scheduled`, `.failed`,
  `.no_route`, `.waiting_for_live_day`. Emgram writes its own events from story 01.
- **Health page:** a panel with counts for the last 24 hours and the three lists (no route,
  waiting, failed).
- **Delete behaviour:** queue rows are kept 30 days, then removed by a task that logs its count.

## Tests (write first)

| ID | Test |
|---|---|
| T-DEMAND-03-1 | Valid event creates one job with the right items |
| T-DEMAND-03-2 | Bad signature refused and logged |
| T-DEMAND-03-3 | Duplicate event processed once |
| T-DEMAND-03-4 | Out-of-order events end in the right state |
| T-DEMAND-03-5 | Change before start updates; change after start flags only |
| T-DEMAND-03-6 | Cancel before start cancels; cancel after start flags only |
| T-DEMAND-03-7 | No route listed; nothing added |
| T-DEMAND-03-8 | Emgram down: retries at the right gaps, then failed |
| T-DEMAND-03-9 | No log row or forwarded body contains a customer name, email or phone |
| T-DEMAND-03-10 | A write with the read-only key is refused |
| T-DEMAND-03-11 | Flag shows in Planning and in Execution; step status unchanged |
| T-DEMAND-03-12 | Owner clears the flag; the clear is logged |
