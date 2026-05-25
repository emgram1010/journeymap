# Intelligence Layer — Epic PRD

**Status:** Planning
**Goal:** Enable an AI agent to operate as a first-class operator inside Emgram — building maps, reading state, scaffolding actors, publishing snapshots, and delegating to sub-agents — entirely through a programmatic interface with no UI dependency.

---

## Vision

> Emgram is an AI-native process operating system. The journey map is the universal unit of work. The AI is not a chatbot inside the product — it is an operator OF the product. Any actor in any map can become an agent. Any map can invoke another map and receive its output. The system compounds intelligence as more maps exist.

**Through-line:**
```
Process → Journey Map → Actors → Agents → Sub-maps → Execution → Feedback → Index → Better AI
```

---

## Existing Architecture (Do Not Break)

- `journey_map → journey_stage → journey_lens → journey_cell → actor_fields` — core data model
- `journey_link` with types `exception`, `anti_journey`, `sub_journey` — map-to-map relationships
- `workflow_execution` with `parent_execution_id` — nested execution tracking already in schema
- `agent_capability` table — runtime capability registry injected into agents dynamically
- `ai_agent` actor type — exists with fields: `ai_model_agent`, `input_data`, `decision_output`, `confidence_threshold`, `escalation_logic`, `failure_scenarios`
- MCP server: `mcp_servers/journey_map.xs` — exists, only exposes `build_journey_map` today
- Agents: Builder, Assistant, Orchestrator, Chat — all in `ai/agent/`
- Tools: `get_map_state`, `scaffold_structure`, `mutate_structure`, `search_cells`, `save_workflow_state`, `get_workflow_state` — all in `ai/tool/`
- Xano base URL: `https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ`
- Auth: Bearer token via `Authorization` header

---

## Priority Stack

```
🔴 CRITICAL  Epic-IL-0  Complete MCP Server — 8 tools
🔴 HIGH      Epic-IL-1  Map Index Layer — ai_summary + tags + search
🟡 MED       Epic-IL-2  Actor → Sub-Agent Binding
🟡 MED       Epic-IL-3  Map Invocation Protocol
🟢 LOW       Epic-IL-4  Sub-Agent Runtime + Self-Organizing Loop
```

---

## Epic IL-0 — Complete the MCP Server
**Unlock the AI as an operator. Nothing downstream works without this.**

**File:** `mcp_servers/journey_map.xs`
**Current state:** Only `build_journey_map` is exposed. Full CRUD, scaffold, publish, list, search are missing.

### US-IL-00-01 — MCP tool: `create_workspace`
**Maps to:** `POST /journey_architecture`
**Input:** `title`, `description?`, `account_id?`
**Output:** architecture record with `id`

### US-IL-00-02 — MCP tool: `create_journey_map`
**Maps to:** `POST /journey_map/create_draft`
**Input:** `title`, `journey_architecture_id?`, `intent?` (sop / automation / hybrid)
**Output:** map bundle with `id`, default stages, default lenses

### US-IL-00-03 — MCP tool: `scaffold_map`
**Maps to:** existing AI tool `scaffold_structure`
**Input:** `journey_map_id`, `stage_operations[]`, `lens_operations[]`
**Output:** stages added, lenses added, cells created count

### US-IL-00-04 — MCP tool: `fill_cells`
**Maps to:** existing AI tools `batch_update` + `update_actor_cell_fields`
**Input:** `journey_map_id`, array of `{ stage_key, lens_key, content?, actor_fields? }`
**Output:** cells written count, skipped count

### US-IL-00-05 — MCP tool: `publish_map`
**Maps to:** `POST /journey_map/{id}/publish`
**Input:** `journey_map_id`
**Output:** `{ version, snapshot_url, webhook_push_results }`

### US-IL-00-06 — MCP tool: `list_maps`
**Maps to:** `GET /journey_map` scoped to authenticated user
**Input:** `architecture_id?`, `intent?`, `status?`
**Output:** array of `{ id, title, intent, status, last_interaction_at }`

### US-IL-00-07 — MCP tool: `get_map`
**Maps to:** existing AI tool `get_map_state`
**Input:** `journey_map_id`
**Output:** full map state — stages, lenses, cells, fill status

### US-IL-00-08 — MCP tool: `search_maps`
**Maps to:** new `GET /journey_map/search` endpoint (built in Epic IL-1)
**Input:** `query`, `intent?`, `tags?`
**Output:** ranked list of `{ map_id, title, ai_summary, intent, tags }`

**Acceptance Criteria — Epic IL-0:**
- All 8 tools registered in `mcp_servers/journey_map.xs`
- AI can execute full flow in one session: create workspace → create map → scaffold → fill → publish → retrieve snapshot
- Existing `build_journey_map` tool unchanged

---

## Epic IL-1 — Map Index Layer
**Every published map is findable by a future AI without scanning cells.**

### US-IL-01-01 — Add `intent`, `ai_summary`, `tags` to `journey_map` table
**File:** `table/journey_map.xs`
**Additions:**
```
enum intent? { values = ["sop", "automation", "hybrid"] }
text ai_summary?   // AI-generated at publish. Max 500 chars. Structured text.
json tags?         // Array of strings. e.g. ["onboarding", "linkedin", "crm"]
```
**Backward compatible:** all fields nullable, existing maps unaffected.

### US-IL-01-02 — Expose `intent` in `create_draft` endpoint
**File:** `api/journey_map/journey_map/create_draft_POST.xs`
**Change:** accept `intent` as optional input, write to record on creation

### US-IL-01-03 — Auto-generate `ai_summary` on publish
**File:** `api/journey_map/journey_map/journey_map_id/publish_POST.xs`
**Trigger:** end of publish, after snapshot compiles successfully
**One LLM call. Structured output format:**
```
Process: [one sentence — what this journey does]
Actor: [primary actor]
Domain: [industry/function tag]
Triggers: [what starts it]
Outcome: [what it produces]
Stages: [comma-separated stage labels]
Intent: [sop | automation | hybrid]
```
**Cost model:** 1 LLM call at publish time only. Zero tokens at query time.
**Write result to:** `journey_map.ai_summary`

### US-IL-01-04 — Account-scoped `search_maps` endpoint
**New file:** `api/journey_map/journey_map/search_GET.xs`
**Auth:** user-scoped (searches only maps owned by `auth.account_id`)
**Input:** `query` (text), `intent?`, `tags?`
**Behavior:** full-text search on `ai_summary` + `tags` fields
**Output:** `[{ map_id, title, ai_summary, intent, tags, last_published_at }]` ranked by relevance

**Acceptance Criteria — Epic IL-1:**
- Publishing a map auto-writes `ai_summary` without user action
- `search_maps` MCP tool returns correct results for natural language query
- Zero cells scanned during search

---

## Epic IL-2 — Actor → Sub-Agent Binding
**An actor's intelligence is defined by a journey map.**

### US-IL-02-01 — Add `agent_map_id` to `journey_lens` table
**File:** `table/journey_lens.xs`
**Addition:**
```
int agent_map_id? {
  table = "journey_map"
}
```
**Meaning:** when an `ai_agent` actor lens has `agent_map_id` set, the linked map defines that actor's behavior and decision logic. Recursive by design — that map can itself have `ai_agent` actors with their own `agent_map_id`.

### US-IL-02-02 — Orchestrator reads `agent_map_id` and delegates
**File:** `ai/agent/journey_map_orchestrator.xs`
**Change:** when executing a stage with an `ai_agent` actor that has `agent_map_id` populated:
1. Invoke the linked map via map invocation protocol (Epic IL-3)
2. Pass current stage context as `input_data`
3. Wait for sub-execution result
4. Use returned output as the actor's stage contribution
5. Continue main map execution

**Acceptance Criteria — Epic IL-2:**
- Setting `agent_map_id` on a lens causes orchestrator to delegate instead of generate text
- Sub-execution tracked with correct `parent_execution_id`
- Main map waits for sub-map completion before advancing

---

## Epic IL-3 — Map Invocation Protocol
**The missing nerve system. Map A calls Map B and receives structured results.**

### US-IL-03-01 — Map invocation endpoint
**New file:** `api/journey_map/journey_map_id/invoke_POST.xs`
**Input:**
```json
{
  "input_data": {},
  "parent_execution_id": null,
  "subject_id": "lead_42",
  "subject_label": "Acme Corp"
}
```
**Behavior:**
1. Creates child `workflow_execution` with `parent_execution_id` set (links to caller)
2. Runs orchestrator on the target map with `input_data` as context
3. Completes all stages or halts on blocker
4. Returns `{ execution_id, status, stage_outputs, final_output }`

**Acceptance Criteria — Epic IL-3:**
- Map A can call Map B and receive output in same execution session
- `workflow_execution` tree correctly represents parent → child relationship
- Circular invocation prevented (map cannot invoke itself)

---

## Epic IL-4 — Sub-Agent Runtime + Self-Organizing Loop
**The system learns from its own execution.**

### US-IL-04-01 — Execution health endpoint
**New file:** `api/journey_map/journey_map_id/execution_health_GET.xs`
**Returns:** per-stage `{ failure_rate, avg_completion_time, common_failure_reasons[] }`
**Source:** aggregates `workflow_execution.stage_outputs` across all runs for the map

### US-IL-04-02 — AI improvement suggestions
**Trigger:** when `execution_health` shows `failure_rate > 0.20` on any stage
**Surface in:** map dashboard — "Stage X has a 34% failure rate. Suggested fix: [AI recommendation]"
**Recommendation logic:** pattern-match `failure_reason` values against handoff lens content + exception_condition config

### US-IL-04-03 — Full actor → map → agent chain
**Depends on:** Epic IL-2 + Epic IL-3 both complete
**Enables:** actor-agents can themselves have actor-agents, tracked via `parent_execution_id` chain. Parent map synthesizes all sub-map outputs before advancing.

---

## Build Order

```
US-IL-00-01 through 00-08  MCP server tools        ← START HERE
US-IL-01-01                intent + ai_summary + tags fields
US-IL-01-02                create_draft accepts intent
US-IL-01-03                publish auto-generates ai_summary
US-IL-01-04                search_maps endpoint
US-IL-02-01                agent_map_id on journey_lens
US-IL-02-02                orchestrator delegation logic
US-IL-03-01                map invocation endpoint
US-IL-04-01                execution health endpoint
US-IL-04-02                improvement suggestions
US-IL-04-03                full sub-agent runtime
```

---

## Files To Create or Modify

| File | Story | Change |
|---|---|---|
| `mcp_servers/journey_map.xs` | IL-00-01 to 08 | Add 8 MCP tool declarations |
| `table/journey_map.xs` | IL-01-01 | Add `intent`, `ai_summary`, `tags` |
| `api/journey_map/journey_map/create_draft_POST.xs` | IL-01-02 | Accept `intent` input |
| `api/journey_map/journey_map/journey_map_id/publish_POST.xs` | IL-01-03 | Generate `ai_summary` post-compile |
| New: `api/journey_map/journey_map/search_GET.xs` | IL-01-04 | Account-scoped map search |
| `table/journey_lens.xs` | IL-02-01 | Add `agent_map_id` FK |
| `ai/agent/journey_map_orchestrator.xs` | IL-02-02 | Delegation on `agent_map_id` |
| New: `api/journey_map/journey_map_id/invoke_POST.xs` | IL-03-01 | Map invocation protocol |
| New: `api/journey_map/journey_map_id/execution_health_GET.xs` | IL-04-01 | Health aggregation |
