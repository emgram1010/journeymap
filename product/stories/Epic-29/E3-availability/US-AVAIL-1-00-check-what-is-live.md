# US-AVAIL-1-00 — Check what is live before building

**Epic:** AVAIL-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** nothing. **Read-only.**

## Description

Two claims in the epic decide its design, and both came from searching the repo, not from live.

1. **Nothing reads daily hours when scheduling.** If something live does refuse an over-full day,
   then "not enough hours" is already a refusal somewhere and decision D-9 (warn, do not refuse)
   would contradict it.
2. **How the board adds up a day.** "Hours left" must use the same sum the planner already sees,
   or the board and the availability answer will disagree by a few minutes and nobody will trust
   either.

## User story

**As** the builder, **I want** to know how a day's hours are counted today,
**so that** availability gives the same answer the planner already sees.

## Acceptance criteria

```gherkin
Scenario: live matches the repo
  When tables 116, 117, 118, 129, 133, 172 and 174 are fetched live
  Then every difference is listed and the founder is told before anything is built

Scenario: does anything enforce daily hours
  When every endpoint and function that places work is read live
  Then the story records whether any of them refuses or warns on a full day

Scenario: how a day is totalled
  Then the story records the function and the frontend code that add up a day's minutes
  And whether gaps from manual start times count

Scenario: over-full days today
  When every draft and published day on the test account is totalled
  Then the story records how many are already over their person's daily hours
```

## Counter-measures

| Risk | Prevention |
|---|---|
| D-9 is decided on a wrong assumption | The "over-full days today" count goes to the founder with D-9 |
| Two different sums for a day | Story 03 reuses the existing sum, wherever this story finds it |

## Governance

- No errors, no events: nothing is written. Answers go into `epic.md` section 2.

## Tests (write first)

| ID | Test |
|---|---|
| T-AVAIL-00-1 | Live vs repo comparison recorded |
| T-AVAIL-00-2 | "Enforces daily hours" answered for every placing endpoint in README F-8 |
| T-AVAIL-00-3 | Over-full day count recorded |

## Keep a pulse on

- If many days are already over-full, daily hours are being used as a rough guide, and a warning is the right strength.
