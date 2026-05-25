# Link Map MCP — Epic PRD

**Status:** Planning
**Goal:** Expose map-to-map link creation to AI agents via the MCP server so an agent can wire exception, anti-journey, and sub-journey connections from a specific cell to a target map — entirely through the programmatic interface.

---

## Context

The `journey_link` table and `POST /journey_architecture/{id}/link` endpoint are fully built. Map-to-map linking is how Emgram models branching process logic — a cell in one map can be the trigger point for an exception map, an alternate journey, or a delegated sub-process.

Today an AI agent using the MCP has no way to create these connections. It can build and publish maps but cannot wire the graph topology that makes automation snapshots and multi-map orchestration work.

**This becomes critical when:**
- The Automation Bridge snapshot compiler needs to traverse `journey_link` chains (Epic AB-4)
- An agent builds a scenario variant that represents an exception path and needs to connect it back to the originating cell
- The Orchestrator agent needs to register sub-agent map delegations programmatically

---

## Existing Architecture (Do Not Break)

- `journey_link` table (`table/journey_link.xs`, `tables/14_journey_link.xs`) — `(source_cell, target_map)` unique; `link_type: exception | anti_journey | sub_journey`
- `POST /journey_architecture/{id}/link` — creates the link; validates both maps belong to architecture (`api/journey_map/journey_architecture/journey_architecture_id/link_POST.xs`)
- `journey_map.journey_architecture` FK — both maps must belong to the same architecture
- `journey_cell` — links anchor to a specific cell (stage × lens intersection), not just a stage
- MCP server primary: `mcp_servers/journey_map.xs` (9 tools — canonical)
- MCP server secondary: `ai/mcp_server/journey_map.xs` (1 tool — keep in sync)
- Tool canonical location: `ai/tool/*.xs`
- Tool numbered copies: `tools/{N}_{name}.xs` — both must be created for every new tool
- Orchestrator agent: `agents/6_journey_map_orchestrator.xs` — uses `invoke_map` to follow links at runtime; does not need `link_map` (build-time only)

---

## Priority Stack

```
🟡 MED   Epic-LM-1   link_map tool
```

Priority is MED because the backend is complete and automation snapshot graph traversal (Epic AB-4 Phase 3) is the primary consumer. Not blocking the core create/edit/publish loop.

---

## Epic LM-1 — `link_map`

### US-LM-01 — Tool: `link_map`

**Input:**
```
journey_architecture_id  int   required
source_map_id            int   required
source_cell_id           int   required  — exact cell (stage × lens) where the branch originates
target_map_id            int   required  — map being linked to
link_type                enum  required  — exception | anti_journey | sub_journey
label                    text  optional  — short edge label shown on the graph
```

**Output:** Full `journey_link` record — `{ id, source_map, source_cell, target_map, link_type, label, created_at }`

**Logic (inline xs — replicate `link_POST.xs` logic, do NOT call HTTP):**
1. Validate `source_map_id != target_map_id`
2. `db.get journey_architecture` — verify exists and `owner_user == $auth.id`
3. Verify `source_map.journey_architecture == journey_architecture_id`
4. Verify `target_map.journey_architecture == journey_architecture_id`
5. Verify `source_cell.journey_map == source_map_id`
6. `db.query journey_link` — check `(source_cell, target_map)` uniqueness; surface clear error if duplicate
7. `db.add journey_link` — set `owner_user` from architecture, not from client input

**⚠️ Cell ID lookup note:** Agents must call `get_map` first to find the correct `source_cell_id`. The cell `id` is returned in the `cells[]` array from `get_map`. Agents should locate the right cell by matching `stage_key` + `lens_key` in the `get_map` response.

**Instructions string:**
> Create a directed link from a specific cell in one map to another map within the same Journey Architecture. Call `get_map` first to find the `source_cell_id` — match by `stage_key` + `lens_key` in the cells array. `link_type`: `exception` = something went wrong here and the target map handles recovery; `anti_journey` = actor did NOT follow expected path and target map handles the alternate; `sub_journey` = target map is a delegated sub-process invoked at this cell. Both maps must belong to the same architecture. One cell can only link to a given target map once — re-submitting the same pair returns an error.

**Acceptance Criteria:**
- [ ] All three `link_type` values accepted
- [ ] Returns the created `journey_link` record including `id`
- [ ] Returns clear error when `(source_cell, target_map)` pair already exists
- [ ] `owner_user` inherited from architecture — never from client input
- [ ] Returns `403` if user doesn't own the architecture
- [ ] Returns `inputerror` if either map doesn't belong to the architecture
- [ ] Self-link (`source_map_id == target_map_id`) rejected with clear error

---

## link_type Reference

| Type | When to use |
|---|---|
| `exception` | Something went wrong at this cell — target map handles the recovery or escalation path |
| `anti_journey` | The actor did NOT follow the expected flow at this cell — target map handles the alternate path |
| `sub_journey` | This cell delegates to a sub-process — target map is a self-contained process invoked here |

---

## Agent Workflow (Scenario + Exception Link Loop)

```
list_scenarios    { journey_architecture_id }           ← find the base map
clone_scenario    { source_map_id, title }              ← create the exception variant
fill_cells        { journey_map_id: clone_id, ... }     ← fill exception handling logic
publish_map       { journey_map_id: clone_id }          ← compile the exception map
get_map           { journey_map_id: base_map_id }       ← find source_cell_id from cells[]
link_map          {                                     ← wire the connection
  journey_architecture_id: arch_id,
  source_map_id:           base_map_id,
  source_cell_id:          cell_id_from_get_map,
  target_map_id:           clone_id,
  link_type:               "exception",
  label:                   "Exception: [reason]"
}
publish_map       { journey_map_id: base_map_id }       ← re-publish base map to include link in snapshot
```

---

## Complete Codebase Change List

### Files to CREATE

| File | What |
|---|---|
| `ai/tool/link_map.xs` | New tool — canonical Xano tool definition |
| `tools/61_link_map.xs` | Numbered copy — must mirror `ai/tool/link_map.xs` |
| `emgram-mcp/skills/link_map.md` | New skill file — link wiring decision tree for agents |

### Files to UPDATE

| File | Change |
|---|---|
| `mcp_servers/journey_map.xs` | Add `{name: "link_map"}` to `tools` array. Update `instructions` string to mention exception/sub-journey wiring. Tool count: 12 → 13. |
| `ai/mcp_server/journey_map.xs` | Same — keep secondary MCP server in sync |
| `emgram-mcp/instructions.md` | (1) Add link_map decision tree block (see below). (2) Add 1 row to Tool Summary table. (3) Update tool count. |

---

## `emgram-mcp/instructions.md` — Additions

**Decision tree block to add** (after the scenario block):
```
### User says "connect this map to an exception", "wire this cell to another map", "link these maps"
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

**Tool Summary table row to add:**
| `link_map` | Create directed cell→map link | `journey_architecture_id`, `source_map_id`, `source_cell_id`, `target_map_id`, `link_type` |

---

## `emgram-mcp/skills/link_map.md` — New Skill Contents

Cover:
- When to use each `link_type` (exception vs anti_journey vs sub_journey)
- Hard rule: always call `get_map` before `link_map` — never guess a `source_cell_id`
- How to find `source_cell_id` from `get_map` response (match `stage_key` + `lens_key` in `cells[]`)
- Uniqueness constraint — if `(source_cell, target_map)` already exists, surface the error and ask user whether to update via HTTP API
- Re-publish rule — after `link_map`, call `publish_map` on the **source** map to include the new link in the automation snapshot; the link alone does not update the snapshot
- Relationship to Automation Bridge (Epic AB-4) — the snapshot compiler reads `journey_link` records at publish time to build the full linked-map graph

---

## Relationship to Automation Bridge (Epic AB-4)

`link_map` creates the `journey_link` records the snapshot compiler (US-AB-09) reads at publish to build the full linked-map graph. An agent that builds and wires exception maps via MCP produces a snapshot that n8n can traverse at runtime without calling Emgram.

**Important:** After `link_map`, `publish_map` must be called on the **source** map. The link alone does not regenerate the snapshot.

---

## Updated MCP Tool Count (after this epic): 13

`build_journey_map`, `create_workspace`, `create_journey_map`, `scaffold_map`, `fill_cells`, `publish_map`, `list_maps`, `get_map`, `search_maps`, `list_scenarios`, `clone_scenario`, `compare_scenarios`, **`link_map`**

---

## Non-Goals

- Listing or deleting existing journey links via MCP — use HTTP API directly if needed
- Multi-hop link creation in one call — one link at a time
- Modifying an existing link — uniqueness enforced on `(source_cell, target_map)`; delete + recreate via HTTP API
