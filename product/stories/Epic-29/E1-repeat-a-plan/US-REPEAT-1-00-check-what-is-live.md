# US-REPEAT-1-00 — Check what is live before building

**Epic:** REPEAT-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** nothing. **Read-only: this story writes nothing to the real account.**

## Description

The epic was written from the repo files. Live Xano can differ (it has before: reserved table
ids were already in use). A repeat copies everything that hangs off a plan, so a table that
exists live and is missing from this list is work that silently does not carry over.

This story produces three answers and writes them into `epic.md` section 2.

## User story

**As** the builder, **I want** to know exactly what a plan holds today, **so that** a repeat
copies all of it or says what it left out.

## Acceptance criteria

```gherkin
Scenario: live matches the repo
  When each table and endpoint in epic.md section 2 is fetched live
  Then every difference is listed, and the founder is told before anything is built

Scenario: everything that hangs off a plan is listed
  When every table is searched for a reference to a plan, a day, a person, a slot, a job or a step
  Then each one is marked "copied", "not copied (history)" or "not copied (one-off)", with the reason

Scenario: one large write is measured
  Given a scratch plan on the test account
  When 50 jobs with 10 steps each are created in one transaction
  Then the time taken and whether it finished are recorded

Scenario: the frontend is read
  When the planner app's plan list and board screens are read
  Then the story files say where the "Repeat" action and the preview will sit
```

## Counter-measures

| Risk | Prevention |
|---|---|
| A newer table (added after this epic was written) hangs off a plan and is missed | Search by reference, not from memory: every table with a `workspace_id`, `timeline_id`, `planner_task_id`, `work_item_id` or `work_task_id` column |
| The measurement leaves junk on the test account | The scratch plan is deleted at the end; the count of plans before and after is the same |
| One transaction cannot hold a week | Story 02 then builds in stages under a `building` state, hidden until `ready` (already designed in the epic's table) |

## Governance

- No errors, no events: nothing is written to real data.
- The answers are recorded in `epic.md` section 2 and in this epic's Test Results.

## Tests (write first)

| ID | Test |
|---|---|
| T-REPEAT-00-1 | Every table in section 2 fetched live and compared |
| T-REPEAT-00-2 | The "hangs off a plan" list has no table marked unknown |
| T-REPEAT-00-3 | Large-write timing recorded for 100, 250 and 500 rows |

## Keep a pulse on

- **Assumed:** the planner screens live in `webapp/protype-2/src/planner/`. CLAUDE.md also names `webapp/planningFrontendv2`. Find out which one is in use.
