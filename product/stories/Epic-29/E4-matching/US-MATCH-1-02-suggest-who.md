# US-MATCH-1-02 — Suggest who

**Epic:** MATCH-1 · **Size:** M · **Model:** Opus 5.5 (Sonnet 5.5 is fine for the screen) · **Status:** 📋 Not built
**Depends on:** story 01

## Description

The founder's original question: "if there's a specific task, who should it be assigned to?"
This story answers it on the screen. For a piece of work and a day, the planner sees the people
on the plan in order: who fits best first, who cannot take it last, each with the reason.

The planner still chooses. The system ranks and explains.

## User story

**As** a planner, **I want** to see who fits a piece of work, best first, and why,
**so that** I pick the right person quickly instead of remembering who can do what.

## Acceptance criteria

```gherkin
Scenario: open the list
  When I pick a piece of work and a day
  Then I see every active person on the plan, in order

Scenario: the order
  Then people who may take it come first, ordered by:
    1. fewest soft needs missing
    2. enough hours left before not enough
    3. most hours left
    4. name
  And people who may not take it come last, greyed, each with every reason

Scenario: the same order every time
  Given nothing has changed
  Then the list is in the same order on every load

Scenario: why this person is first
  Then each person shows a short line: "Holds everything · 3 h left"

Scenario: nobody fits
  Then I see "Nobody on this plan can take this on <day>", the reasons grouped, and what would fix it
  (another day, someone who holds it and is not on the plan, a holding that ended)

Scenario: someone who fits but is not on this plan
  Then they are named under "not on this plan", for an admin to add; they cannot be picked directly

Scenario: no day chosen yet (backlog)
  Then I see, per person, the days in the plan on which they could take it

Scenario: pick someone
  When I pick a person who may take it
  Then the work is placed through the normal path (story 03 applies)

Scenario: a greyed person
  Then they cannot be picked, and the reason is shown on tap

Scenario: show-only mode
  Then greyed people can be picked, with the reason shown as a warning

Scenario: matching is off
  Then the list is today's plain list of people

Scenario: an AI asks
  Then a tool returns the same list in the same order, as data
```

## Counter-measures

| Risk | Prevention |
|---|---|
| The list and the save disagree | Both call `match/check`; a test picks the first suggested person on 20 golden cases and asserts the save accepts |
| An unstable order makes the screen jump | A total order ending in name then id; sorted with an explicit key (a space as the separator, never a NUL character or a pipe) |
| The list is slow on a big plan | One batch load of needs, holdings and availability for the plan's window |
| The list leaks private facts | It shows "away", never the time-off note; it shows holdings, which the account's planners may already see |
| The planner trusts the top name blindly | The reason line is always shown; soft misses and "not enough hours" are visible on the top name too |
| People in another plan are shown with details | Only their name and "not on this plan" |
| An AI treats the list as an instruction to assign | The tool returns data; placing is a separate, gated write |
| Ranking by hours left starves nobody of rest but overloads the least-booked | Accepted for now (fairness is a non-goal); noted below |

## Governance

- **Errors:** none new (a read).
- **Events:** `matching.suggested` is **not** logged per view. When a planner picks someone other than the first suggestion, the placement event records the rank they picked, so the ranking can be judged later.

## Tests (write first)

| ID | Test |
|---|---|
| T-MATCH-02-1 | Unit: order for a mixed set (fits, soft miss, low hours, refused) |
| T-MATCH-02-2 | Stable order across 10 loads |
| T-MATCH-02-3 | Nobody fits: grouped reasons and fixes |
| T-MATCH-02-4 | Backlog: per-person list of possible days |
| T-MATCH-02-5 | First suggestion is accepted by the save (20 cases) |
| T-MATCH-02-6 | Show-only and off modes |
| T-MATCH-02-7 | No time-off note in the response |
| T-MATCH-02-8 | AI tool returns the same order |

## Keep a pulse on

- **Picked rank.** If planners usually pick the third name, the order is wrong. Review after a month of use.
- Spreading work evenly is not built.
