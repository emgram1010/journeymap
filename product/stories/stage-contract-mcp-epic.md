# Epic SC-MCP-1 — Stage Contract MCP Tool

**Tool name:** `update_stage_contract`
**File to create:** `tools/62_update_stage_contract.xs`
**Delegates to:** `PATCH /journey_stage/update/:id` (endpoint 211)

---

## Why

Every stage in eMgram has two contract fields that turn a label into an accountable unit:

| Field | Meaning |
|---|---|
| `stage_goal` | Exit condition / definition of done (one-liner) |
| `primary_actor_lens` | Lens key of the actor who owns this stage's outcome |

Both fields exist in the DB (`journey_stage` table) and are writable via endpoint 211.
`get_map_state` already returns them — so **read is already live**.

The gap: **no MCP tool lets an agent write them directly**. `scaffold_map` can set labels and add/remove stages, but there is no dedicated surface for setting stage contracts without knowing the internal scaffold syntax. An agent that wants to assign ownership or define done for a specific stage must currently guess.

---

## Scope

| Operation | How |
|---|---|
| **Read** | `get_map_state` — stages[] already includes `stage_goal` + `primary_actor_lens` ✅ |
| **Create / Update** | `update_stage_contract` → PATCH endpoint 211 |
| **Clear (Delete)** | Same tool — pass `stage_goal: null` or `primary_actor_lens: null` |

---

## Stories

### US-SC-MCP-01 — Create `update_stage_contract` tool
**File:** `tools/62_update_stage_contract.xs`

**Story:** As an MCP agent, I can set or clear the `stage_goal` and `primary_actor_lens` on any stage so that every stage has an explicit contract without needing to know the scaffold_map syntax.

**AC:**
- Input: `journey_map_id` (int, min:1), `journey_stage_id` (int, min:1), `stage_goal?` (text, nullable), `primary_actor_lens?` (text, nullable)
- Validates: stage exists AND belongs to the given map — return `notfound` otherwise
- Calls endpoint 211 (`PATCH /journey_stage/update/:id`) with `stage_goal` and `primary_actor_lens`
- Response: returns updated `{ id, stage_goal, primary_actor_lens, label, key }` from the stage record
- To **clear** a field, agent passes `null` — tool passes it through as null to the API
- `label` is read from the existing stage and re-sent unchanged (endpoint 211 requires it)

---

### US-SC-MCP-02 — Register `update_stage_contract` in MCP server
**File:** `mcp_servers/journey_map.xs`

**Story:** As an external agent calling via MCP, I can invoke `update_stage_contract` the same way I invoke the other 13 tools.

**AC:**
- `{name: "update_stage_contract"}` added to the `tools = [...]` array in `mcp_servers/journey_map.xs`
- Total registered tools becomes 14

---

### US-SC-MCP-03 — Update `emgram-mcp/instructions.md`
**File:** `emgram-mcp/instructions.md`

**Story:** As an agent reading the MCP instruction manual, I know when and how to use `update_stage_contract`.

**AC:**
- Tool added to the Tool Summary table (14 total)
- Decision tree added:

```
### User says "set the goal for stage X", "who owns stage Y", "assign [actor] as owner of stage Z"
get_map_state { journey_map_id }                  ← always first — find stage id + current primary_actor_lens
update_stage_contract {
  journey_map_id,
  journey_stage_id,   ← from get_map_state stages[].xanoId — never guess
  stage_goal?,        ← omit if not changing
  primary_actor_lens? ← lens key from stages[].cells[].lens_key — never use lens label
}
```

- Notes: `primary_actor_lens` is a **lens key** (e.g. `"l1"`, `"l2"`), not a label. Agent must look up the lens key from `get_map_state` before setting it.
- Notes: read is free via `get_map_state` — do NOT call `update_stage_contract` for read-only queries.

---

## Execution Order

```
1. US-SC-MCP-01  Create tools/62_update_stage_contract.xs
2. US-SC-MCP-02  Register in mcp_servers/journey_map.xs
3. US-SC-MCP-03  Update emgram-mcp/instructions.md
4. xano workspace push --include tools/62_... --include mcp_servers/... --force
5. git add + commit + push
```

---

## File Map

| Layer | File |
|---|---|
| MCP tool | `tools/62_update_stage_contract.xs` *(new)* |
| MCP server | `mcp_servers/journey_map.xs` *(+1 tool entry)* |
| Instructions | `emgram-mcp/instructions.md` *(+1 table row + decision tree)* |
| Backend API | `apis/journey_map/211_journey_stage_update_journey_stage_id_PATCH.xs` *(no change needed)* |
| DB | `tables/7_journey_stage.xs` *(no change needed — fields already exist)* |
