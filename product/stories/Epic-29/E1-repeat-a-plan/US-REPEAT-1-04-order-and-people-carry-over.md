# US-REPEAT-1-04 — The order and the people carry over

**Epic:** REPEAT-1 · **Size:** L · **Model:** **Opus 5.5** · **Status:** 🔨 Built and tested live, except review marks (table not pushed)
**Depends on:** stories 02, 03 · **Decision:** D-2 (founder, 2026-11-25), D-7 (builder)

## Description

The frame and the jobs exist. What makes a repeat worth having is the part that took the planner
the longest: which step sits on whose day, in what order.

Each scheduled slot in the source plan becomes a slot in the new plan: on the matching person's
matching day, in the same position. The slot is linked to the **new** job's matching step.

The founder's decision (D-2): the people stay on the work, every copied slot is marked "needs
review", and anyone who cannot do it is dropped, with their work sent to the backlog and the
reason given.

## User story

**As** a planner, **I want** next period to start with the same order and the same people,
**so that** I only change what is different this time.

## Acceptance criteria

```gherkin
Scenario: a scheduled step carries over
  Given step "Load the truck" of a job sat second on Ana's Monday
  Then in the new plan the matching step of the new job sits second on Ana's next Monday

Scenario: a step given to someone other than the day's owner
  Then the new slot is given to the matching person in the new plan

Scenario: a free-standing slot (not linked to a job)
  Then it is copied with its title, length and notes

Scenario: backlog
  Then work that was in the source backlog is in the new backlog, in the same order

Scenario: every copied slot needs review
  Then each slot placed on a day by the repeat is marked "needs review: copied from <plan name>"

Scenario: the person was left off the new plan
  Given Ana was inactive and not added
  Then her slots are in the backlog, marked "needs review: Ana is no longer on the plan"

Scenario: a step that no longer exists
  Given the new version dropped a step
  Then its slot is not created and the result names it

Scenario: a step that is new
  Given the new version added a step
  Then it is in the backlog, marked "needs review: new step in this version"

Scenario: lengths
  Then each slot's length comes from the new job's estimate
  And a length the planner changed for last period's job is not carried, and the result counts those

Scenario: manual start times
  Given a slot had a manual start time of 10:00
  Then the new slot has a manual start time of 10:00

Scenario: order is clean
  Then each new day's positions run 1, 2, 3 with no gap and no repeat

Scenario: a step is never scheduled twice
  Then no step of a new job is linked to two slots

Scenario: all or nothing
  When any slot fails to write
  Then no part of the new plan exists
```

- **Open hook for MATCH-1:** "anyone unavailable" (D-2) cannot be checked until availability
  exists (AVAIL-1). This story drops **inactive** people only. MATCH-1 story 03 adds the
  availability and hard-requirement check to the same step, through the one matching function.

## Counter-measures

| Risk | Prevention |
|---|---|
| A branch inside a loop reads a variable updated earlier in the same pass and silently writes nothing | Two passes: the first records each lookup as a field on the row, the second branches on the row's own field (the confirmed-safe shape in `assert_agent_profiles_eligible`) |
| Looking up "new person for old person" with a variable key returns null and drops slots quietly | Pre-seed every key; test with a person at each end of the list |
| Gaps or duplicate positions after dropped slots | Run the existing resequence function (PLN-7) on every new day and on the backlog, then `planner/audit_sequences` |
| A step linked to two slots | The unique index on `planner_task_work_task.work_task_id` refuses it; the write rolls back |
| A slot's length comes from last period's change and quietly sticks for ever | Lengths are recomputed; carried changes would turn a one-off into a standing rule nobody chose |
| Manual start times that made sense only once | They carry (D-7) and are covered by the "needs review" mark |
| A patch on many rows touches only the first | Every multi-row write is "query, then loop by id" inside the transaction |
| The count in the result is the function's own guess | Counts are re-queried after the write, not taken from loop counters |
| The repeat runs the planner's hand-scheduling guards and is refused on its own copies | It calls the same placement function those endpoints use (`planner/place_task`), so one rule covers both |

## Governance

- **Errors:** none new; a failure is `E-REPEAT-006` (rolled back).
- **Events:** `plan.repeat_schedule` with counts: slots placed, sent to backlog and why (person left off, new step), slots not created (step gone), length changes not carried, manual start times carried.
- **Health page:** a repeat that sent more than half its slots to the backlog is shown as a warning, because it usually means the roster changed more than the planner expected.

## Tests (write first)

| ID | Test |
|---|---|
| T-REPEAT-04-1 | Position and day match for every slot of a 3-person, 5-day plan |
| T-REPEAT-04-2 | Slot given to another person maps to the new person |
| T-REPEAT-04-3 | Free-standing slots and backlog order |
| T-REPEAT-04-4 | Every placed slot has a review row with the right reason |
| T-REPEAT-04-5 | Left-off person's slots in the backlog with the reason |
| T-REPEAT-04-6 | Step gone: no slot, named. Step new: backlog, marked |
| T-REPEAT-04-7 | Lengths recomputed; changed lengths counted, not carried |
| T-REPEAT-04-8 | Manual start times carried |
| T-REPEAT-04-9 | `audit_sequences` clean on the new plan |
| T-REPEAT-04-10 | Forced failure leaves nothing |
| T-REPEAT-04-11 | Counts in the result equal a fresh query |

## Keep a pulse on

- If planners keep re-entering the same length change every period, that is a signal the map's duration is wrong. Fix the map, not the repeat.
- **Assumed:** `planner_task_start_override` holds a time of day. Check in story 00.
