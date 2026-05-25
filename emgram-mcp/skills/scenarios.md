# Skill: Scenarios — Clone, Modify, Compare

## When to use
- User wants to "try a variant", "test a different version", "compare two approaches"
- User wants to A/B test a change to an existing map without touching the live version
- Use scenario tools when working with variations of an EXISTING map
- Use standard map tools (create_journey_map) for brand new maps

---

## 🚨 HARD RULES

1. **Always call `list_scenarios` first** — never call `clone_scenario` without knowing the source map ID
2. **Always `publish_map` on the clone before `compare_scenarios`** — unpublished maps have no `ai_summary` and incomplete scorecard data
3. **Never declare a winner when one side has `null` metrics** — surface both values and let the operator decide

---

## Full Loop: Clone → Modify → Compare

```
list_scenarios    { journey_architecture_id }           ← find source map ID
clone_scenario    { journey_architecture_id, source_map_id, title: "Variant: [what changed]" }
fill_cells        { journey_map_id: new_id, cell_updates: [...] }  ← make the ONE targeted change
publish_map       { journey_map_id: new_id }            ← REQUIRED before compare
compare_scenarios { journey_architecture_id, map_a_id: original_id, map_b_id: new_id }
```

---

## Tool Reference

### list_scenarios
```json
{ "journey_architecture_id": 16 }
```
Returns: `[{ id, title, owner_name, created_at, updated_at, cloned_from_map_id }]`
- Returns `[]` when architecture has no maps — not an error
- Returns both draft and active maps, ordered by `updated_at DESC`

### clone_scenario
```json
{
  "journey_architecture_id": 16,
  "source_map_id": 126,
  "title": "Variant: Shorter followup wait time"
}
```
Returns: new map `{ id, title, cloned_from_map_id, ... }`
- All stages, lenses, cells copied; `cloned_from_map_id` set on new map
- `is_locked` reset to `false` on all cells — clone starts fully editable
- `journey_link` records and AI conversation history are NOT cloned — scenario starts clean
- Journey settings fields reset to null on the new map — fill them if needed
- Always pass a descriptive `title` — backend fallback is generic string only

### compare_scenarios
```json
{
  "journey_architecture_id": 16,
  "map_a_id": 126,
  "map_b_id": 134
}
```
Returns:
```json
{
  "map_a": { "id", "title", "journey_health", "revenue_at_risk", "critical_stages",
             "stage_breakdown": [{ "stage_key", "stage_label", "stage_health" }] },
  "map_b": { ... }
}
```
- Returns `400` if `map_a_id == map_b_id`
- Returns `null` for metrics if map is unpublished — never infer from nulls

---

## Communicating Compare Results

Lead with the **biggest delta**, not alphabetical order:
- "Map B reduces critical stages from 3 → 1 and improves journey health from 62% → 81%"
- Then list per-stage changes
- For null metrics on either side: "Map B hasn't been published yet — no scorecard available to compare"

---

## What clone_scenario Does NOT Copy

- `journey_link` records (exception/sub-journey wiring)
- AI conversation history
- Journey settings metadata (primary_actor, journey_scope, etc.)

If these matter for the variant, re-fill them via `fill_cells` / HTTP PATCH after cloning.
