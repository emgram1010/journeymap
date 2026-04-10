## Scalable AI Agent Integration Epic

### Purpose

Define the epic and user stories to build a **schema-aware, config-driven AI agent** that integrates with the journey map app once and automatically adapts as new features (lenses, stages, capabilities) are added — without recoding the integration layer.

### Problem

Every new journey map feature (new lens, new stage type, new analysis capability) currently requires manual AI integration work: new tools, prompt changes, orchestrator updates. This doesn't scale.

### Solution

A **generic toolset + dynamic schema reading + capability registry** pattern where:

- The agent reads the map's current schema at runtime (stages, lenses, cells) — no hardcoded feature knowledge
- 5 generic tools cover all matrix CRUD operations for any present or future schema
- A capability registry table enables non-matrix features via config, not code
- The system prompt is assembled dynamically from live schema + enabled capabilities

### Scope

- Build 5 generic agent tools that work against any map schema
- Build 1 agent definition with a dynamic system prompt
- Build 1 orchestrator endpoint that assembles context and calls the agent
- Build 1 capability registry table for future extensibility
- Wire the frontend chat sidebar to the new AI endpoint

### Explicit non-goals

- Multi-agent routing or agent-to-agent communication
- Streaming / real-time token output
- Fine-tuning or custom model training
- Multi-user concurrent agent sessions

---

### Epic: Scalable AI Agent for Journey Map

**US-AI-01 — Create generic `get_map_state` tool**
- **Story:** As the AI agent, I need to read the full current state of any journey map (stages, lenses, cells with content/status/lock) so that I can reason about what's filled, empty, locked, or confirmed without hardcoded schema knowledge.
- **Acceptance Criteria:**
  - Tool accepts `journey_map_id` and returns all stages, lenses, and cells with their current content, status, `is_locked`, and `change_source`.
  - Stages and lenses are returned in `display_order`.
  - Works for any map regardless of how many stages/lenses it has.
  - Tool instructions describe the response shape clearly so the LLM can parse it.

**US-AI-02 — Create generic `update_cell` tool**
- **Story:** As the AI agent, I need to update any cell by `stage_key + lens_key` so that I can write interview findings into the correct cell for any lens — including lenses that don't exist yet at build time.
- **Acceptance Criteria:**
  - Tool accepts `journey_map_id`, `stage_key`, `lens_key`, and `content`.
  - Resolves the target cell by joining stage and lens keys — not by hardcoded cell ID.
  - Sets `change_source: "ai"` and `status: "draft"` on write.
  - Respects `is_locked` — returns a skip result instead of writing if locked.
  - Returns the updated cell record on success.

**US-AI-03 — Create generic `mutate_structure` tool**
- **Story:** As the AI agent, I need to add, remove, or rename stages and lenses so that I can reshape the map structure during an interview when the user describes a workflow that doesn't fit the default template.
- **Acceptance Criteria:**
  - Tool accepts `journey_map_id`, `action` (add_stage, remove_stage, rename_stage, add_lens, remove_lens, rename_lens), and relevant payload (`label`, `target_key`).
  - Adding a stage/lens auto-scaffolds cells for all existing counterparts.
  - Removing a stage/lens cascades cell deletion.
  - Renaming updates the label only.
  - Returns the updated structure (new/changed record + updated map timestamp).

**US-AI-04 — Create `batch_update` and `set_cell_status` tools**
- **Story:** As the AI agent, I need to update multiple cells in one call and change cell status/lock so that multi-cell interview answers and user confirmations are efficient.
- **Acceptance Criteria:**
  - `batch_update` accepts an array of `{ stage_key, lens_key, content }` for a given `journey_map_id`. Applies each, skipping locked cells, returns applied + skipped arrays.
  - `set_cell_status` accepts `journey_map_id`, `stage_key`, `lens_key`, and one or more of `status`, `is_locked`. Updates only the provided fields.
  - Both tools respect lock rules and return clear results.

**US-AI-05 — Create the Journey Map Assistant agent definition**
- **Story:** As the system, I need a single AI agent definition that acts as a PM interviewer, understands the matrix schema dynamically, and uses the generic tools to fill/modify the map — so that one agent handles all current and future map features.
- **Acceptance Criteria:**
  - Agent `.xs` file defines the LLM config (model, temperature, max_steps).
  - System prompt instructs the agent to: (1) read map state first, (2) ask targeted PM questions, (3) use tools to write answers into cells, (4) never touch locked/confirmed cells, (5) track progress.
  - Agent references only the 5 generic tools — no feature-specific tools.
  - Agent works with `messages` prompt type for conversation continuity.

**US-AI-06 — Build the orchestrator endpoint**
- **Story:** As the backend, I need a single API endpoint that assembles map context + conversation history, calls the agent, persists messages, and returns a structured response — so the frontend has one integration point that never changes.
- **Acceptance Criteria:**
  - Endpoint: `POST /journey_map/{journey_map_id}/ai_message`.
  - Accepts `content`, `conversation_id` (optional), and `mode` (interview/chat).
  - Loads full map bundle and conversation history before calling the agent.
  - Injects map state + mode rules into the agent context dynamically.
  - Persists user message and assistant reply to `agent_message`.
  - Returns `{ reply, cell_updates[], structural_changes[], progress, conversation }`.

**US-AI-07 — Create the capability registry table**
- **Story:** As the product team, I want a config table where I can register new non-matrix AI capabilities (e.g., generate summary, compare maps, export insights) so that the agent discovers them at runtime without code changes.
- **Acceptance Criteria:**
  - Table: `agent_capability` with fields: `key`, `label`, `tool_name`, `instructions` (markdown), `enabled` (bool), `input_schema` (JSON).
  - The orchestrator reads enabled capabilities and injects their instructions into the agent's context.
  - Disabling a capability removes it from the agent's available actions immediately.
  - Adding a new row makes the capability available on the next agent call.


**US-AI-08 — Wire the frontend chat sidebar to the new AI endpoint**
- **Story:** As a user, I want my chat messages to go through the real AI agent so that I get intelligent, context-aware responses instead of hardcoded replies — and any map updates the agent makes appear in the matrix immediately.
- **Acceptance Criteria:**
  - Frontend calls `POST /journey_map/{id}/ai_message` instead of the current message endpoint with hardcoded replies.
  - Assistant replies render in the conversation timeline.
  - `cell_updates[]` in the response are applied to the matrix grid in real time.
  - `structural_changes[]` (added/removed stages or lenses) trigger a grid refresh.
  - Progress indicator shows how much of the map is filled.
  - Errors display in the chat panel without corrupting UI state.

**US-AI-09 — Dynamic system prompt assembly**
- **Story:** As the orchestrator, I need to build the agent's system prompt at runtime from live schema + enabled capabilities + mode rules so that the agent automatically adapts when the map structure or available features change.
- **Acceptance Criteria:**
  - System prompt includes: base PM behavior instructions, current stage labels, current lens labels, cell fill status summary, enabled capabilities list, and mode-specific rules.
  - Prompt is assembled fresh on every agent call — never cached or stale.
  - Adding a new lens or capability changes what the agent knows on the next call with zero code changes.
  - Prompt size stays within model context limits (truncation strategy for large maps).

**US-AI-10 — Validation and smoke testing**
- **Story:** As the team shipping this feature, we want automated tests confirming the agent tools work correctly, the orchestrator assembles context properly, and the end-to-end flow produces valid results.
- **Acceptance Criteria:**
  - Workflow tests cover: `get_map_state` returns correct schema, `update_cell` writes and respects locks, `mutate_structure` scaffolds correctly, `batch_update` handles mixed locked/unlocked cells.
  - Smoke test confirms: send message → agent replies → cells updated → frontend reflects changes.
  - Tests verify that adding a new lens makes it visible to the agent without code changes.
  - Tests verify that disabling a capability removes it from agent context.

---

### Recommended build order

`US-AI-01 → US-AI-02 → US-AI-03 → US-AI-04 → US-AI-05 → US-AI-06 → US-AI-09 → US-AI-07 → US-AI-08 → US-AI-10`

Tools first. Then agent. Then orchestrator + dynamic prompt. Then config table. Then frontend. Then tests.

### Architecture reference

```
Frontend → POST /ai_message → Orchestrator → Agent → Generic Tools → DB
                                   ↑                       ↑
                          dynamic prompt              works for ANY
                          from live schema            stage/lens/capability
```