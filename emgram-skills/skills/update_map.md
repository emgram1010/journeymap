# Skill: Update a Journey Map

## When to use
User wants to change content, add stages/lenses, fill gaps, or modify actor fields in an existing map.

---

## Rule: Always Read Before Write

```
get_map first → understand current state → then make targeted changes
```

Never call fill_cells or scaffold_map cold.

---

## Flow: Update Cell Content

```
1. get_map { journey_map_id }
2. Identify target: stage_key + lens_key
3. fill_cells {
     journey_map_id,
     cell_updates: [{ stage_key: "s1", lens_key: "lens-2", content?: "...", actor_fields?: {} }]
   }
4. Confirm changes with user
5. publish_map if user wants changes live
```

`fill_cells` parameter is `cell_updates` (not `cells`). Returns `{ journey_map_id, written, skipped }`.
Skipped = cell not found (bad stage_key or lens_key) — verify keys from `get_map`.

---

## Flow: Add a New Stage

```
1. get_map → understand existing stage structure (keys, order)
2. scaffold_map {
     journey_map_id,
     stage_operations: [{ action: "add", label: "Case Study Followup" }]
   }
3. scaffold_map rename to set stage_goal + primary_actor_lens
4. fill_cells → populate the new stage cells
5. publish_map (with confirmation)
```

`scaffold_map` appends stages at the end.

---

## Flow: Set Stage Metadata (stage_goal + primary_actor_lens)

```json
{
  "journey_map_id": 126,
  "stage_operations": [
    {
      "action": "rename",
      "key": "s2",
      "label": "Clarify Process Scope",
      "stage_goal": "Process scope record complete: name, frequency, volume, owner, and pain all answered",
      "primary_actor_lens": "lens-3"
    }
  ]
}
```

- `stage_goal` — exit condition (what must be true when this stage is done)
- `primary_actor_lens` — key of the lens that owns execution at this stage

---

## Flow: Add a New Lens to Existing Stages

```
1. get_map → check which lenses already exist (lenses[].key)
2. scaffold_map {
     journey_map_id,
     lens_operations: [{ action: "add", label: "Handoff", actor_type: "handoff" }]
   }
   → creates empty cells for this lens across ALL existing stages automatically
3. fill_cells → populate handoff actor_fields per stage
```

Lens key is auto-assigned as `lens-{N}`.

---

## Status Rules

| Status | Meaning | Can AI overwrite? |
|---|---|---|
| `open` | Never filled (default) | Yes |
| `draft` | AI-written via fill_cells | Yes |
| `confirmed` | User-reviewed and approved | **NO — never** |
| `disabled` | Intentionally off | No |

`fill_cells` always writes `status: "draft"` regardless of what you pass.
Always check cell status in `get_map` output before writing to sensitive cells.

---

## Completeness Checklist — Run BEFORE declaring a map "done"

1. **Journey Settings** — verify non-empty: `primary_actor`, `journey_scope`, `start_point`, `end_point`, `duration`, `success_metrics`, `key_stakeholders`, `dependencies`, `pain_points_summary`, `opportunities`
2. **Lens Descriptions** — each lens should have `description` filled
3. **Cell Coverage** — every named stage × every lens must have `content` (even "N/A — [actor] does not act here")
4. **actor_fields Values** — having keys ≠ having values; spot-check actual values are present

---

## What NOT to Do

- Don't scaffold new stages without knowing existing stage keys (you'll break ordering)
- Don't fill handoff cells without running intake first
- Don't publish without user confirmation unless explicitly told "just do it"
- Don't declare a map complete without running the completeness checklist above
