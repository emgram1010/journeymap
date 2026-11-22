# US-SAFE-1-01 — A field that was not sent is kept

**Epic:** SAFE-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built

## Description

`update_cell` is the tool an AI uses to write one cell. Its instructions say "omit content to
update only time fields". It does the opposite: an omitted `content` arrives as `""`, the code
writes `$input.content ?? $cell.content`, and `??` keeps `""`. The text is replaced by nothing,
and the tool reports `applied: true`.

The same line shape is used for `time_duration_value`, `planned_duration`, `actual_duration`
and `time_duration_unit`. An omitted decimal arrives as `0`. So a **text-only** update very
likely sets every time on the cell to `0` and the unit to `""` (finding F-1). The founder only
reported the first direction; the second would quietly break estimates and leakage math.

## User story

**As** the owner, **I want** a cell to keep everything an update did not mention, **so that**
map content and times are never lost by accident.

## Acceptance criteria

```gherkin
Scenario: times-only update keeps the text
  Given a cell with text "Load the truck" and no times
  When update_cell is called with only time_duration_value 20 and time_duration_unit "minutes"
  Then the text is still "Load the truck"
  And the times are 20 minutes

Scenario: text-only update keeps the times
  Given a cell with text "Load the truck", 20 minutes, planned 20, actual 25
  When update_cell is called with only content "Load and strap the truck"
  Then the text is the new text
  And all four time fields are unchanged

Scenario: clearing the text on purpose
  Given a cell with text
  When update_cell is called with content set to an empty string
  Then the text is cleared
  And the response says which fields changed

Scenario: content sent as null
  When update_cell is called with content null
  Then the text is kept (null means "nothing to say", not "clear")

Scenario: a time sent as zero on purpose
  When update_cell is called with planned_duration 0
  Then planned_duration becomes 0 (zero is a real value when it is sent)

Scenario: nothing to change
  When update_cell is called with no content and no time fields
  Then nothing is written, applied is false and skip_reason is "nothing_to_change"

Scenario: locked or confirmed cell
  Then the update is skipped exactly as today
```

- The response gains `fields_changed` (a list of field names). Existing response fields stay.
- "Was it sent?" is read with `$raw_input|get:"field":"__absent__"`, never with `$input` alone.
- The tool's `instructions` text is corrected to state the rule: left out = keep, `""` = clear.

## Counter-measures

| Risk | Prevention |
|---|---|
| The fix is tested only in the direction the founder saw | Tests cover both directions and all five fields |
| `$raw_input` behaves differently inside a tool than in an endpoint | Prove it with a scratch tool first (STAGE-1 did this once already); delete the scratch after |
| A piped `\|get` or `\|has` inside a longer `&&` swallows the rest of the line | Wrap each piped call in its own parentheses, or hoist to a `var` |
| The patch data object drops keys after an unwrapped `?:` | Compute each final value into its own `var` before the `db.patch` |
| An AI that relied on "empty string keeps the text" starts clearing cells | Not possible today: empty string already clears. Note the rule in the tool text |
| Text already wiped stays unnoticed | A **report-only** function lists cells with empty text, a non-zero time and `change_source = "ai"`, grouped by map. It fixes nothing. Show the list to the founder |
| Live source differs from the local file | `getTool` first; diff against `ai/tool/update_cell.xs`; stop and ask if they differ |

## Governance

- **Friendly messages:** `nothing_to_change` skip reason; no new error is thrown for a normal call.
- **Events:** one `cell.updated` success event with map id, cell id and `fields_changed`
  (no cell text in the event). A failed write records a failure event before the error is passed on.
- **Rollback:** the previous tool source is saved in the epic before the push.

## Tests (write first)

| ID | Test |
|---|---|
| T-SAFE-01-1 | Times-only keeps text |
| T-SAFE-01-2 | Text-only keeps all four time fields and the unit |
| T-SAFE-01-3 | Empty string clears the text |
| T-SAFE-01-4 | Null keeps the text |
| T-SAFE-01-5 | A sent zero is stored as zero |
| T-SAFE-01-6 | Empty call writes nothing |
| T-SAFE-01-7 | Locked and confirmed cells are skipped, row unchanged (re-query to prove it) |

Run through `runWorkspaceFunction` or `debugTool` on a clone. Re-query the row after each case;
do not trust the tool's own response.
