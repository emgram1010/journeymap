# US-DEMAND-1-04 — Backup polling for missed orders

**Epic:** DEMAND-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** US-DEMAND-1-03
**Owner decision (2026-11-21):** every 15 minutes, 7:00 am to 11:00 pm Central, with a 7:00 am catch-up.

## Description

Webhooks get lost: a network blip, a restart, a registration that expires. If the webhook is
the only path, a missed booking goes unnoticed until a customer calls. A scheduled check asks
the order system "what changed since I last looked?" and sends anything new down the same
path as the webhook. Because that path is safe to repeat, the two never double up.

## User story

**As** the owner, **I want** a scheduled check for orders the webhook missed, **so that** no
booking goes unnoticed for long.

## Acceptance criteria

```gherkin
Scenario: a normal run
  Given it is between 7:00 am and 11:00 pm Central
  When the task runs
  Then it asks for orders updated since the last successful run, minus 5 minutes of overlap
  And only the fields it needs
  And each order goes down the same path as a webhook event

Scenario: nothing is doubled
  Given the webhook already forwarded an order
  Then the poll's copy returns the existing job and makes no new one

Scenario: the first run of the day
  Given the last successful run was at 11:00 pm
  When the 7:00 am run starts
  Then it covers everything since 11:00 pm (the catch-up is this run, not a separate task)

Scenario: outside hours
  Then the task does nothing and records that it was outside hours

Scenario: the rate limit is low
  Given the last response said fewer than 20% of requests remain (Assumed threshold)
  Then this run is skipped and the skip is logged with the number left

Scenario: a run fails
  Then the "last successful run" time is not moved
  And the next run covers the gap

Scenario: more than one page of results
  Then the task follows the pages, checking the rate limit before each one, and stops safely if it runs low

Scenario: two runs overlap
  Then the second one sees the first is still running and exits

Scenario: the task goes quiet
  Given no successful run for 45 minutes during working hours
  Then the Health page shows a warning

Scenario: clocks change
  Then the 7:00 am to 11:00 pm window is still correct on the days daylight saving starts and ends
```

- 7:00 am to 11:00 pm at 15-minute steps is **65** runs when both ends run (the request said
  about 64). Tests assert the window, not a count.
- The last-success time is stored in a small state table, updated only after a full, clean run.

## Counter-measures

| Risk | Prevention |
|---|---|
| The task fails silently for hours (it has happened here before) | It writes a heartbeat event **every** run: ran, skipped (why), or failed. A test compares the row count against the expected runs |
| The schedule is set in UTC and drifts with daylight saving | Run every 15 minutes all day; the task itself checks the local hour in `America/Chicago` and exits outside the window |
| A filter call inside the `where` clause fails at runtime | Compute the cutoff time into a `var` first; use the plain variable in the query |
| An order updated in the same second as the last run is missed | 5 minutes of overlap; the repeat is harmless |
| A partial run moves the last-success time | Update it only at the very end, after every page is handled |
| Two runs overlap | A "running" row with a unique index; the second insert fails and that run exits. A stale lock older than 30 minutes is released with a warning event |
| The poll uses up the rate limit that people need | Read the headers on every response; skip under the threshold; never retry inside one run |
| The poll and the webhook use two code paths that drift | The poll puts rows in the **same queue** the webhook uses |
| The poll writes to the order system | Read-only key, same as story 03 |
| Personal data in the poll's logs | Same field list as story 03: no names, emails, phones, addresses, prices |
| A long outage creates a huge first request | Cap the look-back at 7 days; if the gap is longer, stop and raise a warning for the owner |

## Governance

- **Errors (suggested):** `E-POLL-001` order system unreachable · `E-POLL-002` rate limit low,
  run skipped · `E-POLL-003` gap longer than 7 days.
- **Events:** `order_poll.ran` (orders seen, orders queued), `.skipped_outside_hours`,
  `.skipped_rate_limit`, `.failed`, `.stale_lock_released`.
- **Health page:** last successful run, next run, runs today, skips today.
- **Switch:** one on/off flag for the task, changeable without a push.

## Tests (write first)

| ID | Test |
|---|---|
| T-DEMAND-04-1 | Normal run queues only orders changed since last success minus 5 minutes |
| T-DEMAND-04-2 | An order already forwarded is not doubled |
| T-DEMAND-04-3 | 7:00 am run covers the overnight gap |
| T-DEMAND-04-4 | Outside hours does nothing but writes a heartbeat |
| T-DEMAND-04-5 | Low rate limit skips and logs |
| T-DEMAND-04-6 | A failed run leaves last-success unchanged; the next run catches up |
| T-DEMAND-04-7 | Overlapping runs: one works, one exits |
| T-DEMAND-04-8 | Daylight-saving days: window correct (fixed test dates) |
| T-DEMAND-04-9 | After one real hour live, heartbeat rows match the expected number of runs |
