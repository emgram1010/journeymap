# US-REQ-1-04 — What a step needs: hard or soft

**Epic:** REQ-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** ✅ Built (2026-11-26)
**Depends on:** story 01 · **Decision:** D-4 (founder), D-11 (builder)

## Description

The person who designs the work knows what it takes. This story lets them say so on the map, at
the level where work is actually done: a **step**, which is one stage of one row.

Each need is marked **hard** or **soft**:

- **Hard:** the work must go to someone who holds it. No one else can be given it.
- **Soft:** it is preferred. Someone who holds it is suggested first; anyone may still be given it.

Setting needs changes the map draft, like any other edit to a step. Nothing takes effect for jobs
until the map is published as a new version (story 05).

## User story

**As** the person designing the work, **I want** to mark what each step needs and whether it is a
must or a preference, **so that** the plan respects it without my being there.

## Acceptance criteria

```gherkin
Scenario: add a hard need
  When I add "Forklift" to a step as hard
  Then the step shows it as a must

Scenario: add a soft need
  When I add "Speaks Spanish" to a step as soft
  Then the step shows it as preferred

Scenario: change hard to soft, or back
  Then the step shows the new setting

Scenario: several needs, or none
  Then both are fine; a step with none behaves exactly as it does today

Scenario: the same need twice
  Then the second add changes its hard/soft setting and is not an error

Scenario: apply to the whole row
  When I choose "apply to every step in this row"
  Then each step in the row gets the need, and I am told how many were changed

Scenario: only steps that are planned work
  Given a row is not marked "does planned work"
  Then needs cannot be set on its steps, and I am told why

Scenario: an archived requirement
  Then it cannot be newly added; where it is already set it shows as archived

Scenario: nothing is live yet
  Then I see "Takes effect for new jobs after you Publish version"

Scenario: a locked step
  Then needs cannot be changed, with the same message other edits get

Scenario: clone a map
  Then the copy has the same needs

Scenario: delete a step, a row, a stage or a map
  Then its needs go with it

Scenario: too many
  When a step already has 10 needs
  Then the next one is refused with the limit in the message

Scenario: another account
  Then it cannot see or change needs on my map
```

## Counter-measures

| Risk | Prevention |
|---|---|
| Needs set in two places (row and step) disagree | One place only: the step. "Whole row" is a bulk write to steps, not a second store |
| A bulk write changes only the first step | Query the row's steps, loop by id, in a transaction; the count returned is re-queried |
| The map screen never shows needs because the cell read does not include the side table | A dedicated read for a map's needs, merged into the frontend state (AUTH-1 lesson) |
| A need is added by an AI while filling the map | Allowed as a draft edit through the tool gate, like other cell edits; it has no effect until a person publishes. AI callers must reuse an existing requirement, never create one in passing |
| A cascade delete leaves needs behind | Added to the existing map, stage and row delete cascades; the integrity audit counts orphans |
| "Hard" set carelessly makes work impossible to assign | The step shows how many active people hold the need **right now**; zero shows a plain warning. It is a warning, not a block: the designer may be setting up before the people are recorded |
| The words soft and hard drift from the reserved time-window field | Same meaning everywhere: hard refuses, soft warns |
| Readiness checks start failing published-ready maps | Needs are not part of the readiness gate in this epic |

## Governance

- **Errors (suggested):** `E-REQ-030` requirement archived · `E-REQ-031` step is not planned work · `E-REQ-032` step has 10 needs · `E-REQ-033` step is locked.
- **Events:** `step.need_added`, `.need_changed`, `.need_removed` (map, stage key, row key, requirement, hard or soft, actor).
- **Delete behaviour:** needs are deleted with their step.

## Tests (write first)

| ID | Test |
|---|---|
| T-REQ-04-1 | Add hard, add soft, switch, remove |
| T-REQ-04-2 | Same need twice updates, no duplicate |
| T-REQ-04-3 | Whole row: every step changed, count correct |
| T-REQ-04-4 | Row not marked planned work refused |
| T-REQ-04-5 | Archived requirement refused; limit of 10 |
| T-REQ-04-6 | Locked step refused |
| T-REQ-04-7 | Clone copies needs |
| T-REQ-04-8 | Deleting a step, row, stage, map leaves no orphan |
| T-REQ-04-9 | "People who hold this now" count, including zero |
| T-REQ-04-10 | Second account refused |

## Keep a pulse on

- **A need that depends on the job, not the step.** Example pattern: a step needs something only when the order contains a certain item. Not built. The likely home is the item catalog (an item carries a need), read alongside the step's needs. Raise it when a real case appears.
- A need for a whole job ("this customer only wants Ana") is a preference about a person, not a requirement. Different feature.
