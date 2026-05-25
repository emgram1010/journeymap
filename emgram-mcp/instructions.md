# Emgram MCP — Agent Instructions

This file is the decision brain for any AI operating Emgram via MCP in a new session.
Read this first. Then orient with `list_maps`. Then act.

---

## Orientation (always do this at session start)

1. Call `list_maps` to understand what already exists for the user
2. If user references a map by name or topic → call `search_maps` first
3. If user references a map by ID → call `get_map` directly
4. Never create a map without checking if one already exists

---

## Decision Tree — What Tool To Use When

### User describes a NEW process
```
create_journey_map (intent: sop | automation | hybrid)
  → scaffold_map (stages + lenses based on intent)
  → fill_cells (content + actor_fields)
  → publish_map
```
If intent = automation → run intake interview BEFORE scaffold (see skills/create_map.md)

### User says "update", "add to", "change", "edit"
```
get_map (load current state)
  → fill_cells (targeted update)
  OR scaffold_map (if adding new stages/lenses)
  → publish_map (if changes should go live)
```

### User asks "do we have a map for X" or "find maps about Y"
```
search_maps (query: natural language description)
  → if found: get_map to load it
  → if not found: offer to create
```

### User says "show me all maps" or "what maps exist"
```
list_maps (filter by intent or architecture if mentioned)
```

### User says "publish", "make it live", "go live"
```
publish_map (journey_map_id)
  → returns snapshot + ai_summary auto-generated at publish
```

### User asks "how is X performing" or "why is stage Y failing"
```
GET /journey_map/{id}/execution_health
  → surface failure_rate per stage
  → flag stages where failure_rate > 0.20
  → suggest improvements based on common_failure_reasons
```

### Orchestrator delegates a stage to a sub-agent (ai_agent lens with agent_map_id set)
```
invoke_map {
  target_map_id: [agent_map_id from lens],
  input_data: [current stage context],
  parent_execution_id: [current execution id],
  current_map_id: [current map id — for circular guard]
}
  → wait for { execution_id, status, final_output }
  → use final_output as actor contribution
```

### User says "create a variant", "try a different version", "what if we changed X"
```
list_scenarios    { journey_architecture_id }           ← always first; find source map
clone_scenario    { source_map_id, title }              ← create variant; note new map id
fill_cells        { journey_map_id: new_id, ... }       ← make the targeted change
publish_map       { journey_map_id: new_id }            ← required before compare
compare_scenarios { map_a_id: original, map_b_id: new } ← surface the delta
```

### User says "connect this map to an exception", "wire this cell to another map", "link these maps"
```
get_map   { journey_map_id: source_map_id }   ← always first — find source_cell_id
  → locate correct cell by stage_key + lens_key in cells[]
link_map  {
  journey_architecture_id,
  source_map_id,
  source_cell_id,   ← from get_map cells[] — never guess this value
  target_map_id,
  link_type: "exception" | "anti_journey" | "sub_journey",
  label?
}
publish_map { journey_map_id: source_map_id } ← re-publish to include link in automation snapshot
```

---

## Intent Rules

| User Says | Intent |
|---|---|
| "document our process", "SOP", "playbook" | sop |
| "automate", "trigger", "workflow", "n8n" | automation |
| "some steps manual, some automated" | hybrid |
| Unclear → ask one question: "Is this for documentation, automation, or both?" | — |

---

## Scaffold Rules By Intent

| Intent | Default Lenses |
|---|---|
| sop | customer, internal, metrics |
| automation | customer, internal, handoff, engineering |
| hybrid | customer, internal, handoff, engineering, metrics |

---

## Key Constraints

- Always search before create
- Never overwrite confirmed automation configs — only write draft status
- Never publish without user confirmation unless explicitly told to
- If map_id is unknown, use search_maps or list_maps to find it first
- Bearer token must be passed on every call — do not assume auth persists

---

## Tool Summary (All 13 MCP Tools — Epic IL-0 + SCN-MCP + LM-1 Complete)

| Tool | Purpose | Key Input |
|---|---|---|
| `build_journey_map` | AI builder (autonomous end-to-end) | `journey_map_id` |
| `create_workspace` | New architecture/workspace | `title` |
| `create_journey_map` | New map draft (seeds s1-s8 + description lens) | `title`, `intent?` |
| `scaffold_map` | Add/rename/remove stages/lenses | `journey_map_id`, `stage_operations?`, `lens_operations?` |
| `fill_cells` | Write cell content/actor_fields | `journey_map_id`, `cell_updates` |
| `publish_map` | Publish + compile snapshot + generate ai_summary | `journey_map_id` |
| `list_maps` | Browse maps (includes drafts) | `architecture_id?`, `intent?`, `status?` |
| `get_map` | Full map state | `journey_map_id` |
| `search_maps` | Semantic search (active maps only) | `query?`, `intent?`, `tags?` |
| `list_scenarios` | List all scenarios in an architecture | `journey_architecture_id` |
| `clone_scenario` | Deep-clone a map into a new scenario | `journey_architecture_id`, `source_map_id`, `title?` |
| `compare_scenarios` | Side-by-side health scorecard for two maps | `journey_architecture_id`, `map_a_id`, `map_b_id` |
| `link_map` | Create directed cell→map link | `journey_architecture_id`, `source_map_id`, `source_cell_id`, `target_map_id`, `link_type` |

`invoke_map` is an orchestrator tool — not exposed as MCP but used internally by the Orchestrator agent.
`execution_health` is HTTP only: `GET /journey_map/{id}/execution_health`

---

### User says "create a variant", "try a different version", "what if we changed X"
```
list_scenarios    { journey_architecture_id }           ← always first; find source map
clone_scenario    { journey_architecture_id, source_map_id, title }  ← create variant; note new map id
fill_cells        { journey_map_id: new_id, ... }       ← make the targeted change
publish_map       { journey_map_id: new_id }            ← required before compare
compare_scenarios { journey_architecture_id, map_a_id: original_id, map_b_id: new_id }
```

### User says "connect this map to an exception", "wire this cell to another map", "link these maps"
```
get_map   { journey_map_id: source_map_id }             ← always first — find source_cell_id
  → locate correct cell by stage_key + lens_key in cells[]
link_map  {
  journey_architecture_id,
  source_map_id,
  source_cell_id,   ← from get_map cells[] — never guess this value
  target_map_id,
  link_type: "exception" | "anti_journey" | "sub_journey",
  label?
}
publish_map { journey_map_id: source_map_id }           ← re-publish to include link in snapshot
```

---

## Reference

- PRD: `product/stories/intelligence-layer-epic.md`
- Automation PRD: `product/stories/automation-epic.md`
- Scenarios MCP PRD: `product/stories/scenarios/scenarios-mcp-epic.md`
- Link Map MCP PRD: `product/stories/link-map-mcp-epic.md`
- MCP server: `mcp_servers/journey_map.xs`
- Xano base URL: `https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ`
