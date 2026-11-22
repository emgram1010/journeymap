# US-DEMAND-1-02 — Plan vs actual separates unplanned work

**Epic:** DEMAND-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** US-DEMAND-1-01

## Description

Once work can arrive during the day, a day's total no longer means "what we planned". If
unplanned work is mixed into the same number, a busy reactive week looks like a badly
estimated plan, and the owner learns the wrong lesson. The report needs to show the two kinds
side by side, without changing how any single number is calculated.

## User story

**As** the owner, **I want** unplanned work shown apart from planned work, **so that** I can
see how much of the week was reactive.

## Acceptance criteria

```gherkin
Scenario: a day with both kinds
  Given member X's day has 300 planned minutes and one on-demand job of 40 minutes
  Then the report shows planned 300, unplanned 40, total 340, for expected and for actual

Scenario: per member and per day
  Then the same three numbers are shown per member and per day, and they add up to the plan totals

Scenario: a week with no unplanned work
  Then unplanned is 0 and every existing number is exactly what it was before this story

Scenario: older jobs
  Given jobs created before this story
  Then they all count as planned

Scenario: variance
  Then each job's variance is calculated exactly as today
  And unplanned work is not counted as a miss against the plan

Scenario: a share of the week
  Then the report shows unplanned as a percentage of total actual minutes
```

- "Unplanned" comes from one place: the origin side table from story 01. No second flag.
- **Assumed:** the report screen change. The frontend was not read.

## Counter-measures

| Risk | Prevention |
|---|---|
| The split changes a total | The total is still computed the old way; planned = total − unplanned. A test pins the old totals for a fixed fixture |
| A second copy of the variance formula appears | The split is a grouping of rows the existing function already returns; no new formula |
| A tally with a variable key comes back null | Seed `planned` and `unplanned` to 0 for every member and day before counting |
| A missing origin row is read as an error | No row means planned. Read the optional value through `??` into a `var` before branching |
| An untouched decimal reads as "has data" | Do not use a duration's nullness to decide anything; use the origin row |
| The percentage divides by zero | A week with 0 actual minutes shows "—", not an error |

## Governance

- **Events:** none for a read. A report that cannot be computed records a failure event and shows a friendly message, never a blank.
- **Friendly message:** "No unplanned work this week."

## Tests (write first)

| ID | Test |
|---|---|
| T-DEMAND-02-1 | Mixed day shows 300 / 40 / 340 |
| T-DEMAND-02-2 | Member and day rows add up to plan totals |
| T-DEMAND-02-3 | A fixture with no unplanned work gives the same numbers as before (golden file) |
| T-DEMAND-02-4 | Pre-existing jobs count as planned |
| T-DEMAND-02-5 | Zero actual minutes shows "—" |
| T-DEMAND-02-6 | TypeScript and backend give the same split for the same fixture |
