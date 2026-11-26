# US-REQ-1-00 — Check what is live, and settle the role question

**Epic:** REQ-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** ✅ Done (2026-11-26)
**Depends on:** nothing. **Read-only.**

## Description

Three things must be known before a table is created.

1. **Does live match the repo** for the tables this epic sits beside?
2. **How many people on plans cannot be tied to a lasting profile?** A person with a login can be
   joined through that login. An AI profile with no login, or a person added to a plan by hand
   with no login, cannot. Those people can hold nothing, so once matching is on they could take
   no work that has a hard need. The founder should see that number first.
3. **What happens to roles?** The PRD says assignment will later be "suggested by role" (PL-5,
   SCHED-1 story 04, ROLE-1). This folder replaces that with needs and holdings. That is a change
   to a written plan and needs a line in PRD §10. The PRD is not edited without asking.

## User story

**As** the founder, **I want** to know what matching would break and what it replaces before it
is built, **so that** I am not surprised on the day it is switched on.

## Acceptance criteria

```gherkin
Scenario: live matches the repo
  When tables 9, 112, 116, 129, 130, 135 and 172 and endpoint 201 are fetched live
  Then every difference is listed and the founder is told before anything is built

Scenario: people who cannot be linked
  When every person on every non-archived plan is checked
  Then the result gives three counts: linked through a login, linkable by an exact profile name, not linkable
  And the not-linkable people are listed by plan

Scenario: the role note
  Then a short PRD §10 entry is drafted in this story file for the founder to approve
  And the PRD, ROLE-1 and SCHED-1 files are not edited until the founder says yes

Scenario: the switch
  Then the story records where the on/off switch for matching will live
  And confirms it does not require changing the feature-flag table's fixed list
```

## Counter-measures

| Risk | Prevention |
|---|---|
| The link count is run on the wrong accounts | Run per account and report per account; never across tenants in one number |
| Linking by name ties two different people together | Name matching is only **reported** here. Story 03 never links by name without a person confirming |
| The role decision is made by silence | It is listed as D-12 in the folder README and asked directly |

## Governance

- No errors, no events: nothing is written.
- **Draft PRD note (not yet in the PRD):** "Assignment is matched on needs and holdings (REQ-1,
  AVAIL-1, MATCH-1), not on a role. ROLE-1 stays deferred. MATCH-1 replaces SCHED-1 story 04. A
  role may later be added as a requirement."

## Tests (write first)

| ID | Test |
|---|---|
| T-REQ-00-1 | Live vs repo comparison recorded |
| T-REQ-00-2 | Link counts add up to the number of people checked |
| T-REQ-00-3 | No row changed (counts before and after) |

## Keep a pulse on

- If "not linkable" is large, story 03's clean-up screen matters more than the rest of this epic.
