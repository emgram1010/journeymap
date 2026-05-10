# Specialist & Consortium Mode Epic

**Epic goal:** Transform the Emgram AI chatbot from a generic Q&A assistant into a true intelligence layer over the journey map — enabling users to talk directly to individual actors (Specialist Mode) or convene all actors simultaneously (Consortium Mode), while upgrading Chat Mode to surface actor-level tasks and advice grounded in real cell data.

---

## Context & Motivation

The current chatbot has two modes — Interview and Chat. Chat mode is read-only but generic: it can answer questions about the map, but it cannot become an actor, voice tasks from a specific perspective, or simulate a panel discussion. For maps like the Pre-Seed Launch (8 advisory personas), the user needs to query each actor directly — "what does The Lawyer say I should do at Leg 2?" — and get a response in character, grounded in that actor's identity and cell data.

Three gaps identified:
1. **Chat Mode** doesn't load `get_stage_detail` → can't see actor fields per stage
2. **Specialist Mode** doesn't exist → can't become an actor and answer in 1st person
3. **Consortium Mode** doesn't exist → can't convene all actors for a panel response

---

## Dependencies

- `agents/5_journey_map_chat_agent.xs` — extended with `get_stage_detail` tool + persona rules
- `agents/2_journey_map_assistant.xs` — extended with specialist/consortium prompt rules
- `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs` — new inputs + context injection
- `webapp/protype-2/src/xano.ts` — new params on `sendAiMessage`
- `webapp/protype-2/src/App.tsx` — new mode buttons + actor pill selector UI

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Mode storage | Keep DB mode as `chat` for specialist/consortium | Avoids schema migration; specialist/consortium are sub-modes of chat |
| 2 | Actor selection transport | `specialist_actor_key` (text) + `consortium_actor_keys` (json array) as separate API inputs | Clean separation, no enum expansion needed |
| 3 | Agent selection | Both modes route to `Journey Map Chat Agent` | Read-only persona behavior; no writes needed |
| 4 | Persona context injection | API injects `## Specialist Persona` or `## Consortium Panel` block into dynamic context | Agent reads identity + role without needing a new tool |
| 5 | UI pattern | Shared actor pill row for both modes; single-select = Specialist, multi-select = Consortium | One UI pattern, two behaviors — minimal surface area |
| 6 | Actor list source | Pulled live from `lenses` state already in `App.tsx` | Zero extra API calls |

---

## Priority Stack

```
🔴 HIGH   US-SCM-01  Chat Mode — load get_stage_detail + actor task/advice rules
🔴 HIGH   US-SCM-02  API — add specialist_actor_key + consortium_actor_keys inputs
🔴 HIGH   US-SCM-03  API — inject Specialist Persona context block
🔴 HIGH   US-SCM-04  API — inject Consortium Panel context block
🔴 HIGH   US-SCM-05  Agent — specialist persona prompt rules
🔴 HIGH   US-SCM-06  Agent — consortium panel prompt rules
🟡 MEDIUM US-SCM-07  xano.ts — new params on sendAiMessage
🟡 MEDIUM US-SCM-08  App.tsx — Specialist/Consortium mode buttons
🟡 MEDIUM US-SCM-09  App.tsx — actor pill selector UI
```

---

## User Stories

### US-SCM-01 — Chat Mode: get_stage_detail + actor task/advice
**Priority:** 🔴 HIGH
**File:** `agents/5_journey_map_chat_agent.xs`

**Story:** As a user in Chat Mode asking "what does The Operator do at Leg 3?", I want the AI to retrieve actual cell data for that actor at that stage and give me a grounded answer — not a generic response.

**Changes:**
- Add `get_stage_detail` to the chat agent tool list
- Add prompt rule: when user asks about actor tasks/advice at a stage, call `get_stage_detail` first, then answer from the actor's data
- Keep max_steps at 5 — one `get_stage_detail` call is sufficient

**Acceptance criteria:**
- "What does [actor] do at [stage]?" triggers a `get_stage_detail` call
- Response references actual `task_objective`, `entry_trigger`, or `friction_points` from the cell
- No write tools are loaded or callable

---

### US-SCM-02 — API: specialist_actor_key + consortium_actor_keys inputs
**Priority:** 🔴 HIGH
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

**Story:** As a frontend, I need to pass which actor(s) are active so the backend can inject the right persona context.

**New inputs:**
```
text specialist_actor_key?   // lens key of the active specialist actor
json consortium_actor_keys?  // array of lens keys for consortium panel
```

**Acceptance criteria:**
- Both fields are optional; existing calls without them are unaffected
- Values are available downstream in the context injection section

---

### US-SCM-03 — API: Specialist Persona context injection
**Priority:** 🔴 HIGH
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

**Story:** When `specialist_actor_key` is provided, the API looks up that lens and injects a `## Specialist Persona` block into the dynamic context so the agent can become that actor.

**Injected block format:**
```
## Specialist Persona
You ARE this actor for this entire conversation. Speak in first person.
- Actor: {label} ({actor_type})
- Persona: {persona_description}
- Primary Goal: {primary_goal}
- Standing Constraints: {standing_constraints}
```

**Acceptance criteria:**
- Block only injected when `specialist_actor_key` is non-null
- Looks up lens by journey_map_id + key match
- Missing identity fields are omitted gracefully

---

### US-SCM-04 — API: Consortium Panel context injection
**Priority:** 🔴 HIGH
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

**Story:** When `consortium_actor_keys` is provided, the API looks up all listed lens records and injects a `## Consortium Panel` block listing each actor's identity.

**Injected block format:**
```
## Consortium Panel
You represent ALL of the following actors simultaneously. For each question,
give each actor's perspective labeled with their name.
- [Actor Label]: {persona_description} | Goal: {primary_goal}
- [Actor Label]: ...
```

**Acceptance criteria:**
- Block only injected when `consortium_actor_keys` is non-empty array
- Each actor entry includes label, persona_description, primary_goal
- Missing fields omitted gracefully

---

### US-SCM-05 — Agent: Specialist persona prompt rules
**Priority:** 🔴 HIGH
**Files:** `agents/5_journey_map_chat_agent.xs`, `agents/2_journey_map_assistant.xs`

**Story:** When a `## Specialist Persona` block is present in context, the agent speaks in 1st person as that actor for the entire conversation.

**Prompt rules:**
```
## Specialist Mode
When the dynamic context contains a "## Specialist Persona" block:
- You ARE that actor. Answer in first person using their name/role.
- Ground every answer in their persona, goal, and constraints.
- When asked about a stage, call get_stage_detail and respond as that actor would.
- Stay in character. Do NOT say "as an AI" or break persona.
- If asked what to do, give the actor's specific recommendation — not generic advice.
```

**Acceptance criteria:**
- Agent responds in 1st person when Specialist block present
- Calls `get_stage_detail` when stage-specific question asked
- No persona bleed when Specialist block is absent

---

### US-SCM-06 — Agent: Consortium panel prompt rules
**Priority:** 🔴 HIGH
**Files:** `agents/5_journey_map_chat_agent.xs`, `agents/2_journey_map_assistant.xs`

**Story:** When a `## Consortium Panel` block is present, the agent responds as a panel — each actor voices their perspective, then a synthesis is provided.

**Prompt rules:**
```
## Consortium Mode
When the dynamic context contains a "## Consortium Panel" block:
- Represent ALL listed actors simultaneously.
- For each user question, respond with each actor's take.
- Format:
  **[Actor Name]:** {perspective, 1-3 sentences}
  **[Actor Name]:** {perspective, 1-3 sentences}
  ...
  **Synthesis:** {where they align or diverge, 1-2 sentences}
- Surface real tension between actors when it exists — do not smooth over disagreement.
- Call get_stage_detail when the question is stage-specific.
```

**Acceptance criteria:**
- Each actor responds in their own voice when Consortium block present
- Synthesis line always present
- Disagreement surfaced when actors have conflicting priorities
- Falls back to normal chat when neither block is present

---

### US-SCM-07 — xano.ts: new params on sendAiMessage
**Priority:** 🟡 MEDIUM
**File:** `webapp/protype-2/src/xano.ts`

**Changes:**
- Add `specialistActorKey?: string | null` to `SendAiMessageInput`
- Add `consortiumActorKeys?: string[] | null` to `SendAiMessageInput`
- Pass both to request body when present

---

### US-SCM-08 — App.tsx: Specialist/Consortium mode buttons
**Priority:** 🟡 MEDIUM
**File:** `webapp/protype-2/src/App.tsx`

**Story:** User can switch between Interview / Chat / Specialist / Consortium using the existing mode toggle pattern.

**Changes:**
- Add `chatSubMode` state: `'default' | 'specialist' | 'consortium'`
- Extend the mode toggle: `[Interview] [Chat] [Specialist] [Consortium]`
- Specialist and Consortium map to `mode: 'chat'` in the API call
- Switching to Interview clears `chatSubMode`

---

### US-SCM-09 — App.tsx: actor pill selector UI
**Priority:** 🟡 MEDIUM
**File:** `webapp/protype-2/src/App.tsx`

**Story:** When Specialist or Consortium is active, a pill row appears showing all actor lenses from the map. User selects actor(s) to activate.

**Changes:**
- `activeSpecialistKey` state (string | null) — single select for Specialist
- `activeConsortiumKeys` state (string[]) — multi select for Consortium
- Pill row rendered below mode toggle when `chatSubMode !== 'default'`
- Actors sourced from `lenses` state filtered to those with non-null `actor_type`
- Pills show actor label; active pill highlighted
- Switching mode clears selections

**UI sketch:**
```
🎭 Speaking as:  [●The Lawyer]  [The Operator]  [The Coach]   ← Specialist (single)
🏛️ Panel:  [●The Lawyer]  [●The Fundraiser]  [The Coach]     ← Consortium (multi)
```

**Acceptance criteria:**
- Pills render only for lenses with actor_type set
- `specialist_actor_key` sent when Specialist active + actor selected
- `consortium_actor_keys` array sent when Consortium active + actors selected
- Empty selection in Specialist/Consortium falls back to generic chat behavior

---

## Out of Scope

- Specialist/Consortium write access (both are read-only in this epic)
- Persisting selected actor to conversation record
- Actor avatar images
- Streaming per-actor responses in Consortium Mode
