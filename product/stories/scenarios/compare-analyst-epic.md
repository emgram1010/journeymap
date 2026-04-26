# Epic: Journey Compare Analyst (AI-Driven Insights)

## Purpose

Give users an AI analyst embedded in the Compare Health view that can summarize quantitative differences between two scenarios, explain *why* scores differ, and answer follow-up questions — all in a persistent chat conversation anchored to the comparison.

## The Problem It Solves

The current Compare Health view shows numbers side-by-side with color coding but provides no interpretation. A user can see that Scenario A has a Discovery health of 3.8 vs 7.2 in Scenario B, but has no way to understand *why* without opening each journey map separately. An AI analyst fixes this by synthesizing both scorecards and the underlying stage data into plain-language insight.

## What's Different from the Journey Map Assistant

| | Journey Map Assistant | Journey Compare Analyst |
|---|---|---|
| Scope | Single journey map | Two scenarios simultaneously |
| Mode | Build + interview + edit | Read-only analysis |
| Write tools | Yes (14 tools) | None |
| Conversation stored against | `journey_map` FK | `journey_architecture` + both map IDs |
| Identity | PM interviewer / map builder | Tradeoff analyst / decision advisor |

---

## Data / Schema Changes

---

### US-CMP-01 — DB: extend `agent_conversation` for compare mode

**Story:** As a backend engineer, I want `agent_conversation` to support compare conversations so that chat history for a side-by-side comparison can be persisted like any other conversation.

**Migration: `agent_conversation` table**
- Add nullable `map_b_id` (int → `journey_map`) — the second map in a compare session
- Add nullable `journey_architecture_id` (int → `journey_architecture`) — scoping anchor
- Add `"compare"` to the `mode` enum values

**Acceptance Criteria:**
- [ ] `map_b_id` field added as nullable FK to `journey_map`
- [ ] `journey_architecture_id` field added as nullable FK to `journey_architecture`
- [ ] `mode` enum includes `"compare"` alongside `"interview"` and `"chat"`
- [ ] Existing conversations unaffected — new fields default to `null`
- [ ] All existing workflow tests continue to pass

---

### US-CMP-02 — New tool: `get_stage_detail`

**Story:** As the Compare Analyst agent, I need to read the underlying cell content for a specific stage in a specific map so I can explain *why* a stage health score is low.

**File:** `tools/16_get_stage_detail.xs`

**Input:**
```json
{ "journey_map_id": 42, "stage_key": "discovery" }
```

**Logic:** Query all cells at `stage_key` for `journey_map_id`, join with lens metadata, return actor fields + content per lens row.

**Response shape:**
```json
{
  "stage_label": "Discovery",
  "stage_key": "discovery",
  "lenses": [
    {
      "lens_key": "customer",
      "lens_label": "Customer",
      "actor_type": "customer",
      "content": "Customer is confused about tracking status",
      "actor_fields": { "emotions": "frustrated", "friction_points": "no visibility" }
    }
  ]
}
```

**Acceptance Criteria:**
- [ ] Returns all lenses for the given stage + map combination
- [ ] Returns `actor_fields` as a parsed object (not raw JSON string)
- [ ] Returns `null` content/fields gracefully when cells are empty
- [ ] Registered in agent tool list for Journey Compare Analyst

---

## Backend Story

---

### US-CMP-03 — `POST /journey_architecture/{arch_id}/compare/message`

**Story:** As a user in the Compare Health view, I want to send messages to an AI analyst that has full context on both scenarios so I can ask questions and get insights without leaving the view.

**Auth:** `auth = "user"` — verify user owns the architecture.

**Input:**
```json
{
  "map_a_id": 42,
  "map_b_id": 43,
  "conversation_id": null,
  "content": "Why is Scenario A's Discovery stage so much worse?"
}
```

**Orchestration logic:**
1. Validate both maps belong to `arch_id` and user owns the architecture
2. Fetch scorecard for both maps (reuse `/journey_map/{id}/scorecard` logic)
3. Fetch stage list + lens list for both maps
4. Build dual-context system prompt block (see below)
5. Load or create `agent_conversation` with `mode = "compare"`, `map_b_id`, `journey_architecture_id`
6. Load conversation history from `agent_message`
7. Call `Journey Compare Analyst` agent with full context + history + user message
8. Persist assistant reply to `agent_message`
9. Return reply + `conversation_id`

**Dynamic context block injected into system prompt:**
```
## Scenario A — "{title_a}" (map_id: 42)
Journey Health: 5.7 (critical)
Stages:
- Delivery Confirmed: 9.1 (healthy)
- Discovery: 3.8 (critical)
...
Financial: Revenue at Risk $0, Cost to Serve $0

## Scenario B — "{title_b}" (map_id: 43)
Journey Health: 6.3 (at_risk)
Stages:
- Delivery Confirmed: 9.1 (healthy)
- Discovery: 7.2 (at_risk)
...

## Delta Summary
| Stage | Scenario A | Scenario B | Delta | Winner |
|---|---|---|---|---|
| Discovery | 3.8 | 7.2 | +3.4 | B |
| Resolution Attempt | 6.8 | 8.2 | +1.4 | B |
...
Overall: B wins 2 metrics, A wins 0, 6 tied
```

**Acceptance Criteria:**
- [ ] Returns `400` if `map_a_id` or `map_b_id` missing
- [ ] Returns `400` if `map_a_id == map_b_id`
- [ ] Returns `403` if either map does not belong to the architecture or user doesn't own it
- [ ] Both scorecards injected into system prompt context on every turn
- [ ] Delta summary computed and injected (not left to the agent to calculate)
- [ ] Conversation history loaded and appended correctly across turns
- [ ] `conversation_id` returned in response for frontend to persist
- [ ] New conversation created if `conversation_id` is null

---

## Agent Story

---

### US-CMP-04 — New agent: `Journey Compare Analyst`

**Story:** As the system, I need a dedicated AI agent with an analytical identity, no write tools, and explicit instructions for cross-scenario reasoning so that compare conversations stay focused on insight and never attempt to edit maps.

**File:** `agents/3_journey_compare_analyst.xs`

**Identity:**
> You are an expert journey analyst. You are given two customer journey scenarios — Scenario A and Scenario B — with health scores, stage breakdowns, and financial data. Your job is to explain the differences, identify root causes, surface tradeoffs, and help the user decide which scenario produces better outcomes. You are read-only. You never edit maps.

**Tools available:**
- `get_stage_detail` (US-CMP-02) — to drill into a specific stage's underlying cell data when asked "why"

**System prompt rules:**
- Always refer to scenarios by their titles, not generic "A/B"
- Lead with the most impactful difference first
- When the user asks "why is X worse", call `get_stage_detail` for that stage on the lower-scoring map and cite specific cell content
- When both sides have `null` for a metric, say "no data yet" — do not infer a winner
- Never recommend making edits — surface findings, let the user decide
- Keep answers concise: 3–5 sentences for summary responses, bullet lists for multi-metric breakdowns

**Model:** `claude-sonnet-4-5`, `temperature: 0.3`, `reasoning: true`

**Acceptance Criteria:**
- [ ] Agent registered in Xano with correct canonical key
- [ ] `get_stage_detail` is the only tool registered — no write tools
- [ ] System prompt enforces read-only identity
- [ ] Agent correctly uses Scenario titles (not "A/B") in responses
- [ ] `get_stage_detail` called when user asks "why" questions about a specific stage

---

## Frontend Story

---

### US-CMP-05 — Compare Analyst chat panel in Compare Health view

**Story:** As a user viewing the Compare Health table, I want an AI chat panel I can open to ask questions about the comparison so I can get insight without switching views.

**Trigger:** A floating `Ask AI` button (bottom-right of the Compare Health view) — same pattern as the journey map editor's floating chat button.

**Layout:** Slide-in panel from the right (same `w-96` animated panel as the map editor). Header shows `"Compare Analyst"` label + close button. No mode toggle (compare mode only).

**Auto-prompt on open:** When the panel opens for the first time (no history), automatically send a silent system prompt:
> *"Summarize the key differences between these two scenarios and which one you'd recommend focusing on."*

This gives the user an immediate insight without requiring them to type a question first.

**State:**
- `conversationId` stored in component state (persisted across panel open/close)
- Messages accumulated in local state same as existing chat

**API call:** `POST /journey_architecture/{archId}/compare/message` with `map_a_id`, `map_b_id`, `conversation_id`, `content`

**Acceptance Criteria:**
- [ ] Floating `Ask AI` button renders bottom-right of Compare Health view
- [ ] Panel slides in/out (Framer Motion, same as editor chat)
- [ ] Auto-summary sent on first open — user sees insight immediately
- [ ] User can send follow-up messages; history persists while panel is open
- [ ] `conversation_id` is preserved across panel open/close within the same compare session
- [ ] Thinking indicator shown while AI is processing (same bounce dots as editor)
- [ ] Panel does not show Interview/Chat mode toggle — compare mode only

---

## Build Order

```
US-CMP-01 → US-CMP-02 → US-CMP-03 → US-CMP-04 → US-CMP-05
```

Schema first → tool → endpoint (needs agent) → agent → frontend.

---

## Explicit Non-Goals

- Writing to either map from the compare chat — analyst is strictly read-only
- Comparing more than 2 scenarios — color logic and delta table break with 3+
- Persisting conversation across browser sessions (future: load history on mount)
- Auto-applying the analyst's recommendation to a map — user action required
