# US-SCALE-1-01 — Jobs carry their items

**Epic:** SCALE-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** US-SCALE-1-00, DEMAND-1 story 01

## Description

A job can already hold order lines (table `work_item_line`, set through `PUT …/lines`). But the
tools an AI or the webhook use to create a job, `plan_add_job` and the new
`plan_add_on_demand_job`, have no way to send them. So a job made from an order starts with no
items, the estimate has nothing to scale, and someone has to open the job and type the lines.

This story lets the tools pass an item list, and stores it through the **same rule** the lines
endpoint already uses.

## User story

**As** the owner, **I want** a job made from an order to list its items and quantities, **so
that** the team sees what they are handling and the estimate can use it.

## Acceptance criteria

```gherkin
Scenario: add a job with items
  When plan_add_job is called with items [{item_key: "chair-adult", quantity: 14}, {item_key: "table-6ft", quantity: 2}]
  Then the job is created with two lines
  And the response lists the lines it stored

Scenario: no items
  When plan_add_job is called with no items
  Then the job is created exactly as today

Scenario: an item the map does not list
  Given "tent-20x20" is not in the pinned version's Items row
  Then the job is still created
  And that item is returned under "not_on_map" and flagged "no time set" on the job

Scenario: an item key that does not exist at all
  Then the job is still created, and the key is returned under "unknown_items"

Scenario: the same item twice
  Then the quantities are added into one line

Scenario: a bad quantity
  When a quantity is 0, negative, a decimal or above 9999
  Then the whole call is refused before anything is written, naming the item

Scenario: the job and its lines are one write
  Given the lines fail to save
  Then the job is not created either

Scenario: it shows on the card
  Then the job's card in Plan and Execution lists its items and quantities

Scenario: lines after work has started
  Then they cannot be changed (EST-1's existing rule)
```

- Both `plan_add_job` and `plan_add_on_demand_job` gain an optional `items` list. The webhook
  fills it from the order lines.
- Items arrive by key. The key-to-catalog lookup is done once, in one function.
- **Assumed:** the card change in Plan and Execution. The frontend was not read. EST-1 already
  has a minimal lines editor; reuse its display.

## Counter-measures

| Risk | Prevention |
|---|---|
| A second copy of the lines rules (range, duplicates, item must be active) | Move the checks behind `PUT …/lines` into one function; the endpoint and the tools both call it. Compare the endpoint's behaviour before and after |
| An unknown item silently disappears | Never dropped quietly: it is returned by name and stored as a flag the card shows |
| "Create anyway" hides a typo in every order | The Health page counts jobs with unknown or unmapped items, so a pattern is visible |
| The job is created and the lines fail | One `db.transaction`; a write-only helper may run inside it, logging stays outside |
| A quantity left out arrives as 0 and passes | Check 1 to 9999 explicitly; read "was it sent" with `\|has` on the loop item |
| A key lookup with a variable key returns null instead of the default | Check for null explicitly; prefix keys so none is empty |
| An unwrapped filter in an object literal drops the keys after it | Hoist every computed value into a `var` before building the line object |
| The owner's approval sees a different payload than what runs | The `items` list is part of the tool's approval payload, exactly as sent |
| Existing callers break | `items` is optional; a call without it is byte-for-byte today's call (test) |

## Governance

- **Errors:** reuse EST-1's codes for range, duplicate and inactive item (`E-EST-001`,
  `-006`, `-002`). New (suggested): `E-SCALE-001` too many items in one call (max 200).
- **Events:** `work_item.lines_set` with counts: stored, not on map, unknown. A warning event
  when any item was not stored as a timed line.
- **Delete behaviour:** unchanged; lines go with the job (EST-1).

## Tests (write first)

| ID | Test |
|---|---|
| T-SCALE-01-1 | Job with two items stores two lines |
| T-SCALE-01-2 | No items: same result as before (golden) |
| T-SCALE-01-3 | Item not on the map: job created, flag shown |
| T-SCALE-01-4 | Unknown key: job created, key returned |
| T-SCALE-01-5 | Duplicate items merged |
| T-SCALE-01-6 | Bad quantity refuses the whole call; nothing written |
| T-SCALE-01-7 | Forced line failure leaves no job |
| T-SCALE-01-8 | `PUT …/lines` behaves the same as before the refactor |
| T-SCALE-01-9 | UI: the card lists items and quantities |
