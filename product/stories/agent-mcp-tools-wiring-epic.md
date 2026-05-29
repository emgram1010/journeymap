# Epic AGT-WIR-1 — Internal Agent MCP Tool Wiring

**Branch:** `epic/mcp-server-wiring`
**Status:** In Progress

## Problem

MCP tools built in Epics IL-0, SCN-MCP-1/2/3, LM-1, and SC-MCP-1 are exposed to **external** agents via the MCP server. However, eMgram's internal agents (`Journey Map Assistant`, `Journey Map Builder`) cannot call them because they are not registered in those agents' `tools` arrays.

## Goal

Wire the 5 new tools into internal agents so they are usable in interview mode and during autonomous build phases.

## Tool → Agent Matrix

| Tool | Assistant | Builder | Why |
|---|---|---|---|
| `list_scenarios` | ✅ | ❌ | User asks to browse/compare variants |
| `clone_scenario` | ✅ | ❌ | User asks to create a variant |
| `compare_scenarios` | ✅ | ❌ | User asks to compare two maps |
| `link_map` | ✅ | ❌ | User asks to wire an exception/sub-journey |
| `update_stage_contract` | ✅ | ✅ | Set stage_goal + primary_actor_lens |

Builder gets only `update_stage_contract` — it writes contracts during Phase 1 setup before content fill.

---

## Stories

### US-AGT-WIR-01 — Wire scenario + link tools into Journey Map Assistant
**File:** `agents/2_journey_map_assistant.xs`
**Changes:**
- Add `list_scenarios`, `clone_scenario`, `compare_scenarios`, `link_map`, `update_stage_contract` to `tools` array
- Add system prompt section describing when to use each tool

**Acceptance:**
- Assistant can list scenarios when user asks "show me the variants"
- Assistant can clone a scenario on user request
- Assistant can compare two maps on user request
- Assistant can link a cell to another map on user request
- Assistant can set or clear stage_goal and primary_actor_lens on user request

---

### US-AGT-WIR-02 — Wire update_stage_contract into Journey Map Builder
**File:** `agents/4_journey_map_builder.xs`
**Changes:**
- Add `update_stage_contract` to `tools` array
- Add Phase 1 build instruction: after scaffolding, call `update_stage_contract` for each stage to set stage_goal and primary_actor_lens before content fill

**Acceptance:**
- Builder sets stage contracts as part of Phase 1 scaffold phase
- Builder does NOT call scenario or link tools (out of scope for build phases)

---

## Reference Files
- `mcp_servers/journey_map.xs` — MCP server (14 tools)
- `agents/2_journey_map_assistant.xs`
- `agents/4_journey_map_builder.xs`
- `tools/58_list_scenarios.xs`
- `tools/59_clone_scenario.xs`
- `tools/60_compare_scenarios.xs`
- `tools/61_link_map.xs`
- `tools/62_update_stage_contract.xs`
