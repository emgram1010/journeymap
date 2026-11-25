# US-MATCH-1-01 — The one rule: does this person fit this work on this day?

**Epic:** MATCH-1 · **Size:** M · **Model:** **Opus 5.5** · **Status:** 📋 Not built
**Depends on:** story 00; REQ-1 story 05 (`req/step_needs`); AVAIL-1 story 03 (`avail/person_day`)
**Decisions:** D-3, D-4 (founder), D-9 (builder)

## Description

This is the heart of the folder. One function, `match/check`, takes a person on a plan, a piece
of work and a date, and returns whether the person may be given it, every reason if not, and
every warning if so.

It is deliberately a **pure rule over facts already loaded**: it does not write, and it does not
decide what happens next. The suggest list ranks with it. The assigning endpoints refuse with
it. Publish to live blocks with it. A repeat drops with it. If the rule lived in each of those,
they would disagree, and a hard need that can be got around on one path is not a hard need.

## User story

**As** a planner, **I want** the same answer everywhere about whether a person can take a piece
of work, **so that** what the board suggests, what a save allows and what Publish to live
accepts never contradict each other.

## Acceptance criteria

```gherkin
Scenario: work with no needs, person with nothing recorded
  Then allowed, no warnings

Scenario: a hard need the person holds
  Then allowed

Scenario: a hard need the person does not hold
  Then refused: "Needs Forklift. Ana does not hold it."

Scenario: a hard need that ends before the day of the work
  Given Ana holds Forklift until 31 March and the work is on 2 April
  Then refused: "Ana's Forklift ended 31 March"

Scenario: a hard need that ends on the day of the work
  Then allowed

Scenario: a hard need waived for this job by the owner
  Then allowed, with the note "Forklift waived for this job by <owner>"

Scenario: a soft need the person does not hold
  Then allowed, with the warning "Prefers Speaks Spanish. Ana does not hold it."

Scenario: not available
  Then refused, with AVAIL-1's reason

Scenario: not enough hours left
  Then allowed, with the warning "This takes 2 h. Ana has 1 h 30 min left that day."

Scenario: several things at once
  Then every refusal reason and every warning is returned, refusals first

Scenario: a block of several steps
  Given one slot covers several steps
  Then the needs are the union of the steps' needs; hard wins if a need is hard on any step

Scenario: a free-standing slot not linked to a job
  Then it has no needs; only availability and hours are checked

Scenario: a person with no profile
  Then they hold nothing: refused for any hard need, with "no profile, so nothing is recorded as held"

Scenario: a job on a version published before needs existed
  Then it has no needs

Scenario: a score for ranking
  Then the answer includes: allowed or not, count of soft needs missing, hours left

Scenario: the app agrees with the server
  Then the TypeScript twin returns the same answer and the same words for every golden case
```

## Counter-measures

| Risk | Prevention |
|---|---|
| The rule is re-written in an endpoint "just for this case" | Build guard: only `match/check` may read needs, holdings and availability together; other files call it |
| A loop that branches on a variable updated in the same pass silently drops reasons | First pass builds one row of facts per need (held: yes/no, ends, waived); second pass branches on the row's own fields |
| Membership tested with `contains` on an array (always false, so "does not hold" for everyone) | Holdings loaded into a map with prefixed keys (`"r:" ~ id`), every key pre-seeded; or `in` inside the query |
| A lookup with a variable key ignores its default and returns null | Pre-seed, and treat null as "not held" on purpose, with a test |
| An empty key returns the whole map | Keys are always prefixed |
| "Ends" stored as empty reads as ended | Ends only when a real date is present; each empty form has a test |
| A date compared as a clock time shifts by a day | Plain dates, compared as dates |
| A ternary or a piped filter inside an object literal drops the keys after it | Hoist into a variable, or wrap in its own parentheses |
| A piped call in the middle of a boolean chain swallows the rest | Each piped call in its own parentheses |
| The server and app wording differ, so the same refusal reads two ways | Reasons are built from a code plus fields; both sides render from one shared table of sentences |
| The function is slow when called per slot | It takes pre-loaded facts; a batch wrapper loads a plan's needs, holdings and availability once |
| Test fixtures use `0` as a stand-in date or id | Realistic dates and ids only |

## Governance

- **Errors:** none of its own. Callers use `E-MATCH-010` (hard need not held), `E-MATCH-011` (not available), and warnings `W-MATCH-001` (soft need not held), `W-MATCH-002` (not enough hours).
- **Events:** none per call. The nightly audit runs the golden cases live and records a failure on any mismatch.

## Tests (write first)

| ID | Test |
|---|---|
| T-MATCH-01-1 | Golden cases: every scenario above |
| T-MATCH-01-2 | The last day of a holding counts; the day after does not |
| T-MATCH-01-3 | Waiver makes one need pass and no other |
| T-MATCH-01-4 | Block of steps: union of needs, hard wins |
| T-MATCH-01-5 | No profile; old version; free-standing slot |
| T-MATCH-01-6 | All reasons returned together, refusals first |
| T-MATCH-01-7 | Server and twin agree on answer **and** wording |
| T-MATCH-01-8 | Build guard passes; a planted second copy of the rule fails it |

## Keep a pulse on

- If a business needs "any one of these" (holds A **or** B), the rule today is "all of". Do not bolt it on; it changes the shape of a need.
