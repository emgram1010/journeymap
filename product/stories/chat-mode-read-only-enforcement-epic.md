# Chat Mode Read-Only Enforcement Epic

**Epic goal:** Make chat mode genuinely read-only by routing to a dedicated agent that has zero write tools loaded — so the AI is structurally incapable of editing the journey map when the user is in chat mode, regardless of LLM instruction-following behaviour.

---

## Context & Motivation

The current mode system is soft. When the user switches to **Chat** mode, the `ai_message` endpoint injects `"Active mode: chat"` into the system prompt and relies on the LLM honouring the rule:

> "Do NOT modify any cells unless the user explicitly asks you to."

This is not enforced. The `Journey Map Assistant` agent still loads **all 14 tools** — including every write tool — in both interview and chat mode. The LLM can and does call write tools in chat mode because:

1. All write tools (`update_cell`, `batch_update`, `update_actor_cell_fields`, `update_actor_identity`, `update_journey_settings`, `set_cell_status`, `batch_set_status`, `mutate_structure`, `scaffold_structure`, `infer_stage_metrics`) remain available — the model can call any of them.
2. The chat-mode rule is a soft instruction buried late in a large system prompt. LLMs weight earlier context more heavily and the interview-mode write instructions appear first.
3. Ambiguous user phrasing ("Tell me about The Founder in Protect") can be interpreted as a write trigger.
4. Conversation history from a prior interview-mode turn bleeds behavioural bias into the chat-mode turn.

The fix is structural: a dedicated **Journey Map Chat Agent** that only has read tools. No write tool → no write possible.

---

## Dependencies

- `agents/2_journey_map_assistant.xs` — existing full-capability agent (interview + build).
- `agents/4_journey_map_builder.xs` — existing builder agent (fill phases).
- `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs` — orchestrator; owns agent routing logic.
- `webapp/protype-2/src/App.tsx` — sends `mode` param on every `sendAiMessage` call; no input change required.

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Enforcement layer | New dedicated agent with read-only tools | Only structural approach — LLM instruction alone is unreliable |
| 2 | Tool set for chat agent | `get_map_state`, `get_slice`, `get_gaps`, `search_cells` only | These are the only tools needed to answer questions about the map |
| 3 | Routing location | `ai_message` POST endpoint, alongside existing `builder_mode` branch | Keeps all routing in one place; no frontend change needed |
| 4 | System prompt | Explicit FORBIDDEN block at top of chat agent prompt | Earlier position = higher LLM weight; belt-and-suspenders with tool removal |
| 5 | Existing agents | `Journey Map Assistant` and `Journey Map Builder` unchanged | Chat agent is additive; no regression risk on interview or build flows |

---

## Vocabulary

| Term | Definition |
|---|---|
| **Chat agent** | The new `Journey Map Chat Agent` — read-only tool set, no write capability |
| **Read-only tools** | `get_map_state`, `get_slice`, `get_gaps`, `search_cells` — query only, no DB writes |
| **Write tools** | All tools that mutate DB state: `update_cell`, `batch_update`, `update_actor_cell_fields`, `update_actor_identity`, `update_journey_settings`, `set_cell_status`, `batch_set_status`, `mutate_structure`, `scaffold_structure`, `infer_stage_metrics` |
| **Soft enforcement** | LLM instruction-only — unreliable, current state |
| **Hard enforcement** | Tool set restriction at agent definition level — no tool loaded = no call possible |

---

## Priority Stack

```
🔴 HIGH   US-CME-01  Create Journey Map Chat Agent (read-only tool set)
🔴 HIGH   US-CME-02  Route chat mode to Chat Agent in ai_message endpoint
🟡 MEDIUM US-CME-03  Strengthen chat-mode system prompt in Chat Agent
🟢 LOW    US-CME-04  Add turn log assertion — flag any write in chat mode turns
```

---

## User Stories

### US-CME-01 — Create Journey Map Chat Agent
**Priority:** 🔴 HIGH
**File:** `agents/5_journey_map_chat_agent.xs` *(new file)*
**Depends on:** None

**Story:** As a product team, we need a dedicated agent definition for chat mode that only has read tools loaded, so it is structurally impossible for the AI to write to the journey map when the user is in chat mode.

**New agent file `agents/5_journey_map_chat_agent.xs`:**
- Agent name: `"Journey Map Chat Agent"`
- Model: `claude-sonnet-4-5` (same as siblings)
- `reasoning: false` — chat Q&A does not require extended thinking
- `max_steps: 5` — read-only turns need at most a couple of read tool calls + reply
- `temperature: 0.4`

**Tool set (read-only — 4 tools only):**
```
get_map_state
get_slice
get_gaps
search_cells
```
No write tools are loaded. `update_cell`, `batch_update`, `update_actor_cell_fields`, `update_actor_identity`, `update_journey_settings`, `set_cell_status`, `batch_set_status`, `mutate_structure`, `scaffold_structure`, `infer_stage_metrics` are **absent**.

**System prompt (key sections):**
```
## CHAT MODE — READ-ONLY. THIS IS A HARD CONSTRAINT.
You are operating in Chat mode. You CANNOT modify the journey map.
The following tools are NOT available to you in this mode:
update_cell, batch_update, update_actor_cell_fields, update_actor_identity,
update_journey_settings, set_cell_status, batch_set_status,
mutate_structure, scaffold_structure, infer_stage_metrics.
Do NOT attempt to call any write tool. If the user asks you to edit the map,
acknowledge the request and tell them to switch to Interview mode.

## Your role in Chat mode
- Answer questions about the journey map, PM best practices, or the workflow.
- Use get_map_state or get_slice to ground your answers in real map data.
- Use get_gaps to identify areas the user might want to explore next.
- Suggest follow-up interview questions the user could ask.
- Keep answers concise and actionable.
```

**Acceptance criteria:**
- Agent file exists and loads without error on Xano
- Tool list contains exactly 4 read tools — no write tool is present in the definition
- Agent can answer questions about map content by calling `get_map_state` / `get_slice`
- Agent does not attempt to call any write tool regardless of user phrasing
- Agent informs user to switch to Interview mode if they ask for an edit

---

### US-CME-02 — Route chat mode to Chat Agent in ai_message endpoint
**Priority:** 🔴 HIGH
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
**Depends on:** US-CME-01

**Story:** As a user in chat mode, I want every AI response to be handled by the read-only Chat Agent so I have a guarantee that the AI cannot touch my journey map data while I am asking questions.

**Current routing logic (lines 3191–3204):**
```
if ($input.builder_mode) → Journey Map Builder
else                     → Journey Map Assistant   ← chat mode falls here today
```

**New routing logic:**
```
if ($input.builder_mode)       → Journey Map Builder
else if ($input.mode == "chat") → Journey Map Chat Agent   ← NEW branch
else                            → Journey Map Assistant
```

**Change detail:**
- Add an `else if` branch between the existing `builder_mode` check and the `else` fallback.
- Condition: `$input.mode == "chat"`
- Agent call: `ai.agent.run "Journey Map Chat Agent"` with identical `args` and `allow_tool_execution = true`
- No other changes to the endpoint.

**Acceptance criteria:**
- `mode = "chat"` turns are routed to `Journey Map Chat Agent` — confirmed via `agent_turn_log.mode` field
- `mode = "interview"` turns continue to route to `Journey Map Assistant` — no regression
- `builder_mode = true` turns continue to route to `Journey Map Builder` — no regression
- `agent_tool_log` entries for chat turns contain only `get_map_state`, `get_slice`, `get_gaps`, or `search_cells` calls — no write tool appears
- Existing `Build Summary` and debug panel counts are unaffected for interview turns

---

### US-CME-03 — Strengthen chat-mode system prompt in Chat Agent
**Priority:** 🟡 MEDIUM
**File:** `agents/5_journey_map_chat_agent.xs`
**Depends on:** US-CME-01

**Story:** As a product team, we want the Chat Agent system prompt to be unambiguous about read-only behaviour so that even if a future tool is mistakenly added to the agent, the LLM instruction provides a second layer of protection.

**Prompt rules to enforce:**
1. Read-only constraint block appears as the **very first section** of the system prompt — before any other instruction.
2. Explicitly lists every write tool by name in the FORBIDDEN section.
3. Provides a canned response template for when users ask for edits:
   > "I'm in Chat mode and can only read your journey map. To make edits, switch to Interview mode using the toggle at the top of the chat panel."
4. Includes a note that `infer_stage_metrics` is also forbidden (it writes inferred values).

**Acceptance criteria:**
- Read-only constraint block is the first `##` section in the system prompt
- All 10 write tool names are listed explicitly in the forbidden list
- Agent uses the canned redirect message when user requests an edit
- Agent does not apologise excessively — one sentence redirect, then offer to answer a related read-only question

---

### US-CME-04 — Turn log assertion: flag write tool calls in chat mode turns
**Priority:** 🟢 LOW
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
**Depends on:** US-CME-02

**Story:** As a developer, I want the turn log to flag any turn where a write tool was called but the mode was `chat`, so we can detect regressions or edge cases where the enforcement breaks down.

**Implementation:**
After the tool trace is collected (post-agent-run, line ~3222), add a check:
- Define `$write_tool_names` as a list: `["update_cell", "batch_update", "update_actor_cell_fields", "update_actor_identity", "update_journey_settings", "set_cell_status", "batch_set_status", "mutate_structure", "scaffold_structure", "infer_stage_metrics"]`
- If `$input.mode == "chat"` AND any tool in `$tool_trace_raw` has a `tool_name` that appears in `$write_tool_names`, set a flag `$chat_write_violation = true`
- Write `$chat_write_violation` into `agent_turn_log` as a new boolean field `chat_write_violation`

This is observability only — it does not block the turn or return an error.

**Acceptance criteria:**
- `agent_turn_log` has a `chat_write_violation` boolean field
- Field is `true` only when mode is `chat` AND a write tool was called
- Field is `false` (or null) on all interview and builder turns
- No existing turn log fields are affected
- No performance impact — check runs on the already-loaded `$tool_trace_raw` array

---

## Recommended Implementation Sequence

```
US-CME-01  Create Journey Map Chat Agent (new agent file)         → 🔴 TODO
US-CME-02  Route chat mode → Chat Agent in ai_message endpoint    → 🔴 TODO
US-CME-03  Strengthen system prompt in Chat Agent                 → 🟡 TODO
US-CME-04  Turn log write-violation flag                          → 🟢 TODO
```

US-CME-01 must be complete before US-CME-02. US-CME-03 is part of the same file as US-CME-01 and can be done together. US-CME-04 is independent and can be done in any order after US-CME-02.

---

## Out of Scope (this epic)

- Streaming or real-time enforcement (blocked by `ai.agent.run` being synchronous)
- Frontend disabling of the chat input or any UI changes — routing is purely backend
- Changing which tools are available in interview mode
- `builder_mode` routing — unchanged, build flow is unaffected
- Retroactively cleaning up any cells written during prior chat-mode sessions
