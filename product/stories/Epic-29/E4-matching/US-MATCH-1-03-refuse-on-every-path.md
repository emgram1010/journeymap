# US-MATCH-1-03 — Every way of assigning work goes through the rule

**Epic:** MATCH-1 · **Size:** L · **Model:** **Opus 5.5** · **Status:** 📋 Not built
**Depends on:** stories 00, 01 · **Decision:** D-3 (founder): no planner override
**Prerequisite (README F-16):** close the two live gaps first — 542 must check the day's owner when
a slot is created on a day with no override; 541 must check when only the date changes — and make
`assert_agent_assignable` count `ai_member_profile.is_paused`. Each fix ships with its own test.

## Description

A hard need means the work **must** go to someone who holds it. That is only true if every way
of putting work on a person checks it. README F-8 lists them: the board's drag and drop, the
schedule action, moving a whole card, changing who owns a day or its date, the AI's scheduling
tools, a repeat, and an outside order landing on a live day.

Most of them already call one shared check, `planner_ops/assert_agent_assignable` ("may new work
land on this plan column"). This story **extends that check** — it gains the date and the steps
being placed, and calls `match/check` — instead of adding a second guard to each caller. When it
refuses, the work is **not** placed: it stays where it was (or in the backlog), with the reason,
and what the planner did on the screen is kept.

The UI helps; the server always checks again.

## User story

**As** an owner, **I want** a hard need and a day off to be respected no matter how work is
assigned, **so that** the rule cannot be got around by using a different button.

## Acceptance criteria

```gherkin
Scenario Outline: a hard mismatch is refused
  Given matching is on and Ana does not hold a hard need of a step
  When the step is given to Ana by <path>
  Then it is refused with the same reason text, and nothing is written

  Examples:
    | path                                             |
    | scheduling a step (560)                          |
    | scheduling a whole card (583)                    |
    | placing or moving a slot (543)                   |
    | changing a slot's person (545)                   |
    | creating a slot directly on a day (542)          |
    | changing who a day belongs to, or its date (541) |
    | changing the login a plan column points to (536) |
    | the AI tool plan_schedule_step                   |
    | the AI tool plan_schedule_card                   |
    | a repeat (REPEAT-1 story 04)                     |
    | an outside order onto a live day (DEMAND-1)      |

Scenario: not available that day
  Then the same paths refuse, with AVAIL-1's reason
  And creating a day for someone who is off is refused too (538, create_timeline, the AI tool plan_start_day)

Scenario: reordering a day (544)
  Then it is not checked: 544 only reorders slots already on that day and refuses anything else

Scenario: a soft mismatch or a full day
  Then the work is placed, and the response carries the warning

Scenario: several items at once, some refused
  When a card of 5 steps is scheduled and 2 are refused
  Then nothing is placed, and all refusals are listed
  And I am offered "place the 3 that fit"

Scenario: changing who a day belongs to
  When a day with 6 items is given to Ben and 1 item does not fit Ben
  Then it is refused, the item is named, and I am offered to move the day and send that item to the backlog

Scenario: a repeat
  Then a copied assignment that no longer fits goes to the backlog, marked "needs review" with the reason
  And the repeat itself never fails for that

Scenario: an outside order onto a live day
  Given the routed member does not fit
  Then the order is not placed; it is listed as "needs a person" on the Health page and in the planner

Scenario: moving work within the same person and day
  Then it is not rechecked for needs (nothing changed), only for hours

Scenario: unassigning, or moving to the backlog
  Then it is never refused

Scenario: what I did is kept
  When a drag is refused
  Then the item returns to where it was and the reason is shown; nothing I typed is lost

Scenario: show-only mode
  Then everything is placed, warnings are shown, and would-be refusals are counted

Scenario: matching is off
  Then every path behaves exactly as it does today
```

## Counter-measures

| Risk | Prevention |
|---|---|
| A path is missed, now or later | Story 00's list, plus a build guard: any file that writes `planner_task`, `planner_task_work_task` or a day's person must call the guard, or the build fails |
| Each endpoint gets its own copy of the guard | No new guard: the existing shared check `planner_ops/assert_agent_assignable` is extended and calls `match/check`. Callers pass the date and step ids explicitly |
| 583 keeps its own copy of the card rule instead of calling `schedule_card` (README F-8) | Fold 583 onto `schedule_card` first, or the two copies drift once matching is added |
| `place_task` (117) is called without a check by a future caller | It checks nothing itself today; the build guard below covers any new caller |
| A refusal leaves half a card placed | All-or-nothing inside the caller's transaction; the guard runs **before** any write |
| The guard is a "does it fit?" read that is stale by the time of the write | It runs inside the same request, on the same reads the write uses; Publish to live rechecks anyway (story 04) |
| Two planners take the same person's last hours | Hours are a warning, not a refusal (D-9), so there is no race to lose |
| The guard runs inside a transaction and logs there | The check is pure and may run inside; logging the refusal happens outside, after rollback |
| A function called without an optional input silently inherits the caller's input of the same name | Every input is passed explicitly (`""`, `0`, `false` for none) |
| Different wording per path | Reasons come from `match/check`; a test asserts identical text across all paths |
| A live day is changed by a refusal | A refusal writes nothing. The same-day add-only path (D-11 of Epic-27) stays add-only |
| The repeat fails as a whole because one person no longer fits | The repeat treats a refusal as "to the backlog", never as an error |
| An AI retries a refused placement in a loop | The refusal is a normal tool answer with the reason and the suggest list; refusals count toward the AI's caps |
| Existing over-full or mismatched plans cannot be edited at all | Only the **placement being made** is checked. Work already sitting somewhere is marked for review (story 04), never ejected |

## Governance

- **Errors (suggested):** `E-MATCH-010` "This needs {requirement}. {person} does not hold it." · `E-MATCH-011` "{person} is not working on {day}: {reason}." Both carry the list of all reasons.
- **Warnings:** `W-MATCH-001` soft need not held · `W-MATCH-002` not enough hours left.
- **Events:** every refusal records `matching.refused` (path, person, work, reasons, actor). Every placement with a warning records the warning. Show-only records `matching.would_refuse`.
- **Health page:** refusals by path and by reason; outside orders that need a person.

## Tests (write first)

| ID | Test |
|---|---|
| T-MATCH-03-1 | One functional test per path in the outline: hard mismatch refused, nothing written |
| T-MATCH-03-2 | The same per path for "not available" |
| T-MATCH-03-3 | Reason text identical across paths |
| T-MATCH-03-4 | Soft mismatch and full day placed with warnings |
| T-MATCH-03-5 | Card of 5 with 2 refused: nothing placed; "place the 3 that fit" works |
| T-MATCH-03-6 | Day handed to another person with one misfit |
| T-MATCH-03-7 | Repeat: misfit goes to backlog with a mark; repeat succeeds |
| T-MATCH-03-8 | Outside order: listed, not placed |
| T-MATCH-03-9 | Off: every path's response identical to before (recorded baseline) |
| T-MATCH-03-10 | Show only: all placed, counts recorded |
| T-MATCH-03-11 | Build guard: a planted unguarded write fails the build |
| T-MATCH-03-12 | UI: refused drag returns the item and shows the reason |

## Keep a pulse on

- This closes REPEAT-1 story 04's open hook ("drop anyone unavailable", D-2).
- Refusals by path on the Health page: one path with far more refusals than the rest usually means its screen is not showing the suggestion.
