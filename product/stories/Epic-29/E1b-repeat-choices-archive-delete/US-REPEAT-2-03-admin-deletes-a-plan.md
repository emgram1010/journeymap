# US-REPEAT-2-03 — An admin deletes a plan that has no history

**Epic:** REPEAT-2 · **Size:** M · **Status:** 🚧 In build · **Risk:** high (first plan delete)
**Depends on:** PLN-3 (the held delete), REPEAT-1 story 00 (the list of everything that hangs off a plan)

## Description

A plan could never be deleted: the PLN-3 delete was written and held. Since then a plan grew from 3 child tables to 13. This story rewrites the delete to cover all of them and adds the rule for when it is allowed.

## Story

**As an** account admin, **I want** to delete a plan that was made by mistake, **so that** it is really gone and does not clutter the account.

## Acceptance (Gherkin)

```gherkin
Scenario: an admin deletes a draft plan
  Given a plan with people, days, jobs and slots, never published
  When an admin deletes it
  Then the plan and every row under it are gone
  And no other plan lost a row
  And a "plan.deleted" event records how many rows went

Scenario: a member cannot
  When a member who is not an admin tries to delete a plan
  Then it is refused and nothing changes

Scenario: an AI cannot
  When an AI identity tries to delete a plan
  Then it is refused (E-COP-025)

Scenario: a plan with a published day
  Given one of the plan's days was published to live
  When an admin tries to delete it
  Then it is refused: "This plan has work recorded against it. Archive it instead." (E-P3A-001)

Scenario: a plan holding customer orders
  Given the plan has a job that came from a customer order
  Then delete is refused with E-P3A-004

Scenario: orders are routed into the plan
  Then delete is refused with E-P3A-005

Scenario: another account's plan
  Then it answers "Plan not found"

Scenario: a failure part-way
  When any row fails to delete
  Then nothing is deleted
```

## Counter-measures

- One `db.transaction`; each row deleted by its own id (a delete by a shared field removes only the first match).
- No sentinel id is ever looped over by a delete (REPEAT-1 story 06 learning).
- The decision (`planner/delete_check`) is separate from the write (`planner/delete_workspace_cascade`), so the screen can ask "may I?" without deleting.
- After the write, the endpoint counts what is left under the plan and logs a failure if anything is.
- Tested on a throwaway plan in the test account before it is trusted.

## Tests

- T-REPEAT2-03-1 full delete leaves zero rows in all 13 tables
- T-REPEAT2-03-2 a neighbour plan is untouched (counts before and after)
- T-REPEAT2-03-3 member refused · T-REPEAT2-03-4 AI refused
- T-REPEAT2-03-5 published day refused (E-P3A-001)
- T-REPEAT2-03-6 customer-order job refused (E-P3A-004) · order route refused (E-P3A-005)
- T-REPEAT2-03-7 other account: not found
