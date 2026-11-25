# US-AVAIL-1-02 — Time off

**Epic:** AVAIL-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** story 00 · **Decision:** D-13 (whole days only)

## Description

A working pattern covers the usual week. Time off covers the exceptions: a holiday, a sick day, a
training day. It is a first day, a last day and an optional note, on the lasting profile so it
applies in every plan that touches those dates.

## User story

**As** an admin, **I want** to record when someone is away,
**so that** no work is planned for them on those days.

## Acceptance criteria

```gherkin
Scenario: record time off
  When I record Ana as away from the 3rd to the 5th
  Then she is not available on the 3rd, 4th or 5th
  And she is available on the 2nd and the 6th

Scenario: one day
  When the first and last day are the same
  Then that one day is time off

Scenario: last day before first day
  Then it is refused with a message that says why

Scenario: overlapping time off
  When I record time off that overlaps one already recorded
  Then I am told, and offered to join them into one

Scenario: change or remove
  Then availability follows the new dates at once

Scenario: time off in the past
  Then it can be recorded (for the record) and changes no work

Scenario: very long time off
  When it is longer than 366 days
  Then I am asked to confirm, and reminded that switching a person off exists

Scenario: a note
  Then up to 200 characters, no HTML; shown to admins only

Scenario: see who is away
  When I open a plan
  Then I can see who is away on which days of that plan

Scenario: who may edit
  Then admins and the owner; an AI may not

Scenario: another account
  Then it cannot see or change my people's time off
```

## Counter-measures

| Risk | Prevention |
|---|---|
| A date compared in the wrong time zone moves time off by a day | Plain dates only, compared to plain plan dates. No clock time anywhere |
| An optional date left out of a GET filter does not exist and crashes | Declare date filters as text, default `""`, widen to a far-past or far-future date when absent |
| A `where` clause calls a filter and fails silently | Compute every bound into a variable first |
| The note leaks a medical reason to the whole team | Notes are returned to admins only; the planner sees "away", never the note |
| Overlapping rows count a day twice | The answer is "is any row covering this date", a yes or no, so overlap cannot double-count |
| Time off recorded over work already assigned | Story 05 |
| Removing time off leaves stale "needs review" marks | Story 05 clears marks it raised when the cause is gone |

## Governance

- **Errors (suggested):** `E-AVAIL-010` last day is before first day · `E-AVAIL-011` dates are not dates · `E-AVAIL-012` note too long or contains HTML · `E-AVAIL-013` time off not found.
- **Events:** `time_off.recorded`, `.changed`, `.removed` (profile, dates, actor; never the note).
- **Delete behaviour:** removed by an admin, or with the profile.

## Tests (write first)

| ID | Test |
|---|---|
| T-AVAIL-02-1 | Both edge days count; the days either side do not |
| T-AVAIL-02-2 | One-day time off |
| T-AVAIL-02-3 | Reversed dates refused |
| T-AVAIL-02-4 | Overlap offered as a join |
| T-AVAIL-02-5 | Note hidden from non-admins; not in any event |
| T-AVAIL-02-6 | List for a plan's window, with and without filters |
| T-AVAIL-02-7 | AI caller refused; second account refused |

## Keep a pulse on

- Part-day time off (D-13). If it comes up often, it needs clock times and a time zone, which is a bigger change than it looks.
