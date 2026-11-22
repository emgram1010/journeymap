# US-DISC-1-01 — List plans (`plan_list`)

**Epic:** DISC-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** ✅ Built 2026-11-21 (see epic Test Results)

## Description

An AI asked to "add this to the Blooming plan" has no way to turn that name into a plan id. It
either asks the owner or guesses. A list tool removes the lookup. It must show only what the
caller may already see on the plan screen, and it must stay small enough to read in one call.

## User story

**As** an AI working for the owner, **I want** to list the plans in the business, **so that** I
can find one by name instead of asking for its id.

## Acceptance criteria

```gherkin
Scenario: list the plans in this business
  Given a copilot chat about one business with three plans, one archived
  When plan_list is called with no filters
  Then two plans are returned, newest activity first
  And each has id, name, planning window (start and end date), archived flag,
      the maps it accepts (id and title), member count and job count

Scenario: include archived
  When plan_list is called with include_archived true
  Then all three are returned and the archived one is marked

Scenario: find by name
  When plan_list is called with name_contains "bloom"
  Then only plans whose name contains "bloom" are returned, ignoring upper and lower case

Scenario: nothing matches
  Then the result is an empty list and count 0, not an error

Scenario: another account
  Given a plan that belongs to another account
  Then it is never in the list, with or without filters

Scenario: an outside assistant
  Given a call over the connector with no chat
  When no business is named
  Then it is refused with the existing message asking for journey_architecture_id (E-COP-045)

Scenario: a long list
  Given more than 100 plans
  Then the first 100 are returned with truncated true and a hint to use name_contains
```

- Tool input: `name_contains?` (text), `include_archived?` (bool, default off),
  `journey_architecture_id?`, `ticket?`. Same last two as `plan_add_job`.
- Gate call uses `kind: "read"`. No approval, no action row.
- The caller needs the Planner grant, checked with `usr/assert_module_access`, like a person.

## Counter-measures

| Risk | Prevention |
|---|---|
| A second copy of the plan-list query drifts from the screen | Move the query into one shared function used by endpoint 524 and the tool; compare 524's output before and after |
| The tool leaks plans from other businesses in the same account | Filter with `copilot/plan_in_business`, the one rule |
| A count comes back null | Seed every tally key to 0 before counting (`\|get` with a variable key ignores its default) |
| `name_contains` is put inside a `where` with a filter call | Lower-case the search text into a `var` first; if the `where` cannot do a contains match, filter in a loop on the loop item |
| An omitted `include_archived` cannot be told from false | Fine here: both mean "off" |
| The list is too big for a model to read | Cap at 100, return `truncated` |
| Archived plans leak into normal use | Default off; the tool text says to include them only when the owner asks |

## Governance

- **Events:** one tool-log row per call through the gate (who, tool, outcome), as every tool has.
- **Friendly messages:** reuse `E-COP-045` (needs one business) and the module-access refusal.

## Tests (write first)

| ID | Test |
|---|---|
| T-DISC-01-1 | Default list hides archived; counts match the plan screen for plans 146 and 147 |
| T-DISC-01-2 | `include_archived` shows them |
| T-DISC-01-3 | `name_contains` is case-insensitive; no match returns an empty list |
| T-DISC-01-4 | Second account sees nothing of the first |
| T-DISC-01-5 | A plan in another business of the same account is not listed |
| T-DISC-01-6 | Outside call with no business is refused |
| T-DISC-01-7 | Endpoint 524 returns the same output as before the change |
