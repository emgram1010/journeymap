# Epic SCN-EDIT-1 — Scenario Cell Edit Tools for MCP

## Problem
The scenario "what-if" loop is incomplete. External AI agents can clone a base map and compare
two scenarios, but cannot modify the clone's cells via MCP. This breaks the core loop:

```
clone_scenario → (gap) → compare_scenarios
```

`update_cell` and `batch_update` exist as internal agent tools but are not exposed on the MCP
server, and the Journey Map Assistant's scenario rules don't include the edit step.

---

## Goal
Close the gap so any MCP caller (Claude, external agent, CRM integration) can:
1. Clone a base map
2. Apply targeted cell improvements to the clone
3. Compare the original vs the improved scenario

---

## Stories

### US-SCN-EDIT-01 — Add `update_cell` to MCP server
**As an** external AI agent  
**I want to** write content into a single cell by stage_key + lens_key on a cloned map  
**So that** I can make targeted, surgical improvements to a scenario  

**Acceptance criteria:**
- `update_cell` appears in `mcp_servers/journey_map.xs` tools array
- MCP instructions updated with scenario modification loop section
- Tool skips locked/confirmed cells and returns skip_reason

---

### US-SCN-EDIT-02 — Add `batch_update` to MCP server
**As an** external AI agent  
**I want to** write improvements to multiple cells in a single call  
**So that** I can efficiently apply a set of changes to a cloned scenario  

**Acceptance criteria:**
- `batch_update` appears in `mcp_servers/journey_map.xs` tools array
- Returns applied/skipped arrays per cell

---

### US-SCN-EDIT-03 — Update MCP server instructions — scenario modification loop
**As an** MCP caller  
**I want** the server instructions to describe the full scenario loop  
**So that** the AI knows the correct sequence  

**Full loop documented:**
```
list_scenarios → clone_scenario → update_cell / batch_update → publish_map → compare_scenarios
```

---

### US-SCN-EDIT-04 — Update Journey Map Assistant prompt — scenario edit step
**As an** eMgram internal AI assistant  
**I want** scenario management rules to include cell-editing guidance after cloning  
**So that** I proactively offer to improve the clone before comparing  

**Acceptance criteria:**
- Scenario rules in `agents/2_journey_map_assistant.xs` extended with edit step
- Rule: after `clone_scenario`, ask user which cells to improve, then call `update_cell` or `batch_update`
- Rule: after edits, call `publish_map` on the clone before `compare_scenarios`

---

### US-SCN-EDIT-05 — Update emgram-mcp/instructions.md
**As a** developer  
**I want** the MCP brain doc to list `update_cell` and `batch_update`  
**So that** the tool table and decision tree are complete  

**Acceptance criteria:**
- Two new rows in the tool table (category: Scenario Edit)
- Decision tree entry for the full scenario modification loop

---

## Tool Summary

| Tool | File | Already in MCP? | Already in Assistant? |
|---|---|---|---|
| `update_cell` | `tools/3_update_cell.xs` | ❌ | ✅ |
| `batch_update` | `tools/5_batch_update.xs` | ❌ | ✅ |

## Notes
- `fill_cells` is already in MCP (bulk write for initial build) — `batch_update` is the scenario-edit
  equivalent (respects locked/confirmed, returns per-cell results)
- Merge conflicts in `mcp_servers/journey_map.xs` and `agents/2_journey_map_assistant.xs` must be
  resolved as part of execution
