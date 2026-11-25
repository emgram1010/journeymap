# US-REPEAT-1-06 — Several periods at once, and where a plan came from

**Epic:** REPEAT-1 · **Size:** S to M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** stories 02–05

## Description

"Next week, and the week after, and so on." Some planners plan a month ahead. This story lets a
repeat make more than one period in a single action, each a plan of its own, and shows on every
plan where it came from and what was made from it.

It stays a deliberate action by a person. A plan that repeats by itself is not built (D-14).

## User story

**As** a planner, **I want** to repeat a plan for several periods in one go and see the chain,
**so that** I can plan ahead and still know which plan was the pattern.

## Acceptance criteria

```gherkin
Scenario: several periods
  When I repeat a 7-day plan for 4 periods
  Then 4 new plans exist, one after another with no gap and no overlap
  And each is copied from the source plan, not from the copy before it

Scenario: names
  Then each plan gets its own free name that shows its start date

Scenario: the limit
  When I ask for more than 8 periods
  Then it is refused with the limit in the message

Scenario: one period already exists
  Given a repeat for the second period was made earlier
  Then that period is skipped and named, and the others are made

Scenario: one period fails
  Then the periods before it stay, the failed one leaves nothing, and I am told which

Scenario: where it came from
  Then a repeated plan shows "Repeated from <plan>" with a link

Scenario: what came from it
  Then a source plan lists the plans repeated from it, with their dates

Scenario: the source was deleted
  Then the repeated plan still opens, and shows "Repeated from a plan that no longer exists"
```

## Counter-measures

| Risk | Prevention |
|---|---|
| Copying from the previous copy multiplies an early mistake | Every period is copied from the one source |
| A long request times out with some plans made | Each period is its own all-or-nothing write; the result lists each period's outcome |
| A person's time off differs per period | Each period runs its own checks (and, after MATCH-1, its own availability check) |
| The start-of-period maths drifts | Period n starts at source start + n × the chosen gap, computed from the source each time, never by adding to the previous result |
| The chain link blocks deleting an old plan | The link is a plain number with a friendly fallback, never a declared blocker |
| Eight plans of copied work nobody reviews | The plan list shows each plan's "needs review" total |

## Governance

- **Errors (suggested):** `E-REPEAT-010` periods must be between 1 and 8.
- **Events:** one `plan.repeated` per plan made, sharing one correlation id.

## Tests (write first)

| ID | Test |
|---|---|
| T-REPEAT-06-1 | 4 periods: dates, no gap, no overlap, all from the source |
| T-REPEAT-06-2 | Limit of 8 |
| T-REPEAT-06-3 | Existing period skipped and named |
| T-REPEAT-06-4 | Forced failure on period 3: 1 and 2 stay, 3 leaves nothing, 4 reported as not attempted |
| T-REPEAT-06-5 | "Repeated from" and "repeated to" shown; deleted source handled |

## Keep a pulse on

- If planners use this every Friday without changing anything, a standing schedule (D-14) is worth revisiting, with a heartbeat and a "last period finished" check.
