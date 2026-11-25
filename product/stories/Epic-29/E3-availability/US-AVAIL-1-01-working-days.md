# US-AVAIL-1-01 — Working days

**Epic:** AVAIL-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** story 00

## Description

Most people work the same days each week. Recording that once answers most of "is this person
free that day?" before any time off is entered.

The pattern is on the lasting profile. It lists the weekdays a person works and, if it differs
from their usual, their hours on each. A person with no pattern recorded is treated as working
every day, which is exactly today's behaviour, so nobody's plan changes until someone records a
pattern on purpose.

## User story

**As** an admin, **I want** to record which days each person works,
**so that** work is never planned for a day they are not there.

## Acceptance criteria

```gherkin
Scenario: no pattern recorded
  Then the person is treated as working every day at their daily hours

Scenario: record a pattern
  When I set Ana to work Monday to Thursday
  Then Friday, Saturday and Sunday are days off for her

Scenario: different hours on one day
  When I set Ana's Thursday to 4 hours
  Then her hours on a Thursday are 4, and on other working days her usual daily hours

Scenario: clear the pattern
  Then she is treated as working every day again

Scenario: a pattern with no working day
  Then it is refused: "Pick at least one working day, or switch the person off instead"

Scenario: bad hours
  When hours are 0, negative, or more than 24
  Then it is refused with the allowed range, and what I typed is kept

Scenario: which weekday is day 1
  Then weekdays are stored as Monday = 1 to Sunday = 7, the same on the server and in the app

Scenario: an AI member
  Then a pattern can be recorded for it the same way

Scenario: who may edit
  Then admins and the owner may edit; an AI may not; the person may read their own

Scenario: another account
  Then it cannot see or change my people's patterns
```

## Counter-measures

| Risk | Prevention |
|---|---|
| "No rows" and "all days off" are confused | Rule: no rows = works every day. A pattern must have at least one working day, so "all off" cannot be stored |
| An hours value of 0 is read as "not set" | Hours are stored only when they differ from the usual; "not set" is a missing value with an explicit flag, never `0` (the optional-number rule in CLAUDE.md) |
| Weekday numbering differs between server and app | One function on each side, pinned by the same test dates (a known Monday, a known Sunday, a leap day) |
| Saving a pattern replaces only the first row | Save is "delete this profile's rows by id, then add the new ones" inside one transaction; re-query to confirm |
| A pattern change today quietly breaks next week's assigned work | Story 05 marks affected work for review |
| A person edits their own pattern to avoid work | Admin and owner only |

## Governance

- **Errors (suggested):** `E-AVAIL-001` pick at least one working day · `E-AVAIL-002` hours must be more than 0 and at most 24 · `E-AVAIL-003` profile not found · `E-AVAIL-004` a person must do this (AI refused).
- **Events:** `work_pattern.saved`, `.cleared` (profile, the days, actor).
- **Delete behaviour:** deleted with the profile (query, loop by id, in the profile's delete transaction).

## Tests (write first)

| ID | Test |
|---|---|
| T-AVAIL-01-1 | No pattern = every day |
| T-AVAIL-01-2 | Monday–Thursday pattern; Friday is off |
| T-AVAIL-01-3 | Per-day hours override; other days use the usual |
| T-AVAIL-01-4 | Empty pattern refused; hours range |
| T-AVAIL-01-5 | Weekday numbers match between server and app on pinned dates |
| T-AVAIL-01-6 | Save replaces the whole pattern (re-query) |
| T-AVAIL-01-7 | AI caller refused; second account refused |

## Keep a pulse on

- Patterns that change by week ("every other Friday") are not built. Time off covers the odd week for now.
