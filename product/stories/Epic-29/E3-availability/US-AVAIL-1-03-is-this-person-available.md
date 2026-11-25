# US-AVAIL-1-03 — One answer: is this person available that day?

**Epic:** AVAIL-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** stories 01, 02; REQ-1 story 03 (the link to a profile) · **Decision:** D-9

## Description

Working days, time off, active or not, an AI that is paused: four facts in four places. If each
screen and endpoint pieced them together itself, they would disagree within a month.

This story is the one function (`avail/person_day`) that answers for a person on a plan and a
date, with a TypeScript twin so the board can show the same answer without a round trip. It
returns the answer **and the reason**, in plain words, because "not available" with no reason is
a support call.

## User story

**As** a planner, **I want** one clear answer about whether someone can work a given day and why
not, **so that** I trust it and do not check by hand.

## Acceptance criteria

```gherkin
Scenario: available
  Given Ana works that weekday, has no time off, and is active
  Then the answer is available, with her hours for that day and her hours left

Scenario: a day off in the pattern
  Then not available: "Ana does not work Fridays"

Scenario: time off
  Then not available: "Ana is away 3–5 March"

Scenario: inactive on the plan, off the roster, or login switched off
  Then not available, with which one

Scenario: an AI member that is paused
  Then not available: "paused", and whether by a person or automatically

Scenario: no profile linked
  Then available every day at the plan's daily hours, with the note "no profile, so no working days recorded"

Scenario: more than one reason
  Then every reason is returned, the most lasting first (inactive, then day off, then time off)

Scenario: hours left
  Given Ana has 8 hours that day and 6 hours 30 minutes scheduled
  Then hours left is 1 hour 30 minutes

Scenario: over-full
  Given more is scheduled than her hours
  Then hours left is negative, and she is still "available" (it is a warning, D-9)

Scenario: many people, many days
  When a board asks for 10 people over 7 days
  Then one call answers all 70, with a fixed number of database reads

Scenario: the app agrees with the server
  Then the TypeScript twin gives the same answer for every golden case
```

## Counter-measures

| Risk | Prevention |
|---|---|
| The rule is copied into the board, the endpoints and the AI tools | One function and one twin. A build guard fails if another file reads the two availability tables |
| The server and the app drift | A shared file of golden cases (dates, patterns, time off, expected answer) run on both sides |
| A per-person, per-day loop of database reads | Load the plan's people, patterns and time off for the window once; answer from memory |
| `0` hours left is read as "not set" | Hours are numbers that may be zero or negative; never tested with `== null` |
| A missing optional key in the loop throws | Read optional keys through `??` into a variable before branching |
| A branch in the loop reads a variable updated in the same pass and silently writes nothing | Branch only on the loop item; build the per-day facts in a first pass |
| Membership tested with `contains` on an array (always false) | Membership by a loop, or by `in` inside a query |
| Hours left uses a different sum from the board | Reuses the sum found in story 00 |
| Weekday worked out differently around midnight | Dates are plain; weekday from the date alone, pinned by test dates |

## Governance

- **Errors:** none for the user; this is a read.
- **Events:** none per call. The nightly audit runs the golden cases against live and records a failure event on any mismatch.

## Tests (write first)

| ID | Test |
|---|---|
| T-AVAIL-03-1 | Golden cases: each reason alone, and combined |
| T-AVAIL-03-2 | Edge days of time off |
| T-AVAIL-03-3 | Paused AI; switched-off login; off the roster |
| T-AVAIL-03-4 | No profile linked |
| T-AVAIL-03-5 | Hours left: zero, positive, negative; per-day hours override |
| T-AVAIL-03-6 | 10 people × 7 days in a fixed number of reads |
| T-AVAIL-03-7 | Server and TypeScript twin agree on every golden case |
| T-AVAIL-03-8 | Build guard: only this function reads the availability tables |

## Keep a pulse on

- This function is the availability half of MATCH-1's one rule. MATCH-1 calls it; it does not copy it.
