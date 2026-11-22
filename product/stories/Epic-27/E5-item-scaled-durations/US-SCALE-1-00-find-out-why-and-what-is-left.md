# US-SCALE-1-00 — Find out why, and what is left to build (read-only)

**Epic:** SCALE-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not started
**No push happens in this story.**

## Description

The request asks for jobs that carry items and estimates that scale with quantity. The repo
already has an order-lines table, lines endpoints, a rates table and an estimate function
(EST-1, RATE-1, ITEM-1). Either those are built and something stops them being used, or they
are only partly live. Building the request as written would create a second estimate next to
the first. This story finds the real gap by reproducing the founder's own example.

## User story

**As** the owner, **I want** the builder to show me exactly why my order planned 11 hours,
**so that** we fix the real cause once and do not build something that already exists.

## Acceptance criteria

```gherkin
Scenario: reproduce the number
  Given plan 146 and the order with 2 six-foot tables and 14 adult chairs
  When the builder reads the job, its lines, its pinned version, that version's rates and the estimate
  Then it reports where the 11 hours comes from, stage by stage
  And what the hand calculation says it should be

Scenario: name the cause
  Then the report says which of these is true (one or more):
    | the job has no lines                                   |
    | the lines exist but the item has no rate in that version |
    | the rate exists but in a different unit or scale       |
    | the estimate is right but the card reads something else |
    | the estimate function is not live, or differs from the local file |

Scenario: what already exists
  Then for each of EST-1, RATE-1, ITEM-1 and CAT-1 the report says: live or not, matches local or not, tests passing or not

Scenario: what is left
  Then stories 01, 02 and 03 are each marked: build as written, build smaller, or not needed
  And the founder sees this before any of them starts
```

**Things to fetch (read-only):** table 139 and 138 schemas and a few rows; endpoints 607 and
608; `estimate/compute_estimate`; `planner/job_step_hydration` and `derive_tasks`; the job and
day rows for the example order on plan 146; the Items row of the map it uses.

## Counter-measures

| Risk | Prevention |
|---|---|
| The check changes data | Read tools only. If a scratch function is needed to run the estimate, it only reads, and is deleted after |
| A stored `0` is read as "no rate set" (or the reverse) | An untouched decimal is `0`, not null. Say for each rate whether it is a real zero or never set, using the row's own history, not the number |
| The estimate is judged from the local file while live differs | Fetch the live function and diff first |
| The story drifts into fixing | It ends with a report. The fix belongs to stories 01–03 |
| EST-1's "To-do" status is trusted | The epic file says To-do but its table and function exist. Check its Test Results and live state, then say which is true |

## Governance

Nothing is written, so no events. The report is added to `epic.md` section 2 as a table.

## Tests

None. The gate is the report: the 11 hours explained stage by stage, the hand calculation
beside it, and a build / smaller / not-needed mark on each later story.
