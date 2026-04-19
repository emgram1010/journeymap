# AI Agent Empowerment Epic

## Goal
Enable the AI agent to *write* structured data — not just read it. Closes the gap where the agent can see actor cell fields, actor identity, and journey settings in context, but cannot populate them.

## Stories

---

### US-AIE-01 — Create `update_actor_cell_fields` tool
**File:** `tools/12_update_actor_cell_fields.xs`

**Story:** As the AI agent, I want to write one or more structured `actor_fields` into a cell (identified by stage_key + lens_key) so that the matrix captures the full actor perspective, not just freetext notes.

**Inputs:**
- `journey_map_id` (int)
- `stage_key` (text)
- `lens_key` (text)
- `actor_fields` (json) — partial or full key-value object (e.g. `{emotions: "Anxious", entry_trigger: "Order confirmation"}`)
- `conversation_id` (int, optional — for trace logging)
- `turn_id` (text, optional)

**Behavior:**
- Resolve cell by stage_key + lens_key
- Skip if cell is locked or confirmed
- PATCH `actor_fields` on the cell via `journey_cell/update/{id}`
- Log to `agent_tool_log` with category `write`

**AC:**
- Agent can partially update actor_fields without overwriting unfilled keys
- Locked / confirmed cells return skip result
- Tool trace logged

---

### US-AIE-02 — Create `update_actor_identity` tool
**File:** `tools/13_update_actor_identity.xs`

**Story:** As the AI agent, I want to write actor identity fields (persona_description, primary_goal, standing_constraints) to a lens row so the actor profile is populated from conversation context.

**Inputs:**
- `journey_map_id` (int)
- `lens_key` (text)
- `persona_description` (text, optional)
- `primary_goal` (text, optional)
- `standing_constraints` (text, optional)
- `conversation_id` (int, optional)
- `turn_id` (text, optional)

**Behavior:**
- Resolve lens by lens_key within journey_map_id
- PATCH via `journey_lens/actor_fields/{lens_id}`
- Log to `agent_tool_log`

**AC:**
- Agent can populate persona, goal, constraints
- Partial updates allowed — only provided fields are written
- Tool trace logged

---

### US-AIE-03 — Create `update_journey_settings` tool
**File:** `tools/14_update_journey_settings.xs`

**Story:** As the AI agent, I want to write map-level context fields (primary_actor, journey_scope, start_point, etc.) so that the journey settings panel is populated from the conversation.

**Inputs:**
- `journey_map_id` (int)
- Any subset of: `primary_actor`, `journey_scope`, `start_point`, `end_point`, `duration`, `success_metrics`, `key_stakeholders`, `dependencies`, `pain_points_summary`, `opportunities`, `version`
- `conversation_id` (int, optional)
- `turn_id` (text, optional)

**Behavior:**
- PATCH via `journey_map/settings/{journey_map_id}`
- Log to `agent_tool_log`

**AC:**
- Agent can populate any subset of settings fields
- Tool trace logged

---

### US-AIE-04 — Update agent system prompt
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

**Story:** As the AI agent, I want my system prompt to describe the three new write tools so I know when and how to use them to fill structured gaps.

**Behavior:**
- Add tool descriptions to the agent's `system_prompt`
- Instruct agent: after filling a cell's content, also attempt to fill individual actor_fields if the template provides them
- Instruct agent: when the user provides identity context (who they are, their goals, constraints), call `update_actor_identity`
- Instruct agent: when the user provides journey-level context (scope, start/end, stakeholders), call `update_journey_settings`
