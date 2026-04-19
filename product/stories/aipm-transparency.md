## Epic 4 — AI PM Agent Transparency

### Purpose

Make the AI PM agent's reasoning, tool usage, and actions visible to users so they can understand *why* the AI asked a question, *what data* it read, *what it wrote*, and *what it skipped*. Builds trust through progressive disclosure across three layers.

### Problem

Today the AI PM is a black box. Users see a short reply and a progress chip but have zero visibility into:
- Why the AI asked that specific question
- Which tools it called and in what order
- What data it read before answering
- What it wrote, where, and why
- What it skipped and why (locked, confirmed, empty)

### Evidence (from 50-map simulation)

- 100% of users asked "what did it just do?" at least once during a build session
- 78% of users expressed uncertainty about whether the AI wrote the correct cell
- 62% of users wanted to see what the AI read before trusting its recommendation
- "Show your work" is the #1 trust-building feature requested

### Solution: Three Layers of Progressive Disclosure

```
Layer 1: Activity Feed    — WHAT happened (always visible, compact)
Layer 2: Tool Trace       — HOW it happened (click to expand)
Layer 3: Reasoning Panel  — WHY it happened (advanced, click to expand)
```

### Impact

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| User trust (can I verify what AI did?) | No | Yes (3 layers) | ✅ |
| Debug-ability (why did AI skip my cell?) | None | Full trace | ✅ |
| Onboarding friction (how does AI work?) | High | Low (visible actions) | ✅ |
| Token overhead per turn | 0 | ~200 tokens (logging) | Acceptable |

---

### Layer 1: Activity Feed (P1 — lowest effort, highest impact)

**US-TR-01 — Surface activity summary beneath each assistant message**
- **Story:** As a user, I want to see a compact summary of what the AI did (cells read, cells written, cells skipped) beneath each assistant reply so I know what happened without expanding anything.
- **Acceptance Criteria:**
  - After each `ai_message` response, display an `<ActivityChip />` beneath the assistant bubble.
  - Format: `📖 Read: {source} · ✏️ {n} cells updated · ⏭️ {n} skipped`
  - Data source: existing `cell_updates[]` (count applied vs skipped), `progress`, `structural_changes`.
  - Map `stage_id` and `lens_id` to labels using frontend state (stages/lenses already loaded).
  - If `structural_changes.stages_changed` or `lenses_changed`, show: `🏗️ Structure changed`.
  - Clicking the chip expands to Layer 2 (if available).
- **Changes:** Frontend only (`App.tsx` or new component). No backend changes needed.
- **Response data already available:**
  ```
  cell_updates: [{ cell_id, stage_id, lens_id, content, status, change_source, is_locked }]
  structural_changes: { stages_changed, lenses_changed, current_stages?, current_lenses? }
  progress: { total_cells, filled_cells, percentage }
  ```

---

### Layer 2: Tool Trace (P2 — medium effort, high trust value)

**US-TR-02 — Create `agent_tool_log` table**
- **Story:** As the system, I need a table to store each tool call the AI agent makes so that tool traces can be retrieved and displayed to users.
- **Acceptance Criteria:**
  - New table `agent_tool_log` with schema:
    - `id` (int, PK)
    - `created_at` (timestamp, default now)
    - `conversation` (int, FK → agent_conversation)
    - `journey_map` (int, FK → journey_map)
    - `turn_id` (text) — groups tool calls within a single agent turn
    - `tool_name` (text) — e.g. "get_slice", "batch_update"
    - `tool_category` (enum: read, write, status, structure)
    - `input_summary` (text) — human-readable, e.g. "Stage 3 (Delivery)"
    - `output_summary` (text) — human-readable, e.g. "2 cells written, 1 skipped"
    - `execution_order` (int) — sequence within the turn
  - Indexed on `conversation` + `turn_id` for fast retrieval.
- **Changes:** New file `tables/6_agent_tool_log.xs`.

**US-TR-03 — Add logging to all 10 agent tools**
- **Story:** As the system, I need each agent tool to write a trace record to `agent_tool_log` so that the orchestrator can return a complete tool trace after each turn.
- **Acceptance Criteria:**
  - Every tool receives optional `conversation_id` and `turn_id` inputs.
  - When both are provided, the tool appends one row to `agent_tool_log` at the end of execution.
  - `input_summary` is a human-readable string built from the tool's inputs (not raw JSON).
  - `output_summary` is a human-readable string built from the tool's results.
  - Category mapping: get_map_state/get_slice/get_gaps/search_cells → "read", update_cell/batch_update → "write", set_cell_status/batch_set_status → "status", mutate_structure/scaffold_structure → "structure".
  - If `conversation_id` or `turn_id` is missing, skip logging (backward compatible).
- **Changes:** Modify all 10 tool files to add logging block at end of stack.

**US-TR-04 — Pass `turn_id` and `conversation_id` to agent tool calls**
- **Story:** As the orchestrator, I need to generate a unique `turn_id` before calling the agent and inject it into the agent's context so that tool calls within a turn can be grouped.
- **Acceptance Criteria:**
  - Orchestrator generates a `turn_id` (UUID or timestamp-based) before `ai.agent.run`.
  - `turn_id` and `conversation_id` are injected into the agent's system prompt context.
  - Agent instructions updated to pass `conversation_id` and `turn_id` to every tool call.
  - After `ai.agent.run`, orchestrator queries `agent_tool_log` filtered by `turn_id`.
  - Tool trace is included in the response as `tool_trace[]`.
- **Changes:** `apis/journey_map/52_...ai_message_POST.xs`, `agents/2_journey_map_assistant.xs`.
- **Response shape addition:**
  ```
  tool_trace: [
    { tool_name, tool_category, input_summary, output_summary, execution_order }
  ]
  ```

**US-TR-05 — Display tool trace in expandable panel**
- **Story:** As a user, I want to click on the activity chip to see the full sequence of tools the AI called, with human-readable summaries, so I can understand how it arrived at its answer.
- **Acceptance Criteria:**
  - Clicking the `<ActivityChip />` expands a `<ToolTrace />` panel.
  - Each tool call shows: icon (by category), tool name, input summary, output summary.
  - Tools displayed in execution order.
  - Category icons: 🔍 read, ✏️ write, 🔒 status, 🏗️ structure.
  - Panel is collapsible. Collapsed by default.
- **Changes:** Frontend component. Consumes `tool_trace[]` from response.

---

### Layer 3: Reasoning Panel (P3 — higher effort, power-user value)

**US-TR-06 — Enable agent thinking and persist reasoning**
- **Story:** As a power user, I want to see the AI's internal reasoning (why it chose that question, how it evaluated my answer quality, why it targeted that cell) so I can fully understand its decision-making.
- **Acceptance Criteria:**
  - Agent config updated: `thinking_tokens: 1000`, `include_thoughts: true`.
  - Add `thinking` field (json, optional) to `agent_message` table.
  - Orchestrator extracts thinking output from `$agent_run` and persists it in the `thinking` field of the assistant message.
  - Thinking content is returned in the `ai_message` response as `thinking: string | null`.
  - If thinking is empty or null, omit from response.
- **Changes:** `agents/2_journey_map_assistant.xs`, `tables/5_agent_message.xs`, `apis/journey_map/52_...ai_message_POST.xs`.

**US-TR-07 — Display reasoning in collapsible panel**
- **Story:** As a user, I want to optionally expand a "Show AI reasoning" panel beneath the tool trace to see the AI's thought process in plain language.
- **Acceptance Criteria:**
  - `<ReasoningPanel />` component renders below tool trace.
  - Collapsed by default. Shows "💭 Show AI reasoning" toggle.
  - Displays the raw thinking text in a styled, readable format.
  - Only rendered when `thinking` field is non-null.
  - Visually distinct from the reply (muted background, smaller font, italic).
- **Changes:** Frontend component. Consumes `thinking` from response.

---

### Build Order

```
US-TR-01 → US-TR-02 → US-TR-03 → US-TR-04 → US-TR-05 → US-TR-06 → US-TR-07
```

1. **US-TR-01** Activity Feed — ship immediately, frontend-only, instant trust boost.
2. **US-TR-02** Tool log table — foundation for all Layer 2 features.
3. **US-TR-03** Tool logging — modify all 10 tools to write traces.
4. **US-TR-04** Orchestrator integration — wire turn_id, return trace.
5. **US-TR-05** Tool trace UI — frontend display.
6. **US-TR-06** Thinking persistence — agent config + backend.
7. **US-TR-07** Reasoning UI — frontend display.

### Architecture

```
User sends message
        │
        ▼
┌─ Orchestrator (ai_message) ─────────────────┐
│  1. Generate turn_id                         │
│  2. Build context (map state, history)       │
│  3. Call ai.agent.run                        │
│     ├─ Agent calls get_gaps     → logs trace │
│     ├─ Agent calls get_slice    → logs trace │
│     ├─ Agent calls batch_update → logs trace │
│     └─ Agent returns reply + thinking        │
│  4. Query agent_tool_log by turn_id          │
│  5. Persist messages (reply + thinking)      │
│  6. Return response                          │
└──────────────────────────────────────────────┘
        │
        ▼
┌─ Response ───────────────────────────────────┐
│  reply: "Got it — logged the GPS failures."  │
│  cell_updates: [{...}, {...}]                │
│  tool_trace: [                               │
│    {get_gaps, read, "14 gaps found", 1},     │
│    {get_slice, read, "Stage 3", 2},          │
│    {batch_update, write, "2 cells", 3}       │
│  ]                                           │
│  thinking: "User mentioned GPS failures..."  │
│  progress: {total: 80, filled: 34, pct: 42} │
└──────────────────────────────────────────────┘
        │
        ▼
┌─ Frontend ───────────────────────────────────┐
│  💬 Reply bubble                             │
│  📖 Activity chip (Layer 1) ← always shown  │
│  ▶ Tool trace (Layer 2) ← click to expand   │
│  💭 Reasoning (Layer 3) ← click to expand   │
└──────────────────────────────────────────────┘
```

### Validation (US-TR-08)

- **Story:** As the team, we need workflow tests confirming tool logging, trace retrieval, and thinking persistence work correctly.
- **Acceptance Criteria:**
  - Create map → call tool with conversation_id + turn_id → verify agent_tool_log row created.
  - Call 3 tools with same turn_id → query by turn_id → verify 3 rows in execution order.
  - Call ai_message → verify `tool_trace[]` in response.
  - Verify thinking field persisted when thinking_tokens > 0.
  - All existing Epic 1-3 tests continue to pass.
- **Changes:** New workflow test file `workflow_tests/7_ai_transparency.xs`.
