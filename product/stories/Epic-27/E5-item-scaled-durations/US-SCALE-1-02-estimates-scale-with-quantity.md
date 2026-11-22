# US-SCALE-1-02 — Estimates scale with quantity

**Epic:** SCALE-1 · **Size:** S to M (set by story 00) · **Model:** Sonnet 5.5, then **Opus review**
**Status:** 📋 Not built · **Depends on:** US-SCALE-1-00, US-SCALE-1-01

## Description

The owner's expectation is simple: time per item times how many. Fourteen chairs take more
than two and less than fifty. An estimate function for this already exists (EST-1). Story 00
says whether it is live and correct. **This story closes whatever gap story 00 found, inside
that one function.** It does not add a second calculation.

If story 00 finds the function already does all of this and the only problem was missing
lines, this story shrinks to its tests: prove the founder's example, record it, done.

## User story

**As** the owner, **I want** each stage's planned time to be minutes per item times quantity,
**so that** 14 chairs plan more than 2 and less than 50.

## Acceptance criteria

```gherkin
Scenario: the founder's example
  Given a job with 2 six-foot tables and 14 adult chairs
  And the pinned version has minutes per unit for both, per stage
  Then each stage's planned minutes equal the sum of (minutes per unit × quantity) plus any stage baseline EST-1 defines
  And the result matches the hand calculation to the minute

Scenario: it scales
  Then the same job with 2 chairs plans less, and with 50 chairs plans more

Scenario: an item with no time set
  Given one item on the job has no rate in the pinned version
  Then it adds 0 minutes
  And the job shows "no time set" naming that item
  And the card never falls back to a default 30 for a job that has items

Scenario: a job with no items
  Then its cards are exactly what they are today

Scenario: the owner's manual length
  Given the owner set a block's length by hand
  Then that length is kept, and the estimate is shown beside it as "expected"

Scenario: existing jobs
  Then no job created before this story changes its planned minutes

Scenario: the map is republished with new times
  Then jobs already pinned to the older version keep the older times

Scenario: backend and frontend agree
  Then the backend function and its TypeScript twin give the same minutes for every golden fixture
```

- Minutes are whole numbers. The rounding rule (when minutes per unit has decimals) is stated
  once and used by both sides: suggested round up per stage, after summing.
- Scaling applies only when lines exist on the job.

## Counter-measures

| Risk | Prevention |
|---|---|
| A second formula appears in a tool, a report or the frontend | Search for any other multiply of quantity and rate; EST-1's rule is "one place". A test pins the function and its twin to the same fixtures |
| Old jobs are recalculated and live days shift | No backfill, no recalculation job. The estimate is read through the pinned version, which never changes |
| A stored `0` rate is read as "no time set", or the reverse | Use the rate row's existence, not the number being non-zero. A real zero is a valid rate |
| A tally with a variable key becomes null and the whole estimate is null | Seed every stage key to 0 before summing |
| A branch inside the loop reads a variable updated in the same pass | Branch on the loop item only; fold tests into arithmetic with bool `\|to_int` where needed |
| Rounding differs between backend and frontend | One written rule, golden fixtures on both sides, including a decimal rate |
| The estimate quietly changes what variance compares against | That is intended (EST-1 says so); the Opus review confirms variance reads the new expected, and a fixture shows the before and after |
| An over-large quantity makes an absurd day | Quantity is capped at 9999 by EST-1; a job over the day's capacity is flagged, not refused |

## Governance

- **Errors:** none new; "no time set" is a flag, not an error.
- **Events:** EST-1's `warn` event for an incomplete estimate is reused; it names the items with no time.
- **Health page:** EST-1's Estimates panel counts jobs with "no time set".

## Tests (write first)

| ID | Test |
|---|---|
| T-SCALE-02-1 | Founder's example equals the hand calculation |
| T-SCALE-02-2 | 2 < 14 < 50 chairs, strictly |
| T-SCALE-02-3 | Missing rate adds 0 and flags; never 30 |
| T-SCALE-02-4 | No items: golden file unchanged |
| T-SCALE-02-5 | Manual length wins; expected shown beside it |
| T-SCALE-02-6 | Jobs made before the change are unchanged (snapshot of plan 147) |
| T-SCALE-02-7 | Republish does not change pinned jobs |
| T-SCALE-02-8 | Backend and TypeScript match on all fixtures, including a decimal rate |
