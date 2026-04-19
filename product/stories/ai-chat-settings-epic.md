## AI Chat Settings Epic

### Purpose

Give users explicit control over how the AI agent behaves during their session. Right now every behavioral parameter — tone, quality enforcement, write confirmation, focus area — is hardcoded in the agent definition and invisible to the user. This epic surfaces those controls as a per-map, per-session settings panel so users can tune the AI to their working style and context.

### The 5 Settings

| # | Setting | Type | Default | What It Controls |
|---|---|---|---|---|
| 1 | **Interview Style** | Enum (`formal`, `collaborative`, `rapid`) | `collaborative` | Tone and phrasing of AI questions. Formal = structured PM cadence. Collaborative = conversational and exploratory. Rapid = skips pleasantries, fires through cells. |
| 2 | **Quality Gate** | Enum (`strict`, `balanced`, `permissive`) | `balanced` | How hard the AI probes before accepting a vague answer. Strict = always probes until specific. Permissive = writes what it gets and moves on. |
| 3 | **Auto-Confirm AI Writes** | Boolean | `false` | When off, AI-written cells land as `draft` and need user confirmation. When on, AI writes land as `confirmed` immediately. |
| 4 | **Focus Mode** | Enum (`balanced`, `customer`, `operations`, `engineering`) | `balanced` | Which lens types the agent prioritises in Interview Mode when choosing what to ask next. |
| 5 | **Show AI Reasoning** | Boolean | `true` | Whether the reasoning / thinking disclosure panel renders beneath AI messages. Pure preference — does not affect AI behaviour. |

### Scope

- A new `ai_chat_settings` JSON column on the `journey_map` table
- A dedicated PATCH endpoint for saving AI chat settings
- AI chat settings included in the load bundle response
- AI chat settings injected into the AI agent system prompt by the orchestrator
- Frontend AI Chat Settings panel accessible from the chat header
- Agent prompt updated to honour the four behavioural settings

### Explicit non-goals

- Per-message or per-turn settings overrides
- Exposing raw `temperature` or `max_steps` sliders to end users
- Model selection by end users
- Settings that affect Journey Settings (primary actor, scope, etc.) — that panel is separate

---

## Stories

---

**US-ACS-01 — Add `ai_chat_settings` column to the journey_map schema**

**Story:** As a product operator, I want the journey map record to store AI chat settings so that a user's behavioural preferences persist across sessions and are available to the orchestrator on every call.

**Acceptance Criteria:**
- A new `ai_chat_settings` column of type `json` is added to the `journey_map` table
- The column is nullable and optional — existing records are unaffected
- The expected shape is: `{ interview_style, quality_gate, auto_confirm_writes, focus_mode, show_reasoning }`
- No migration required — null is treated as "all defaults" by both the orchestrator and frontend

**Layer:** Backend — `tables/6_journey_map.xs`

---

**US-ACS-02 — Expose AI chat settings in the load bundle API**

**Story:** As the frontend, I want AI chat settings returned when loading a journey map bundle so that the chat panel can pre-populate before the first message is sent.

**Acceptance Criteria:**
- The `journey_map/load_bundle/{journey_map_id}` response includes the `ai_chat_settings` JSON field
- No additional API call is required to fetch chat settings
- A `null` value is treated as all defaults by the frontend
- No breaking change to the existing bundle response shape

**Layer:** Backend — `apis/journey_map/43_journey_map_load_bundle_journey_map_id_GET.xs` (no change required if schema update lands correctly)

---

**US-ACS-03 — Create a dedicated AI chat settings PATCH endpoint**

**Story:** As the frontend, I want a single endpoint to save AI chat settings so that user preference changes are persisted without affecting other journey map properties.

**Acceptance Criteria:**
- A PATCH endpoint at `journey_map/ai_settings/{journey_map_id}` accepts any subset of the five settings fields
- Only provided fields are written — existing values are preserved (partial update)
- `updated_at` is refreshed on every successful save
- Returns the updated `journey_map` record
- Validates enum values: `interview_style` ∈ `[formal, collaborative, rapid]`; `quality_gate` ∈ `[strict, balanced, permissive]`; `focus_mode` ∈ `[balanced, customer, operations, engineering]`
- Rejects unknown fields with a 400 input error

**Layer:** Backend — new file `apis/journey_map/journey_map_ai_settings_journey_map_id_PATCH.xs`

---

**US-ACS-04 — Inject AI chat settings into the orchestrator system prompt**

**Story:** As the AI agent, I want the user's AI chat settings injected into my context so that I adjust my interview style, quality enforcement, write confirmation behaviour, and focus area automatically — without the user needing to re-state their preferences each session.

**Acceptance Criteria:**
- The orchestrator (`52_journey_map_journey_map_id_ai_message_POST.xs`) reads `ai_chat_settings` from the loaded `$journey_map` record
- A new `## AI Behaviour Settings` section is appended to `$dynamic_context` when any setting is non-null and non-default
- The injected block includes plain-English directives per active setting:
  - `interview_style: rapid` → "Move quickly — skip pleasantries and probe only once per vague answer."
  - `quality_gate: permissive` → "Accept the user's answer as-is and write immediately — do not probe for more detail."
  - `quality_gate: strict` → "Never write a cell until the answer meets the quality gate — probe until specific."
  - `auto_confirm_writes: true` → "Set cell status to 'confirmed' (not 'draft') for all AI writes this session."
  - `focus_mode: customer` → "Prioritise customer lens rows when choosing which empty cell to ask about next."
  - `focus_mode: engineering` → "Prioritise engineering lens rows when choosing which empty cell to ask about next."
  - `focus_mode: operations` → "Prioritise internal and handoff lens rows when choosing which empty cell to ask about next."
- Null or default values produce no directive (no noise injected)
- Existing AI message flow is unaffected when `ai_chat_settings` is null

**Layer:** Backend — `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

---

**US-ACS-05 — Build the AI Chat Settings panel in the frontend**

**Story:** As a user, I want an AI Chat Settings panel accessible from the chat window header so that I can configure how the AI behaves for this journey map without leaving the workspace.

**Placement:** The gear icon lives in the **chat panel header** (upper-right corner of the right-side chat drawer), slotted into the existing `flex items-center gap-1` button row alongside the close `X` button — NOT in the Journey Settings panel (which is a separate left-side drawer about journey content, not AI behaviour).

```tsx
// webapp/protype-2/src/App.tsx — chat panel header, right-side button group
<div className="flex items-center gap-1">
  <button onClick={() => setIsAiSettingsOpen(true)} ...>
    <Settings className="w-4 h-4" />   {/* ← gear icon added here */}
  </button>
  <button onClick={() => setIsChatOpen(false)} ...>
    <X className="w-4 h-4" />           {/* ← existing close button */}
  </button>
</div>
```

**Acceptance Criteria:**
- A gear (`Settings`) icon is added to the chat panel header, to the left of the existing close `X` button
- Clicking the gear opens the AI Chat Settings panel (overlay or inner drawer within the chat panel)
- The panel displays all five settings with clear labels, descriptions, and their current values
- `Interview Style` renders as a 3-option segmented control: Formal | Collaborative | Rapid
- `Quality Gate` renders as a 3-option segmented control: Strict | Balanced | Permissive
- `Focus Mode` renders as a 4-option segmented control: Balanced | Customer | Operations | Engineering
- `Auto-Confirm AI Writes` and `Show AI Reasoning` render as labelled toggles
- Each setting includes a one-line description of what it does
- The panel is accessible but controls are disabled when no journey map is loaded
- The Journey Settings panel (left-side drawer) is unaffected — these are two separate panels with separate concerns

**Layer:** Frontend — `webapp/protype-2/src/App.tsx` + new `AiChatSettings` component

---

**US-ACS-06 — Load and display AI chat settings from the backend on startup**

**Story:** As a user reopening a journey map, I want my AI chat settings pre-applied so that I never have to re-configure the AI after returning to a session.

**Acceptance Criteria:**
- When the load bundle response arrives, `ai_chat_settings` is read and applied to local state
- The chat settings panel reflects the persisted values immediately on open
- Null fields fall back to their default values in the UI
- Settings state resets to defaults when a new or different journey map is loaded

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`, `webapp/protype-2/src/xano.ts`

---

**US-ACS-07 — Save AI chat settings changes to the backend**

**Story:** As a user, I want changes I make in the AI Chat Settings panel to be saved automatically so that my preferences are applied immediately and persist across sessions.

**Acceptance Criteria:**
- Each setting change triggers a PATCH to `journey_map/ai_settings/{journey_map_id}` with only the changed field
- A subtle saving indicator appears while the request is in flight
- Errors surface as an inline banner inside the settings panel — the panel does not close
- The updated settings are applied to the next AI message sent in the same session without a page reload
- `show_reasoning` preference is applied immediately to the message list (existing messages update in place)

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`, `webapp/protype-2/src/xano.ts`

---

**US-ACS-08 — Apply `show_reasoning` preference to the chat message list**

**Story:** As a user who has toggled off AI Reasoning, I want the thinking disclosure panels to be hidden from all messages — past and future — so the chat stays clean without me having to collapse each one manually.

**Acceptance Criteria:**
- When `show_reasoning` is `false`, the `ActivityPanel` reasoning section is not rendered for any message
- When `show_reasoning` is `true` (default), existing behaviour is unchanged
- Toggling the setting live updates all currently visible messages without a reload
- The setting does not suppress the tool-trace chip (cells read/written) — only the extended reasoning text

**Layer:** Frontend — `webapp/protype-2/src/App.tsx` → `ActivityPanel` component

---

### Recommended build order

```
US-ACS-01 (schema) → US-ACS-02 (bundle) → US-ACS-03 (PATCH endpoint) → US-ACS-04 (orchestrator injection)
→ US-ACS-05 (UI panel) → US-ACS-06 (load settings) → US-ACS-07 (save settings) → US-ACS-08 (reasoning toggle)
```

**Phase 1 — Backend (no UI needed to test):**
`US-ACS-01` → `US-ACS-02` → `US-ACS-03` → `US-ACS-04`

**Phase 2 — Frontend:**
`US-ACS-05` → `US-ACS-06` → `US-ACS-07` → `US-ACS-08`

### Architecture reference

```
Frontend AI Chat Settings panel
       │
       ├─ PATCH /journey_map/ai_settings/{id}   ← save changes
       └─ GET  /journey_map/load_bundle/{id}    ← load on startup

Orchestrator (ai_message POST)
       └─ reads journey_map.ai_chat_settings
          └─ injects ## AI Behaviour Settings block into $dynamic_context
                └─ Agent prompt adapts tone, quality gate, status, and focus
```
