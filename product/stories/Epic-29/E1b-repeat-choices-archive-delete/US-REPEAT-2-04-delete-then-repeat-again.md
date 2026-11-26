# US-REPEAT-2-04 — Delete a copy, then repeat again

**Epic:** REPEAT-2 · **Size:** S · **Status:** ✅ Built (2026-11-26)
**Depends on:** story 03

## Description

A repeat to a date can be made once. If the copy was wrong, the planner was stuck: archiving it did not free the date. Deleting the copy now does. The screen confirms first and names what will be removed.

## Story

**As an** admin, **I want** to delete a wrong repeat and make it again, **so that** a mistake costs me one click, not a workaround.

## Acceptance (Gherkin)

```gherkin
Scenario: the screen asks first
  Given I am an admin on a plan
  When I press Delete plan in Workspace Settings
  Then I see how many people, days, jobs and slots will be removed
  And that this cannot be undone
  When I confirm
  Then the plan is gone and another plan opens

Scenario: a plan that cannot be deleted
  When the plan has history
  Then the screen shows the reason and offers Archive instead

Scenario: a member
  Then the Delete plan button is not shown

Scenario: repeat again
  Given plan A was repeated to 2027-01-04 and that copy was deleted
  When I repeat plan A to 2027-01-04 again
  Then a new plan is made

Scenario: the original is deleted
  Given a copy made from plan A
  When plan A is deleted
  Then the copy still opens
  And its history says the original no longer exists
```

## Counter-measures

- The button is hidden for non-admins, and the server refuses them anyway.
- The confirm shows the server's own counts (`GET` the delete check), not a guess.

## Tests

- T-REPEAT2-04-1 delete the copy, repeat to the same date: created
- T-REPEAT2-04-2 delete the source: the copy opens, history `exists: false`
- T-REPEAT2-04-3 the delete check returns counts and the refusal reason
- UT: the confirm sentence; the button rule
