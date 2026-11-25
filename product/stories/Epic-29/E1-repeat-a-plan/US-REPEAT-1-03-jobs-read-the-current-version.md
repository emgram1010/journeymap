# US-REPEAT-1-03 — Repeated jobs read the current published version

**Epic:** REPEAT-1 · **Size:** L · **Model:** **Opus 5.5** · **Status:** ✅ Built and tested live (hidden until the button)
**Depends on:** story 02

## Description

A job does not hold its own steps. It points at one published map version and reads its steps,
durations and "done when" from there. That is what keeps live work safe from later edits.

It is also the trap in a repeat. Copy the job row and next week's job is pinned to last week's
definition, and the week after that, for ever. The map could be improved ten times and the
repeated work would never see it.

So a repeat does not copy jobs. It **creates new jobs** the same way a planner would by hand,
through the one function that writes jobs (`jobs/create_job`), pinned to each map's **current**
published version, then carries over what belongs to the job itself: title, attributes, item
quantities and its time window.

## User story

**As** a planner, **I want** next period's jobs to use the map as it is published now,
**so that** an improvement to the map reaches repeated work without rebuilding the plan.

## Acceptance criteria

```gherkin
Scenario: a job is repeated
  Given a job "Monday delivery run" on the source plan
  Then the new plan has a new job with the same title and attributes
  And it is open, with every step not started
  And it is pinned to the map's current published version

Scenario: the map did not change
  Then the new job has the same steps as the source job

Scenario: the map has a newer published version
  Then the new job has the newer version's steps
  And the result lists the job, with the steps added and the steps gone

Scenario: item quantities
  Given the source job has item lines
  Then the new job has the same items and quantities
  But an item that is inactive, or not in the new version's rates, is left off and named

Scenario: time window
  Given the source job has a time window
  Then the new job has the same window, moved forward by the same number of days

Scenario: jobs that never repeat
  Given an outside order, an exception child, or a cancelled job
  Then it is not repeated and the result says why

Scenario: a job the planner unticked
  Then it is not repeated

Scenario: a map that cannot be used
  Given the map is archived, deleted, no longer accepted by the plan, or has no published version
  Then the job is not repeated and the result says why

Scenario: nothing from the job's history comes along
  Then the new job has no activity, no start or finish time, no exception and no order origin

Scenario: a parent job that repeats and a child that does not
  Then the new job has no parent link

Scenario: all or nothing
  When any job fails to write
  Then no job, step, line or window of the new plan exists
```

- Attributes are copied with their `source` set to say they came from a repeat, and `entered_at` now.
- Flagged quantities on a line are **not** copied (they are a fact about last period's order).

## Counter-measures

| Risk | Prevention |
|---|---|
| A second way to create jobs drifts from the first | Only `jobs/create_job` and `jobs/tasks_from_version` are used. No new job-writing code |
| "Current published version" picked wrongly (a draft, an archived map) | One lookup function, the same one "add a job" uses; tested with a map that has a newer draft |
| An outside order is repeated and looks like a real order | Excluded by rule; no `work_item_origin` row is ever written by a repeat |
| A step that moved in the new version is confused with a new step | Steps are matched by (stage key, row key), which never change after creation; anything unmatched is reported, not guessed |
| A big repeat times out halfway | Story 00's measurement decides: one transaction, or staged under `building`. Never a visible half-plan |
| `function.run` inside a transaction | Allowed for a write-only helper (measured in EXC-1); logging and anything outward stay outside |
| The freeze on item lines ("no change once work starts") blocks the copy | New jobs have no started work; lines are written at creation, like "add a job" |
| Attributes merge instead of replace | A new row has nothing to merge into; if a later edit is added, use the two-step patch for `json` |
| A missing optional key in a stored attribute crashes the loop | Read optional keys through `??` into a variable first |

## Governance

- **Errors (suggested):** `E-REPEAT-007` no job could be repeated (the plan is still created; this is a warning in the result, not a refusal).
- **Events:** one `plan.repeat_jobs` event with counts: repeated, on a newer version, left out by rule, left out by the planner, could not repeat. Each "could not repeat" is listed in the metadata. Failure records a failure event.
- **Delete behaviour:** unchanged. Repeated jobs are ordinary jobs.

## Tests (write first)

| ID | Test |
|---|---|
| T-REPEAT-03-1 | Same version: same steps, all not started, job open |
| T-REPEAT-03-2 | Newer version: new steps, change list correct |
| T-REPEAT-03-3 | Newer **draft** is ignored |
| T-REPEAT-03-4 | Lines copied; inactive item and item missing from the rates left off and named |
| T-REPEAT-03-5 | Time window moved, including one that crosses midnight |
| T-REPEAT-03-6 | Outside order, exception child, cancelled job not repeated |
| T-REPEAT-03-7 | Archived map, no published version, map no longer accepted |
| T-REPEAT-03-8 | No activity, origin, exception or parent on the new job |
| T-REPEAT-03-9 | Forced failure on the last job leaves nothing |
| T-REPEAT-03-10 | 50 jobs repeated within the measured limit |

## Keep a pulse on

- D-6 (current version, not last period's) is the builder's pick.
- If a business needs "repeat exactly as it was, old version and all", that is a different feature: say so before bending this one.
