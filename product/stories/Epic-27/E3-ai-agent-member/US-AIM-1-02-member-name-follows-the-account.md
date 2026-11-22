# US-AIM-1-02 — A member's name follows its account

**Epic:** AIM-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** US-AIM-1-00 (inventory item 5)

## Description

A plan member has its own stored name. When the linked account is renamed, the plan keeps the
old name, so the roster and the account disagree. The request offered two fixes: read the name
from the account when showing it, or copy the new name into every member row on rename.

**This story reads at display time.** It follows the product's own rule (reference, do not
copy), and copying would hit a wall: `planner_agent` has a unique index on (plan, name), so a
rename could fail on one plan and succeed on another, leaving the roster half-updated (finding F-10).

## User story

**As** the owner, **I want** a renamed account to show its new name on every plan, **so that**
the roster is never stale.

## Acceptance criteria

```gherkin
Scenario: a linked member is renamed
  Given member 155 is linked to user 34, named "Eli Claude"
  When user 34 is renamed "Eli (AI)"
  Then every plan that has a member linked to user 34 shows "Eli (AI)"
  And no planner_agent row was changed

Scenario: a member with no login
  Given a member with user_id 0
  Then it shows its own stored name, as today

Scenario: past activity
  Given activity recorded while the name was "Eli Claude"
  When the account is renamed
  Then those log entries still read "Eli Claude"

Scenario: two members would show the same name
  Given two members of one plan whose display names are now identical
  Then each shows its display name followed by its stored name in brackets, so they can be told apart

Scenario: the linked account is switched off or deleted
  Then the member shows the last known name and stays in history
```

- One function returns a member's display name (suggested `planner/agent_display_name`). Every
  list that shows members calls it: roster, plan screens, `plan_get`, reports, the activity feed's "current" name.
- Lists use one query for all needed users (`id in $ids`), never one query per member.

## Counter-measures

| Risk | Prevention |
|---|---|
| The log shows today's name for yesterday's work | **If** the log stores only an id (story 00 finds out), add a name snapshot at write time on a side table; never rewrite old rows |
| One screen is missed and still shows the stored name | Search the frontend and the tools for every read of `planner_agent.name`; list each in Test Results |
| The roster endpoint does not join the user table and silently returns the old name | Add the display name on the server in the list endpoint; a live reload test proves it (the STAGE-1 side-table lesson) |
| A user-name lookup with a variable key returns null | Pre-seed the map or check null explicitly; never trust `\|get` defaults with a variable key |
| An empty key returns the whole map | Prefix lookup keys (`"u:" ~ id`) so a key is never empty |
| Name uniqueness in a plan is now checked on the wrong name | Uniqueness stays on the stored name (the index); the collision scenario above covers display |
| A deleted user breaks the roster | Fall back to the stored name when the user row is missing |

## Governance

- **Events:** none for a read. If a name snapshot is added to log writes, its failure must not block the status change; it records a warning event instead.
- **Friendly message:** none new.

## Tests (write first)

| ID | Test |
|---|---|
| T-AIM-02-1 | Rename user 34: plans 146 and 147 both show the new name; `planner_agent` rows unchanged |
| T-AIM-02-2 | Member with no login shows stored name |
| T-AIM-02-3 | Log entries from before the rename keep the old name |
| T-AIM-02-4 | Two identical display names are told apart |
| T-AIM-02-5 | Missing user row falls back to the stored name, no error |
| T-AIM-02-6 | UI: full reload shows the new name on roster, plan and execution screens |
