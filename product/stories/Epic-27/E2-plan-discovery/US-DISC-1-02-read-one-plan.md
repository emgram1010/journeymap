# US-DISC-1-02 — Read one plan (`plan_get`)

**Epic:** DISC-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** ✅ Built 2026-11-21 (see epic Test Results)
**Depends on:** US-DISC-1-01

## Description

Before an AI changes a plan it needs to know who is on it, what jobs it holds, and which days
are still draft and which are live. Today it cannot see any of that, so it acts blind. This
tool is the read that should come before every plan write.

**Assumed:** a "day" is a `planner_timeline` row for one member and one date, and "live" is
what LIVE-1 / REPUB-1 mark as published. Confirm against live before building.

## User story

**As** an AI, **I want** to read a plan's members, jobs and days with their status, **so that**
I know what is draft, what is live and who owns what before I change anything.

## Acceptance criteria

```gherkin
Scenario: read a plan
  Given plan 146 in my business
  When plan_get is called with its id
  Then I get the plan header (id, name, window, archived)
  And members: id, name, kind (person or ai), has_login (yes/no), active
  And jobs: id, title, map id and title, pinned version number, status
  And days: id, member id, date, state (draft or live), planned minutes, capacity minutes

Scenario: an empty plan
  Given a plan with no members, jobs or days
  Then the three lists are empty and nothing errors

Scenario: a plan that is not mine
  Given a plan in another account, or in another business
  Then the answer is "Plan not found" in both cases

Scenario: a date range
  When plan_get is called with date_from and date_to
  Then only days in that range are returned

Scenario: no date range
  Then days from 7 days ago to 14 days ahead are returned, and the response says which range was used

Scenario: a large plan
  Given more than 200 jobs
  Then the first 200 open jobs are returned with jobs_truncated true and a total count

Scenario: it is read-only
  Then no row is written except the tool log, and no approval is asked for
```

- Available to the in-app copilot **and** the outside connector: add the tool to both tool lists.
- `has_login` is yes/no only. The member's email and user id are not returned.
- Over capacity is shown as data (`planned_minutes > capacity_minutes`), not as an error.

## Counter-measures

| Risk | Prevention |
|---|---|
| Optional date inputs do not exist when left out and crash the call | Declare `date_from` / `date_to` as **text**; widen to `"0001-01-01"` / `"9999-12-31"` or the default range when empty |
| Day totals are wrong because a tally inside a loop is lost | Scope the task query with `timeline_id in $ids` and branch only on the loop item, as endpoint 539 does |
| The tool becomes a second, different view of the plan | Reuse the functions behind endpoints 539 and the roster; do not write new queries where one exists |
| Member names are stale | Until AIM-1 story 02 ships, return the stored name. After it, use the same display-name function |
| Personal data leaves through the connector | No email, no user id, no phone. Names and ids only |
| A "not allowed" answer confirms a plan exists in another account | Same "Plan not found" for both |
| One call returns megabytes | Day range default and job cap, with truncated flags and totals |

## Governance

- **Events:** the gate's tool-log row. A failure (for example a broken join) records a failure event.
- **Friendly messages:** "Plan not found"; "date_from must be a date like 2026-11-21".

## Tests (write first)

| ID | Test |
|---|---|
| T-DISC-02-1 | Plan 146: members, jobs and days match the plan screen |
| T-DISC-02-2 | Empty plan returns three empty lists |
| T-DISC-02-3 | Other account and other business both return "not found" |
| T-DISC-02-4 | Date range filters days; default range is reported |
| T-DISC-02-5 | No email or user id anywhere in the response |
| T-DISC-02-6 | Row counts in the database are unchanged after the call (except the tool log) |
| T-DISC-02-7 | Works from the in-app copilot and from the connector |
