# US-AVAIL-1-04 — The board shows days off and hours left

**Epic:** AVAIL-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** story 03

## Description

A rule the planner cannot see is a rule that surprises them. Before anything is refused
(MATCH-1), the board should already show what the system knows: this person is off that day,
this person has an hour and a half left.

This story only **shows**. It refuses nothing. That makes it safe to release on its own and
useful from day one.

## User story

**As** a planner, **I want** to see who is off and how full each day is while I plan,
**so that** I place work where it can actually be done.

## Acceptance criteria

```gherkin
Scenario: a day off
  Given Ana does not work Fridays
  Then her Friday on the board is shown as a day off, with the reason on hover or tap

Scenario: time off
  Then her days away are shown as away, without the private note

Scenario: hours left
  Then each day shows scheduled time against the person's hours for that day

Scenario: over-full
  Then the day is shown as over, by how much

Scenario: it updates as I plan
  When I place or move work
  Then hours left changes at once, without reloading

Scenario: work already on a day off
  Given work sits on a day that is now a day off
  Then the day shows a clear warning with the count of items

Scenario: no profile
  Then the person shows "no working days recorded" once, not on every day

Scenario: nothing is recorded for anyone
  Then the board looks exactly as it does today, plus hours against daily hours

Scenario: phone width
  Then the signs are readable without sideways scrolling

Scenario: not by colour alone
  Then every sign has text or an icon as well as a colour
```

## Counter-measures

| Risk | Prevention |
|---|---|
| The board works it out itself and disagrees with the server | It uses the TypeScript twin and the same golden cases |
| The board read does not include availability, so nothing shows | Availability for the plan's window is returned with the board (or a dedicated read wired to the screen) |
| Showing hours changes how a planner already works with over-full days | It is shown, never enforced, in this story |
| The private note leaks into the board | The board read never includes notes; a test asserts the field is absent |
| A slow board on a long plan | One availability call for the whole window (story 03) |
| A planner assumes "shown as off" means "blocked" before MATCH-1 is on | The hover text says "you can still place work here" until matching is switched on |

## Governance

- **Errors:** none new.
- **Events:** none (display only). A failed availability read records a client event and the board still loads without the signs.

## Tests (write first)

| ID | Test |
|---|---|
| T-AVAIL-04-1 | Unit: day-off, away, hours-left and over-full signs from the twin |
| T-AVAIL-04-2 | UI: a day off and an away day render with reasons |
| T-AVAIL-04-3 | UI: hours left changes after a placement with no reload |
| T-AVAIL-04-4 | Board read has no `note` field |
| T-AVAIL-04-5 | With nothing recorded, the board matches today's screenshot plus hours |
| T-AVAIL-04-6 | Availability read fails: board still loads |

## Keep a pulse on

- **Assumed:** the board is `webapp/protype-2/src/planner/PlannerApp.tsx`. Confirm in REPEAT-1 story 00.
