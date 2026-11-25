# US-REPEAT-1-02 — The new plan, its people and its days

**Epic:** REPEAT-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** stories 00, 01

## Description

The first part of a repeat is the frame: a new plan with the same length, the same accepted
maps, the same people and the same days, moved forward. A plan template already does part of
this, from the template. A repeat does it from the **plan as it is now**, because a plan drifts
from its template the moment a planner adds a person or changes a start time.

## User story

**As** a planner, **I want** the new plan to start with the same people and days as the last one,
**so that** I do not rebuild the frame every period.

## Acceptance criteria

```gherkin
Scenario: the plan
  When I confirm a repeat with a start date and a name
  Then a new plan exists with the same number of days, starting on that date
  And it accepts the same maps as the source plan does today
  And it records which plan it came from

Scenario: the people
  Then every active, visible person on the source plan is on the new plan
  With the same name, kind, colour, daily hours, login and (for an AI) model

Scenario: a person who cannot come along
  Given a person is inactive, their profile is off the roster, or their login is switched off
  Then they are not added, and the result names them with the reason

Scenario: the days
  Given the source plan has a day for Ana on Monday starting 07:30
  Then the new plan has a day for Ana on the next period's Monday starting 07:30
  And every new day is a draft

Scenario: nothing published is copied
  Then the new plan has no published day and no publication

Scenario: the same repeat twice
  When two confirms for the same source and start date arrive together
  Then one plan is made and the other is told a repeat already exists, with a link to it

Scenario: a taken name
  Then it is refused, and what I typed is kept

Scenario: it fails partway
  Then no part of the new plan is left behind, and the failure is recorded

Scenario: the source plan
  Then no row of the source plan has changed
```

- Writes `plan_repeat` first (state `building`), inside the same write as the plan when one
  transaction can hold it (story 00 decides). Otherwise the plan stays hidden from lists until
  the state is `ready`.

## Counter-measures

| Risk | Prevention |
|---|---|
| Two clicks make two plans | Unique index on `plan_repeat` (source plan, new start date). The loser reads the winner's row. A "does it exist?" check alone does not stop an overlap (EXC-1) |
| A day lands on a date that already has one | Cannot happen: the people are new rows, and a day is unique per (person, date). Asserted in a test anyway |
| Two people share a name after a rename | Same rule the template uses: skip both, name them, never fail the whole plan on the database's unique index |
| A half-built plan is visible and someone starts working in it | State `building` hides it from every plan list; `failed` is cleaned up and reported on the Health page |
| Accepted maps copied from the template, not the plan | Read `planner_workspace_map` of the **source plan** |
| A map the plan accepts is now archived | Not copied; named in the result |
| Dates drift across a month or leap day | Dates move by a number of days through the same date maths the template uses (`planTemplate.ts::windowEnd`), unit-tested on month, year and leap-day edges |
| The source plan is written by mistake | Test compares row counts and a board hash of the source before and after |

## Governance

- **Errors (suggested):** `E-REPEAT-004` name empty or too long · `E-PLN-001` name taken (existing) · `E-REPEAT-005` a repeat for this start date already exists · `E-REPEAT-006` the write failed and was rolled back.
- **Events:** `plan.repeated` (source, new plan, days moved, counts) · `plan.repeat_skipped_person` (warn, shows on Health) · a failure records `plan.repeat_failed`.
- **Delete behaviour:** deleting a plan removes its `plan_repeat` rows as the new plan; a source plan that was repeated keeps its history link as a plain number, never a blocker.

## Tests (write first)

| ID | Test |
|---|---|
| T-REPEAT-02-1 | Window length and dates for 7, 14 and 31-day plans, across a month end and a leap day |
| T-REPEAT-02-2 | Accepted maps come from the plan, not the template |
| T-REPEAT-02-3 | People copied with every field; AI model kept |
| T-REPEAT-02-4 | Inactive, off-roster and switched-off people skipped and named |
| T-REPEAT-02-5 | Days moved, start times kept, all draft |
| T-REPEAT-02-6 | Two parallel confirms leave one plan |
| T-REPEAT-02-7 | Forced failure leaves no rows |
| T-REPEAT-02-8 | Source plan unchanged |
| T-REPEAT-02-9 | Second account refused |

## Keep a pulse on

- A person's daily hours are copied from the **plan**, not their profile. If the profile changed, the new plan keeps the plan's value. Say so in the preview if it differs.
