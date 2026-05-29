# Skill: Link Map — Wire Cell-to-Map Connections

## When to use
- User wants to connect a cell in one map to another map as an exception, alternate path, or sub-process
- Building out branching process logic (exception handling, anti-journey, sub-agent delegation)
- After building an exception map via clone_scenario — wire it back to the originating cell
- Before publishing the source map when automation snapshot needs to include the link graph

---

## 🚨 HARD RULES

1. **Always call `get_map` first** — never guess a `source_cell_id`
2. **Re-publish the source map after `link_map`** — the link alone does not update the automation snapshot
3. **One cell → one target map** — if the pair already exists, surface the error and ask user whether to update via HTTP API

---

## link_type Reference

| Type | When to use |
|---|---|
| `exception` | Something went wrong at this cell — target map handles recovery/escalation |
| `anti_journey` | Actor did NOT follow the expected flow — target map handles the alternate path |
| `sub_journey` | This cell delegates to a sub-process — target map is a self-contained process invoked here |

---

## Full Flow: Build + Wire an Exception Map

```
list_scenarios    { journey_architecture_id }           ← find the base map
clone_scenario    { source_map_id, title: "Exception: [reason]" }
fill_cells        { journey_map_id: clone_id, ... }     ← fill exception handling logic
publish_map       { journey_map_id: clone_id }          ← compile the exception map first
get_map           { journey_map_id: base_map_id }       ← find source_cell_id from cells[]
link_map          {
  journey_architecture_id,
  source_map_id:   base_map_id,
  source_cell_id:  <id from cells[] — matched by stage_key + lens_key>,
  target_map_id:   clone_id,
  link_type:       "exception",
  label:           "Exception: [reason]"
}
publish_map       { journey_map_id: base_map_id }       ← re-publish to include link in snapshot
```

---

## Finding source_cell_id from get_map

`get_map` returns a `cells[]` array. Each cell has:
```json
{ "id": 55, "stage_key": "s3", "lens_key": "lens-2", "actor_type": "handoff", ... }
```

Match by `stage_key` + `lens_key` to find the right cell. Use `id` as `source_cell_id`.

Example: "Link from the handoff cell in stage s3":
→ find cell where `stage_key == "s3"` AND `lens_key == "handoff"` (or your lens key)
→ use that cell's `id`

---

## link_map Input

```json
{
  "journey_architecture_id": 16,
  "source_map_id": 126,
  "source_cell_id": 55,
  "target_map_id": 134,
  "link_type": "exception",
  "label": "Exception: payment failed"
}
```

Returns: full `journey_link` record `{ id, source_map, source_cell, target_map, link_type, label, created_at }`

---

## Error Cases

| Error | Meaning |
|---|---|
| `(source_cell, target_map)` already exists | Link already created — surface to user, offer HTTP update |
| `source_map_id == target_map_id` | Self-link rejected — must use different maps |
| Either map not in architecture | Both maps must belong to the same `journey_architecture_id` |
| User doesn't own architecture | Returns 403 |

---

## Relationship to Automation Bridge

`link_map` creates `journey_link` records that the snapshot compiler reads at publish time.
An agent that builds and wires exception maps via MCP produces a snapshot n8n can traverse
at runtime without calling Emgram — the full linked-map graph is embedded in the snapshot.
