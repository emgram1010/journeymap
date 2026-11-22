# US-SAFE-1-02 — One rule for every tool that writes a cell

**Epic:** SAFE-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** US-SAFE-1-01

## Description

Several tools write cells: `update_cell`, `fill_cells`, `batch_update`, and possibly
`build_journey_map`. Each holds its own copy of "what do I keep, what do I overwrite".
`fill_cells` happens to be safer today (a key left out of a JSON list is a real null), but that
is luck, not design, and it also covers `actor_fields`. If the rule is fixed in one tool only,
the next tool that copies the old line brings the bug back.

## User story

**As** the owner, **I want** every AI tool that writes a cell to follow the same keep-or-clear
rule, **so that** fixing it once fixes it everywhere and it cannot come back.

## Acceptance criteria

```gherkin
Scenario: one shared rule
  Given a new function (suggested name cells/merge_patch)
  When it is given the stored cell and the fields that were sent
  Then it returns the final value of every field and the list of fields that changed
  And it writes nothing itself

Scenario: every cell writer uses it
  When I search the tools for a direct write to journey_cell
  Then update_cell, fill_cells and batch_update all call the shared function
  And no tool has its own copy of the keep-or-clear rule

Scenario: fill_cells, key left out
  Given a list of three updates where the second has no "content" key
  Then the second cell's text is unchanged and the other two are updated

Scenario: fill_cells, key sent as empty string
  Then that cell's text is cleared

Scenario: fill_cells, mixed list with a locked cell
  Then the locked cell is skipped, the rest are applied, and the response counts both

Scenario: fill_cells respects locked and confirmed cells (live check 2026-11-21)
  Given a locked cell, and a confirmed cell
  When fill_cells includes both in its list
  Then both are skipped with reasons "locked" and "confirmed", exactly like update_cell and batch_update
  And the response lists skipped cells with their reason

Scenario: batch_update with no content key (live check 2026-11-21)
  Given an update in the list with no "content" key
  Then that cell's text is unchanged (today it is wiped to null)

Scenario: actor_fields
  Given a cell with actor_fields
  When an update leaves actor_fields out
  Then actor_fields is unchanged
```

- Inside the loop, "was this key sent?" is `($upd|has:"content")`, captured on the loop item in
  a first pass and branched on in a second pass (the only loop shape that is reliable).
- `actor_fields` is a JSON column. `db.patch` **merges** JSON. Decide per call: merge (one patch)
  or replace (patch to null, then patch the value). The story must say which, and test it.

## Counter-measures

| Risk | Prevention |
|---|---|
| A fourth cell-writing tool is missed | Step one is a search of `ai/tool/*.xs` and `apis/journey_map/*.xs` for writes to `journey_cell`; list every hit in Test Results |
| The app's own save endpoints behave differently from the tools | Out of scope to change, but list them and note whether they share the bug |
| A branch inside the loop reads a variable updated earlier in the same pass and silently loses its writes | Branch only on the loop item |
| The shared function is called with an input left out and inherits the caller's input of the same name | Pass every input explicitly |
| A bulk call half-applies | Writes for one call go in one `db.transaction`; the response reports applied and skipped counts that are re-checked by a query in the test |

## Governance

- **Events:** one `cells.bulk_updated` event per call with applied count, skipped count and reasons.
- **Friendly message** when every row was skipped: say why per row (locked, confirmed, not found, nothing to change).

## Tests (write first)

| ID | Test |
|---|---|
| T-SAFE-02-1 | Shared function: every combination of omitted / null / empty / value, for text and number |
| T-SAFE-02-2 | `fill_cells` with a left-out key keeps the stored value |
| T-SAFE-02-3 | `fill_cells` with an empty string clears |
| T-SAFE-02-4 | `batch_update` same two cases |
| T-SAFE-02-5 | Mixed list with locked and confirmed cells: counts match a re-query |
| T-SAFE-02-6 | `actor_fields` kept when left out; replaced or merged as the story decides |
