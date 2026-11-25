# US-MATCH-1-05 — Work nobody can take

**Epic:** MATCH-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** stories 01–04 · **Decision:** D-3 (founder)

## Description

The founder's decision: when nobody qualified is free, the work stays unassigned with the reason
shown. That is the right rule, and it creates a new job for the screen. Unassigned work that
nobody notices is a missed job.

This story gives that work one place: a list of everything in a plan that **cannot** be given to
anyone as things stand, with the reason and, most important, what would fix it. The founder is
the only support person; a list that says "blocked" and stops would send every case to them.

## User story

**As** a planner, **I want** one list of the work nobody can currently take, with what would fix
each item, **so that** I act on it days ahead, not on the morning.

## Acceptance criteria

```gherkin
Scenario: the list
  Given matching is on or show-only
  Then the plan shows "Needs a person": every unplaced or blocked item that no one on the plan fits on its day

Scenario: the reason
  Then each item shows why, grouped:
    - nobody on the plan holds <requirement>
    - people hold it, and none is working that day
    - the only person who holds it is away
    - the holding ended on <date>

Scenario: what would fix it
  Then each item offers the fixes that apply:
    - "Ben can take it on Wednesday" (another day, within the job's time window)
    - "Cara holds it and is not on this plan" (an admin adds her)
    - "Ana's holding ended 31 March" (an admin renews it)
    - "Ask the owner to waive it for this job" (if story 06 is built)

Scenario: backlog items with no day yet
  Then an item is listed only if no person fits on **any** day of the plan

Scenario: a time window
  Given the job has a time window
  Then days outside the window are not offered as a fix

Scenario: it clears itself
  When someone who fits becomes available
  Then the item leaves the list without anyone marking it

Scenario: the count is visible
  Then the plan header and the plan list show how many items need a person

Scenario: Health page
  Then the account's total is shown, by plan, with the oldest first

Scenario: the owner sees what is asked of them
  Then the owner sees the items waiting on a decision only they can make

Scenario: matching is off
  Then the list does not appear
```

## Counter-measures

| Risk | Prevention |
|---|---|
| The list is worked out differently from the rule | It is `match/check` run over the plan's people for each item; no second rule |
| It is slow on a big plan | The batch loader from story 01; the list is computed for the plan's window in one pass |
| A stored "needs a person" flag goes stale | Nothing is stored. The list is worked out when read, so it cannot disagree with the facts |
| A fix is offered that would itself be refused | Every offered fix is checked with the same rule before it is shown |
| It names people on other plans with private detail | Name and "not on this plan" only |
| The count on the plan list makes the list slow | A count-only variant with a cap ("20+") |
| Planners learn to ignore a list that is always full | Empty by default: an item is listed only when **no one** fits, not when the planner's first choice does not |
| The owner is never told | The owner's home shows items waiting on them; one in-app notice per new item, never an email (Epic-27 D-8) |

## Governance

- **Errors:** none new (a read).
- **Events:** `matching.needs_person` when an item first appears and `…resolved` when it leaves, with the reason and how long it waited. These two events are what make the Health page line possible without storing a flag.
- **Health page:** items needing a person, by plan, oldest first.

## Tests (write first)

| ID | Test |
|---|---|
| T-MATCH-05-1 | Each reason group, from golden cases |
| T-MATCH-05-2 | Each fix offered only when it would pass the rule |
| T-MATCH-05-3 | Time window limits the days offered |
| T-MATCH-05-4 | Backlog item listed only when no day works |
| T-MATCH-05-5 | Item leaves the list when a holding is recorded |
| T-MATCH-05-6 | Counts on the plan header and plan list |
| T-MATCH-05-7 | Appeared and resolved events, once each |
| T-MATCH-05-8 | Off: no list |

## Keep a pulse on

- How long items wait. If the usual wait is days, the business is short of a holding, which is a hiring or training signal worth showing the owner.
