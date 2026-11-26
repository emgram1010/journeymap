# US-REPEAT-2-01 — Choose what comes along

**Epic:** REPEAT-2 · **Size:** M · **Status:** 🚧 In build
**Depends on:** REPEAT-1

## Description

Today a repeat copies everything. The planner wants to decide: sometimes only the people, sometimes the jobs without the schedule. Three boxes on the repeat window, all ticked by default.

## Story

**As a** planner, **I want** to tick what a repeat carries (people, jobs, assignments), **so that** the new plan starts with exactly what I need.

## Acceptance (Gherkin)

```gherkin
Scenario: everything ticked is today's repeat
  Given a plan with people, days, jobs and slots
  When I repeat it with all three boxes ticked
  Then the new plan has the same counts as a REPEAT-1 repeat

Scenario: jobs unticked
  When I untick Jobs
  Then the preview shows 0 jobs
  And the new plan has the people and their days
  And slots that belonged to a job are not created

Scenario: assignments unticked
  When I untick Assignments
  Then the new plan has the people and the jobs
  And it has no days and no scheduled slots
  And every job step waits in Unscheduled

Scenario: people unticked
  When I untick People
  Then Assignments is unticked and greyed
  And the new plan has no people, no days and no slots
  And the jobs still come

Scenario: the server does not trust the screen
  When a request skips people but asks for assignments
  Then the server still makes no days and no slots

Scenario: a caller that says nothing
  When a request names no choices (the AI tool, an older screen)
  Then everything is copied
```

## Counter-measures

- The three inputs are **skip** flags, so an omitted one (which arrives as `false`) means "copy". An omitted input can never remove work.
- One rule in `repeat/build_plan`; the preview and the copy both read it.
- The choices are stored with the repeat's counts and on its event.

## Tests

- T-REPEAT2-01-1 all ticked = REPEAT-1 counts
- T-REPEAT2-01-2 jobs unticked
- T-REPEAT2-01-3 assignments unticked
- T-REPEAT2-01-4 people unticked forces assignments off (server)
- T-REPEAT2-01-5 preview equals copy for each choice
- UT: the screen model (people off greys assignments; the request body; the summary line)
