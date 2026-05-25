# Scenarios MCP — Epic PRD

**Status:** Planning
**Goal:** Expose the scenario workflow to AI agents via the MCP server so an agent can list, clone, modify, and compare maps entirely through the programmatic interface.

---

## Context

The backend for scenarios is complete (US-SCN-01 through US-SCN-10). The Compare Analyst agent (US-CMP-01 through US-CMP-05) is also specced. What is missing is MCP coverage — an AI agent operating through `mcp_servers/journey_map.xs` today has no way to list, clone, or compare scenarios.

**Existing MCP coverage:** `create_workspace → create_journey_map → scaffold_map → fill_cells → publish_map → get_map → list_maps → search_maps → build_journey_map`

**Gap:** No scenario operations — agent cannot participate in the clone → modify → compare improvement loop.

**Modifying a cloned map is already covered** — `fill_cells` and `scaffold_map` both accept a `journey_map_id`, so once a clone exists the agent can edit it with existing tools.

---

## Existing Architecture (Do Not Break)

- `journey_map.journey_architecture` FK — ties a map to an architecture
- `journey_map.cloned_from_map_id` — self-referencing FK tracking clone lineage
- `GET /journey_architecture/{id}/scenarios` — lists all maps in an architecture (`api/journey_map/journey_architecture/journey_architecture_id/scenarios_GET.xs`)
- `POST /journey_architecture/{id}/scenarios/clone` — deep-clones map + stages + lenses + cells (`api/journey_map/journey_architecture/journey_architecture_id/scenarios/clone_POST.xs`)
- `GET /journey_architecture/{id}/compare` — currently returns titles + dates only (`api/journey_map/journey_architecture/journey_architecture_id/compare_GET.xs`) — tool must fetch scorecard data inline
- MCP server primary: `mcp_servers/journey_map.xs` (9 tools — canonical)
- MCP server secondary: `ai/mcp_server/journey_map.xs` (1 tool — keep in sync)
- Tool canonical location: `ai/tool/*.xs`
- Tool numbered copies: `tools/{N}_{name}.xs` — both must be created for every new tool

---

## Priority Stack

```
🔴 HIGH   Epic-SCN-MCP-1   list_scenarios tool
🔴 HIGH   Epic-SCN-MCP-2   clone_scenario tool
🟡 MED    Epic-SCN-MCP-3   compare_scenarios tool
```

---

## Epic SCN-MCP-1 — `list_scenarios`

### US-SCN-MCP-01 — Tool: `list_scenarios`

**Input:** `journey_architecture_id` (int, required)

**Output:** `[{ id, title, owner_name, created_at, updated_at, cloned_from_map_id }]`

**Logic (inline xs — follow `list_maps.xs` pattern, do NOT call HTTP):**
1. `db.get journey_architecture` — verify exists, surface notfound if null
2. `db.query journey_map` where `journey_architecture == input.journey_architecture_id`, sort `updated_at desc`
3. For each map: resolve `owner_name` via `db.get user` on `owner_user`; fallback to email if name null
4. Return array + count

**Instructions string:**
> List all journey map scenarios within a Journey Architecture. Pass `journey_architecture_id`. Returns all maps (draft and active) ordered by `updated_at DESC`. Returns `[]` when none exist — not an error. Always call this before `clone_scenario` to find the correct `source_map_id`.

**Acceptance Criteria:**
- [ ] Returns `[]` (not error) when architecture has no maps
- [ ] `owner_name` resolved from user table, fallback to email
- [ ] Ordered by `updated_at DESC`
- [ ] Returns both draft and active maps

---

## Epic SCN-MCP-2 — `clone_scenario`

### US-SCN-MCP-02 — Tool: `clone_scenario`

**Input:** `journey_architecture_id` (int, required), `source_map_id` (int, required), `title` (text, optional)

**Output:** `{ id, title, owner_name, created_at, updated_at, cloned_from_map_id }`

**Logic (inline xs — replicate `clone_POST.xs` logic, do NOT call HTTP):**
1. Validate architecture exists; validate `source_map_id` belongs to it
2. Create new `journey_map`: `cloned_from_map_id = source_map_id`, `status = "draft"`, settings fields null
3. Clone all `journey_stage` records — preserve `key`, `label`, `display_order`
4. Clone all `journey_lens` records — preserve all actor/persona fields
5. Clone all `journey_cell` records — remap stage/lens IDs via key lookup; set `is_locked = false`
6. Do NOT clone `journey_link` or `agent_conversation` records
7. Title defaults to `"Copy of Scenario"` when not provided (xs `~` concat is unavailable in API context — caller should always pass a title; backend fallback is static string only)

**Instructions string:**
> Deep-clone an existing journey map into a new scenario within the same architecture. Returns the new map `id` — pass it directly to `fill_cells` or `scaffold_map` to make targeted modifications. `journey_link` records and AI conversation history are NOT cloned — the scenario starts clean. Always pass a descriptive `title` — the backend fallback is a generic string.

**Acceptance Criteria:**
- [ ] All stages, lenses, cells copied; `cloned_from_map_id` set on new map
- [ ] `is_locked` reset to `false` on all cloned cells
- [ ] No journey links or agent conversations copied
- [ ] Journey settings fields reset to null on the new map
- [ ] Source map completely unchanged after clone

---

## Epic SCN-MCP-3 — `compare_scenarios`

### US-SCN-MCP-03 — Tool: `compare_scenarios`

**Input:** `journey_architecture_id` (int, required), `map_a_id` (int, required), `map_b_id` (int, required)

**Output:**
```json
{
  "map_a": { "id", "title", "journey_health", "revenue_at_risk", "critical_stages",
             "stage_breakdown": [{ "stage_key", "stage_label", "stage_health" }] },
  "map_b": { ... }
}
```

**⚠️ Backend gap note:** `compare_GET.xs` returns titles + dates only. This tool must fetch scorecard metrics inline — query `journey_cell` status counts and stage-level data per map directly in xs rather than waiting for a backend API update.

**Logic:**
1. Validate both maps belong to `journey_architecture_id`; `map_a_id != map_b_id`
2. For each map: fetch stages + cells; compute `journey_health`, `revenue_at_risk`, `critical_stages`, per-stage health
3. Align stage breakdown by `stage_key` — stages missing from one side return `null` health for that side
4. Return combined response

**Instructions string:**
> Compare the health scorecard of two scenarios side-by-side. Pass `journey_architecture_id`, `map_a_id`, `map_b_id`. Returns journey health, revenue at risk, critical stage count, and per-stage health for both. Higher journey health + lower revenue at risk = better scenario. `null` means no data yet — never infer a winner when one side is null.

**Acceptance Criteria:**
- [ ] Returns full scorecard for both maps, not just titles/dates
- [ ] `null` for missing metrics — never zero or omitted
- [ ] Stage breakdown ordered by `display_order`
- [ ] Stages missing from one side return `null` health on that side
- [ ] Returns `400` if `map_a_id == map_b_id`
- [ ] Returns `403` if either map doesn't belong to the architecture

---

## Agent Workflow (Full Loop)

```
list_scenarios    { journey_architecture_id }           ← find source map ID
clone_scenario    { source_map_id, title }              ← create variant
fill_cells        { journey_map_id: new_id, ... }       ← make the one change (existing)
publish_map       { journey_map_id: new_id }            ← generate ai_summary (existing)
compare_scenarios { map_a_id: original, map_b_id: new } ← surface the delta
```

---

## Complete Codebase Change List

### Files to CREATE

| File | What |
|---|---|
| `ai/tool/list_scenarios.xs` | New tool — canonical Xano tool definition |
| `ai/tool/clone_scenario.xs` | New tool — canonical Xano tool definition |
| `ai/tool/compare_scenarios.xs` | New tool — canonical Xano tool definition |
| `tools/58_list_scenarios.xs` | Numbered copy — must mirror `ai/tool/list_scenarios.xs` |
| `tools/59_clone_scenario.xs` | Numbered copy — must mirror `ai/tool/clone_scenario.xs` |
| `tools/60_compare_scenarios.xs` | Numbered copy — must mirror `ai/tool/compare_scenarios.xs` |
| `emgram-mcp/skills/scenarios.md` | New skill file — scenario workflow decision tree for agents |

### Files to UPDATE

| File | Change |
|---|---|
| `mcp_servers/journey_map.xs` | Add `{name: "list_scenarios"}`, `{name: "clone_scenario"}`, `{name: "compare_scenarios"}` to `tools` array. Update `instructions` string to mention scenario workflow. Tool count: 9 → 12. |
| `ai/mcp_server/journey_map.xs` | Same 3 entries — keep secondary MCP server in sync with primary |
| `emgram-mcp/instructions.md` | (1) Add scenario decision tree block (see below). (2) Add 3 rows to Tool Summary table. (3) Update header "9 MCP Tools" → "12 MCP Tools". |

---

## `emgram-mcp/instructions.md` — Additions

**Decision tree block to add** (after the "User says publish" block):
```
### User says "create a variant", "try a different version", "what if we changed X"
list_scenarios    { journey_architecture_id }           ← always first; find source map
clone_scenario    { source_map_id, title }              ← create variant; note new map id
fill_cells        { journey_map_id: new_id, ... }       ← make the targeted change
publish_map       { journey_map_id: new_id }            ← required before compare
compare_scenarios { map_a_id: original, map_b_id: new } ← surface the delta
```

**Tool Summary table rows to add:**
| `list_scenarios` | List all scenarios in an architecture | `journey_architecture_id` |
| `clone_scenario` | Deep-clone a map into a new scenario | `journey_architecture_id`, `source_map_id`, `title?` |
| `compare_scenarios` | Compare health scorecard of two maps | `journey_architecture_id`, `map_a_id`, `map_b_id` |

---

## `emgram-mcp/skills/scenarios.md` — New Skill Contents

Cover:
- When to use scenario tools vs standard map tools
- Full clone → modify → compare loop with exact tool calls and expected outputs
- Hard rule: always `list_scenarios` first — never call `clone_scenario` without knowing the source map ID
- Hard rule: always `publish_map` on the clone before `compare_scenarios` — unpublished maps have no `ai_summary` and incomplete scorecard data
- `null` metric handling — do not declare a winner when one side lacks data; surface both values and let the operator decide
- How to communicate compare results to the user (lead with biggest delta, not alphabetical)

---

## Updated MCP Tool Count (after this epic): 12

`build_journey_map`, `create_workspace`, `create_journey_map`, `scaffold_map`, `fill_cells`, `publish_map`, `list_maps`, `get_map`, `search_maps`, **`list_scenarios`**, **`clone_scenario`**, **`compare_scenarios`**

---

## Non-Goals

- Cell-level diff view between scenarios — needs lineage logic, deferred
- Comparing more than 2 scenarios in one call
- Auto-declaring a winner — surface tradeoffs, let the operator decide
- Deleting or renaming scenarios via MCP — use HTTP API directly
- Auto-applying compare insights back to a map
