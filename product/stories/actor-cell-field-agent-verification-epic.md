# Epic: Actor Cell Field Agent Verification — Read-Back & Confirm

**Date:** 2026-04-22
**Related:** `product/bug-fixes/ai-agent-actor-cell-fields-not-populating.md`
**Related:** `product/wholistic/actor-cell-fields-agent-context.md` (Gap 2)

---

## Goal

Even after the context injection key-hint fix (`actor-cell-field-context-fix-epic.md`), the
agent has no way to **verify what it actually wrote**. After calling `update_actor_cell_fields`
the agent reads `applied: true` in the tool response and declares success — but it cannot
cross-check the written values because `get_map_state` and `get_slice` do not return
`actor_fields` or `actor_type` on cells.

This epic adds `actor_type` and `actor_fields` to both read tools so the agent can:
1. Detect which rows are actor-typed before choosing a write tool
2. Read back what was actually stored after a write and confirm the correct keys landed

---

## Stories

### US-ACFV-01 — Add `actor_type` and `actor_fields` to `get_map_state` cell objects

**File:** `tools/2_get_map_state.xs`

**Current cell shape returned:**
```json
{ id, stage_id, stage_key, lens_id, lens_key, content, status, is_locked, change_source }
```

**Change:** Inside the `foreach ($raw_cells)` loop (line 114), the `$l_rec` lens record is
already in scope. Add `actor_type` from `$l_rec.actor_type` and `actor_fields` from
`$c.actor_fields` to the `array.push $cells` value object.

Updated cell shape:
```json
{
  id, stage_id, stage_key, lens_id, lens_key,
  actor_type,    ← from parent lens ($l_rec.actor_type), null for non-actor rows
  actor_fields,  ← from cell record ($c.actor_fields), null when not yet populated
  content, status, is_locked, change_source
}
```

**Update the `instructions` block** to reflect the new shape:
- Replace the response shape comment to include `actor_type` and `actor_fields`
- Add a note: "actor_type is null for non-templated rows. actor_fields is null when the cell
  has not been filled via update_actor_cell_fields."

**Update the `response` shape comment** at line 16 of the instructions block to document
the expanded cell object.

**Acceptance Criteria:**
- `get_map_state` cells include `actor_type` (string or null) and `actor_fields` (object or null)
- `actor_type` is correctly sourced from the parent lens record, not the cell record
- Non-actor lens rows emit `actor_type: null` and `actor_fields: null`
- Cells with populated fields return the full `actor_fields` JSON object
- `summary` block is unchanged
- Existing callers that only read `content`, `status`, `is_locked` are unaffected (additive change)

---

### US-ACFV-02 — Add `actor_type` and `actor_fields` to `get_slice` cell objects

**File:** `tools/8_get_slice.xs`

**Three slice modes, each needs updating:**

**Cell mode** (stage + lens both provided, line ~131):
```
cell: { id, content, status, is_locked, change_source }
```
→ Add `actor_type: $lens.actor_type` and `actor_fields: $cell.actor_fields`

**Column mode** (stage only, line ~179 `array.push $cells`):
```
{ lens_key, lens_label, content, status, is_locked, change_source }
```
→ The column loop already has `$l_rec` in scope. Add `actor_type: $l_rec.actor_type`
  and `actor_fields: $c.actor_fields`

**Row mode** (lens only, line ~258 `array.push $cells`):
```
{ stage_key, stage_label, content, status, is_locked, change_source }
```
→ Row mode cells all share the same lens. Add `actor_type: $lens.actor_type`
  (the `$lens` var is already in scope at the row mode block) and
  `actor_fields: $c.actor_fields`

**Update the `instructions` block** response shape descriptions for all three modes to
document the added fields.

**Acceptance Criteria:**
- All three slice modes include `actor_type` and `actor_fields` on cell objects
- Cell mode: `actor_type` sourced from the already-resolved `$lens` record
- Column mode: `actor_type` sourced from `$l_rec` in the column loop's lens map lookup
- Row mode: `actor_type` sourced from the outer `$lens` var (same for all cells in the row)
- `actor_fields` is always `$c.actor_fields` from the raw DB cell record
- Additive change — no existing fields removed or renamed
- Tool instructions response shape comments updated to reflect new fields

---

### US-ACFV-03 — Update agent system prompt with post-write verification rule

**File:** `agents/2_journey_map_assistant.xs`

**Change:** Add a verification step to the `## Structured actor field rules` section.
After the existing rules about when to call `update_actor_cell_fields`, add:

```
## Post-write verification
After calling update_actor_cell_fields:
- Check the tool response: if applied == false, report skip_reason to the user
  (locked / confirmed / not_found) and do not claim success.
- If applied == true, call get_slice with the same stage_key + lens_key to read back
  actor_fields from the database. Confirm that the keys you wrote are present with
  non-null values before telling the user the fields were saved.
- If any key you wrote is missing or null in the read-back, report it and retry
  with the correct key from the Actor field key reference table.
```

**Acceptance Criteria:**
- Agent system prompt includes the post-write verification rule
- Rule is placed inside or immediately after `## Structured actor field rules`
- Rule references `applied`, `skip_reason`, and the `get_slice` read-back step
- Rule references the `Actor field key reference` table for retry guidance

---

## Implementation Notes

- US-ACFV-01 and US-ACFV-02 are purely additive — no DB schema change, no new queries.
  The lens record is already fetched in both tools; `actor_type` is already a field on it.
  The cell record already includes `actor_fields` from the DB query.
- US-ACFV-03 only adds text to the system prompt — no code changes.
- Implement in order: 01 → 02 → 03. 03 depends on 01/02 being live so the agent can
  actually perform the get_slice read-back.
- The verification call adds one extra read per write. This is acceptable given the
  correctness benefit; it can be revisited if latency becomes a concern.
