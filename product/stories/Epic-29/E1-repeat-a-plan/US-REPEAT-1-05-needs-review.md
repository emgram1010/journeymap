# US-REPEAT-1-05 — "Needs review" marks

**Epic:** REPEAT-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** story 04 · **Decision:** D-2 (founder), D-8 (builder)

## Description

A copied assignment is a guess: it was right last period. The founder's decision is that a
repeat keeps the people but tells the planner to look. This story is the "look": a mark on the
slot that says why it needs a second glance, a way to clear it, and a rule for what happens at
Publish to live.

The mark is its own small table (`planner_task_review`), not a new status. The slot's existing
`needs_info` status means something else (the job is missing information), and adding a value to
that column means changing a table whose text checks would be lost.

Later epics reuse the same mark: time off added after work was assigned (AVAIL-1 story 05) and a
qualification that ran out (MATCH-1 story 04).

## User story

**As** a planner, **I want** copied work to be clearly marked until I have looked at it,
**so that** I do not publish last period's guesses as this period's promises.

## Acceptance criteria

```gherkin
Scenario: see what needs review
  Given a repeated plan
  Then each marked slot shows a small "needs review" sign and its reason
  And each day shows how many of its slots are marked
  And the plan shows the total

Scenario: clear one
  When I mark a slot as reviewed
  Then the sign goes, and who cleared it and when is kept

Scenario: clear a day
  When I choose "Reviewed" for a day
  Then every mark on that day is cleared

Scenario: a change clears it
  When I move a marked slot to another person or another day
  Then its mark is cleared, because I have plainly looked at it

Scenario: Publish to live
  Given a day has 4 marked slots
  When I preview Publish to live
  Then I am told "4 items were copied and not yet reviewed"
  And publishing is allowed
  And publishing clears those marks, recorded as cleared by me at publish

Scenario: a slot is deleted
  Then its mark goes with it

Scenario: a plan with no marks
  Then nothing new appears on the screen

Scenario: another account
  Then it cannot see or clear my marks
```

## Counter-measures

| Risk | Prevention |
|---|---|
| Marks become noise and are ignored | Counts sit on the day and at the publish step, where the decision is made; one click clears a day |
| A mark blocks Publish to live and stops a business on a Monday morning | It never blocks (D-8). Hard requirements and availability block (MATCH-1); "you did not look" only warns |
| Publishing changes the frozen snapshot's hash | Marks are not part of the snapshot. A test publishes with and without marks and compares hashes |
| Clearing a day clears only the first mark | Query the marks, loop by id, in a transaction; re-query to confirm zero |
| A deleted slot leaves a mark behind | `planner/delete_task` removes the mark in the same transaction; the integrity audit counts orphans |
| The board read does not include the side table, so the sign never shows | The board endpoint (548) returns marks with its slots; a side table needs its read wired, or the frontend never sees it (AUTH-1 lesson) |
| An AI clears marks to make a plan look ready | Clearing is a person's action; refused for an AI caller, like Publish to live |

## Governance

- **Errors (suggested):** `E-REPEAT-008` slot not found · `E-REPEAT-009` a person must clear a review mark.
- **Events:** `plan.review_cleared` (one, a day, or at publish; with the count).
- **Delete behaviour:** a mark is deleted with its slot. A cleared mark is kept as history (cleared when, by whom).

## Tests (write first)

| ID | Test |
|---|---|
| T-REPEAT-05-1 | Board returns marks and reasons; counts per day and plan |
| T-REPEAT-05-2 | Clear one; clear a day (re-query shows zero) |
| T-REPEAT-05-3 | Moving a slot clears its mark |
| T-REPEAT-05-4 | Publish preview shows the count; publish clears and records |
| T-REPEAT-05-5 | Snapshot hash equal with and without marks |
| T-REPEAT-05-6 | Deleting a slot removes its mark; audit finds no orphan |
| T-REPEAT-05-7 | AI caller refused; second account refused |

## Keep a pulse on

- D-8: if the founder wants unreviewed copies to **block** Publish to live, it is one rule in the publish preview, and it should come with "Reviewed" on the publish screen itself.
