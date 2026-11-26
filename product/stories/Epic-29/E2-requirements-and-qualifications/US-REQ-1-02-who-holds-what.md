# US-REQ-1-02 — Who holds what

**Epic:** REQ-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** ✅ Built (2026-11-26)
**Depends on:** story 01

## Description

A person's holdings are recorded on their lasting profile (`agent_profile`), not on a plan. A
plan lasts a week; what a person is qualified to do lasts longer than that. Recording it per plan
would mean re-entering it every period, and a repeat would copy stale answers.

Some holdings run out. A holding can carry a "held until" date. After that date it stops
counting, without anyone having to remember to remove it.

An AI member can hold requirements too (some work is suited to an AI and some is not). But an AI
may never record a holding, for itself or anyone else. That is the same rule as "it can never
give itself more power".

## User story

**As** an admin, **I want** to record what each person holds and until when,
**so that** the system knows who can do which work without me remembering it.

## Acceptance criteria

```gherkin
Scenario: record a holding
  When I record that Ana holds "Forklift"
  Then Ana's profile shows it

Scenario: with an end date
  When I record that Ana holds "Forklift" until 2027-03-31
  Then on 2027-03-31 she holds it, and on 2027-04-01 she does not

Scenario: running out soon
  Given a holding ends within 30 days
  Then it is shown as "ends soon" on the person and in the admin's list

Scenario: record it twice
  Then the second save updates the end date and is not an error

Scenario: remove a holding
  Then the person no longer holds it, and who removed it and when is recorded

Scenario: an archived requirement
  Then it cannot be newly recorded, and existing holdings of it still show

Scenario: see it from the other side
  When I open a requirement
  Then I see everyone who holds it, and who holds it only until a date

Scenario: a person with no profile
  Given someone was added to a plan by hand and has no profile
  Then I am told they need a profile first, with a link to make one

Scenario: an AI tries to record a holding
  Then it is refused, and the refusal is recorded

Scenario: a person is switched off or removed
  Then their holdings stay as history and stop counting

Scenario: another account
  Then it cannot see or change my people's holdings
```

## Counter-measures

| Risk | Prevention |
|---|---|
| An end date is compared to "today" in the wrong time zone | Holdings are compared to the **date of the work** (a plain plan date), never to a clock time |
| "No end date" stored as an empty value reads as "ended" | An empty date means no end. `0`, `""` and null all compare equal to null in this engine, so the rule is written as "ends only when a real date is present", with a test for each empty form |
| An optional date input that is left out does not exist at all | Declare it as text, default `""`, and convert (the CLAUDE.md date rule) |
| A holding is recorded for a person in another account | The profile's account is resolved (through the login for a person, its own column for an AI) and checked against the caller's |
| An AI records a holding through a tool | Admin endpoints only, each calling `copilot/assert_person_only`. No tool is built |
| A holding lapses and nobody notices until work cannot be assigned | "Ends soon" on the admin's list and one Health-page line per person; MATCH-1 marks affected work for review |
| Removing a holding leaves no trace of who decided | Every add, change and remove is an event with the actor |
| A patch on many rows touches only the first | Each holding is written by id |

## Governance

- **Errors (suggested):** `E-REQ-010` person has no profile · `E-REQ-011` requirement archived · `E-REQ-012` end date is not a date · `E-REQ-013` a person must do this (AI refused).
- **Events:** `holding.recorded`, `.changed`, `.removed`, each with profile, requirement, end date and actor.
- **Delete behaviour:** deleting a profile removes its holdings in the same transaction (query, loop by id). Switching a person off keeps them.

## Tests (write first)

| ID | Test |
|---|---|
| T-REQ-02-1 | Record, change the date, remove |
| T-REQ-02-2 | The last day counts; the day after does not |
| T-REQ-02-3 | Empty date in each form (`""`, missing) means no end |
| T-REQ-02-4 | "Ends soon" at 30 days |
| T-REQ-02-5 | Archived requirement refused for a new holding |
| T-REQ-02-6 | AI caller refused and logged |
| T-REQ-02-7 | Other account's profile refused |
| T-REQ-02-8 | Profile delete removes every holding (re-query zero) |

## Keep a pulse on

- "Held from" (a start date) is not built. Add it only if someone needs to record a future holding.
