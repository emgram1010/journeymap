## Smart AI Chat Settings Epic

### Why This Exists

A generic chatbot that asks polite questions is not the same as a world-class PM and UX practitioner who
specialises in journey mapping. The research is clear on what separates the best from the rest:

- **World-class PMs** chase specifics relentlessly, connect every friction point to a business outcome
  (frequency × severity × strategic importance), triangulate signal from noise, and hold assumptions
  with humility while probing until they have root causes — not symptoms.
- **World-class UX journey mapping specialists** map reality not aspirations, always capture the
  emotional arc at every touchpoint alongside the actions, apply laddering / 5-Whys to reach root
  pain (not just surface complaints), and treat every pain point as a decision input tied to a
  measurable business consequence.

Right now the agent's behaviour is entirely hardcoded. This epic surfaces **7 settings** that let
users dial the AI toward the specific PM/UX posture their session needs — from rapid coverage to
deep-dive strategic discovery.

---

### The 7 Settings

| # | Setting | Type | Default | What It Controls |
|---|---|---|---|---|
| 1 | **Interview Depth** | Enum (`strategic`, `discovery`, `rapid_capture`) | `discovery` | How deeply the AI works each stage before moving on. Strategic = full contextual understanding per stage. Discovery = balanced breadth + depth. Rapid Capture = coverage-first, minimal follow-up. |
| 2 | **Insight Standard** | Enum (`surface`, `discovery`, `deep_dive`) | `discovery` | How hard the AI probes before writing a cell. Surface = accepts stated answer. Discovery = one clarifying probe. Deep Dive = 5-Whys approach — root cause required, not symptom. |
| 3 | **Lens Priority** | Enum (`balanced`, `customer`, `operations`, `engineering`) | `balanced` | Which lens rows the agent prioritises in Interview Mode when deciding what to ask next. |
| 4 | **Emotional Mapping** | Boolean | `false` | When ON, the AI always probes for emotional state at every customer-facing touchpoint before moving on. |
| 5 | **Business Impact Framing** | Boolean | `false` | When ON, every pain point is framed with frequency + severity + downstream business consequence before being written. |
| 6 | **Auto-Confirm AI Writes** | Boolean | `false` | When OFF (default), AI-written cells land as `draft`. When ON, they land as `confirmed` immediately. |
| 7 | **Show AI Reasoning** | Boolean | `true` | Frontend-only. Whether the reasoning/thinking disclosure panel renders beneath AI messages. |

---

### Core Design Principle: Enrich, Don't Gate

**The AI's primary job is to populate the journey map. Every setting must support that — never block it.**

Settings control the *richness and depth* of what gets written, not *whether* the AI writes.
The AI should always be biased toward building the map forward. Probing questions happen
*after* a cell is written to enrich it — not *before* as a condition of writing it.

| Wrong | Right |
|---|---|
| "Don't write until you have root cause" | "Write what you have, then probe to deepen it" |
| "Don't write a pain point without business impact" | "Write the pain point, then ask the one follow-up that surfaces impact" |
| "Don't move on until emotional state is captured" | "Write the factual content, then ask about feelings before the next topic" |

**The user override is absolute and immune to all smart settings.** If the user says "just write
it", "build it", "that's all I have", "skip it", or makes any bulk population request — the AI
writes immediately and moves forward. No setting supersedes user intent.

---

### Agent Behaviour Directives Per Setting

These are the exact plain-English directives injected into `$dynamic_context` by the orchestrator:

**Interview Depth**
- `strategic` → "At every stage, fully understand context before moving on. Explore upstream triggers,
  downstream consequences, and cross-functional connections. Do not advance until the current stage has
  solid, specific coverage across all populated lens rows."
- `rapid_capture` → "Move quickly across the map. Accept first-level answers. One question per area,
  then advance. Prioritise breadth over depth — the user can revisit later."
- `discovery` → (default — no directive injected)

**Insight Standard**
- `surface` → "Accept the user's stated answer and write it immediately. Do not probe or challenge.
  Prioritise capturing everything given, however brief."
- `deep_dive` → "Write the cell with the best available content, then follow up with a probing
  question to deepen it toward root cause. Use a 5-Whys approach in your follow-ups — always write
  first, enrich second. For pain points aim to surface across turns: WHAT the friction is + WHO it
  affects + HOW OFTEN + DOWNSTREAM CONSEQUENCE — but gather these progressively, never as a gate
  before writing."
- `discovery` → (default — quality gate as defined in the base prompt)

**Emotional Mapping (when `true`)**
→ "Write the factual cell content first. Then, before moving to the next topic, ask one follow-up
  to surface the emotional dimension: 'How does the customer feel at this exact moment — frustrated,
  uncertain, relieved, trusting?' If the user provides emotional context alongside their answer,
  capture both in the same write turn. Never withhold writing while waiting for emotional data."

**Business Impact Framing (when `true`)**
→ "Write the pain point cell with whatever content is available. Then ask the one follow-up that
  surfaces the missing impact dimension — frequency, severity, or downstream consequence — and enrich
  the cell on the next turn. Target structure across turns: [What] affects [Who] [How often], causing
  [Business consequence]. Never withhold writing a pain point cell while waiting for this structure."

**Lens Priority**
- `customer` → "When choosing which empty area to explore next, prioritise lens rows with
  `actor_type: customer`."
- `operations` → "Prioritise internal actor and handoff lens rows."
- `engineering` → "Prioritise engineering lens rows."
- `balanced` → (default — no directive injected)

**Auto-Confirm AI Writes (when `true`)**
→ "Set cell `status` to `confirmed` (not `draft`) for all writes this session."

---

### Scope

- A new `smart_ai_settings` JSON column on the `journey_map` table
- A dedicated PATCH endpoint for saving smart AI settings
- Smart AI settings included in the load bundle response
- Orchestrator reads settings and injects per-setting behaviour directives into `$dynamic_context`
- Frontend Smart AI Settings panel in the chat header (gear icon, left of existing X button)
- `show_reasoning` toggle applied live to the `ActivityPanel` component

### Explicit Non-Goals

- Exposing raw `temperature`, `max_steps`, or model selection to users
- Per-message or per-turn overrides (settings are per-map, per-session)
- Merging with Journey Settings panel — that panel is about journey content, this is about AI posture
- Changing the base agent system prompt — directives are injected as context, not prompt rewrites

---

## Stories

---

**US-SACS-01 — Add `smart_ai_settings` column to the journey_map schema**

**Story:** As a product operator, I want the journey map record to store smart AI behaviour settings so
that a user's PM/UX interview posture persists across sessions and is available to the orchestrator
on every call.

**Acceptance Criteria:**
- A new `smart_ai_settings` column of type `json` is added to the `journey_map` table
- The column is nullable and optional — existing records are unaffected, `null` = all defaults
- The expected shape:
  ```json
  {
    "interview_depth": "discovery",
    "insight_standard": "discovery",
    "lens_priority": "balanced",
    "emotional_mapping": false,
    "business_impact_framing": false,
    "auto_confirm_writes": false,
    "show_reasoning": true
  }
  ```
- No migration required — `null` is treated as all defaults by both orchestrator and frontend

**Layer:** Backend — `tables/6_journey_map.xs`

---

**US-SACS-02 — Expose smart AI settings in the load bundle API**

**Story:** As the frontend, I want the smart AI settings returned with the journey map bundle on load
so the chat panel can pre-populate all controls before the first message is sent.

**Acceptance Criteria:**
- The `journey_map/load_bundle/{journey_map_id}` response includes the `smart_ai_settings` JSON field
- No additional API call is needed to fetch settings
- A `null` value is treated as all defaults by the frontend
- No breaking change to the existing bundle response shape

**Layer:** Backend — `apis/journey_map/43_journey_map_load_bundle_journey_map_id_GET.xs`
(no change required if schema update lands correctly — the field is returned automatically)

---

**US-SACS-03 — Create the smart AI settings PATCH endpoint**

**Story:** As the frontend, I want a dedicated endpoint to save smart AI settings so changes are
persisted independently of other journey map properties.

**Acceptance Criteria:**
- A PATCH endpoint at `journey_map/smart_ai_settings/{journey_map_id}` accepts any subset of the 7 fields
- Only provided fields are written — existing values are preserved (partial update)
- `updated_at` is refreshed on every successful save
- Returns the updated `journey_map` record
- Validates enum values:
  - `interview_depth` ∈ `[strategic, discovery, rapid_capture]`
  - `insight_standard` ∈ `[surface, discovery, deep_dive]`
  - `lens_priority` ∈ `[balanced, customer, operations, engineering]`
- Boolean fields: `emotional_mapping`, `business_impact_framing`, `auto_confirm_writes`,
  `show_reasoning`
- Rejects unknown fields with a 400 input error

**Layer:** Backend — new file
`apis/journey_map/journey_map_smart_ai_settings_journey_map_id_PATCH.xs`

---

**US-SACS-04 — Inject Interview Depth + Insight Standard directives into the orchestrator**

**Story:** As the AI agent, I want the user's Interview Depth and Insight Standard settings injected
into my context so I automatically adjust how broadly I cover each stage and how deeply I probe each
answer — matching the PM/UX posture the user has selected.

**Acceptance Criteria:**
- The orchestrator (`52_journey_map_journey_map_id_ai_message_POST.xs`) reads `smart_ai_settings`
  from the loaded `$journey_map` record
- A `## Smart AI Behaviour` section is appended to `$dynamic_context` when any non-default setting
  is present
- `interview_depth: strategic` injects:
  > "At every stage, fully understand context before moving on. Explore upstream triggers, downstream
  > consequences, and cross-functional connections. Do not advance until the current stage has solid,
  > specific coverage across all populated lens rows."
- `interview_depth: rapid_capture` injects:
  > "Move quickly across the map. Accept first-level answers. One question per area, then advance.
  > Prioritise breadth over depth."
- `insight_standard: surface` injects:
  > "Accept the user's stated answer and write it immediately. Do not probe or challenge."
- `insight_standard: deep_dive` injects:
  > "Write the cell with the best available content, then follow up with a probing question to deepen
  > it toward root cause. Use a 5-Whys approach in your follow-ups — always write first, enrich second.
  > For pain points, aim to surface across turns: WHAT the friction is + WHO it affects + HOW OFTEN +
  > DOWNSTREAM CONSEQUENCE — but gather these progressively, never as a gate before writing."
- `discovery` values for both produce no directive (default behaviour is unchanged)
- When `smart_ai_settings` is `null`, the orchestrator injects nothing and existing behaviour holds
- The user override is always honoured regardless of active settings — if the user says "just write
  it", "build it", "skip it", or "that's all I have", the AI writes immediately. No smart setting
  supersedes user intent.

**Layer:** Backend — `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

---

**US-SACS-05 — Inject Emotional Mapping + Business Impact Framing directives**

**Story:** As the AI agent, I want the Emotional Mapping and Business Impact Framing toggles to
activate specific world-class UX and PM behaviours — capturing emotional arcs and connecting every
pain point to a business outcome — when the user has enabled them.

**Acceptance Criteria:**
- When `emotional_mapping: true`, the orchestrator appends to the `## Smart AI Behaviour` section:
  > "Write the factual cell content first. Then, before moving to the next topic, ask one follow-up
  > to surface the emotional dimension: 'How does the customer feel at this exact moment — frustrated,
  > uncertain, relieved, trusting?' If the user provides emotional context alongside their answer,
  > capture both in the same write turn. Never withhold writing while waiting for emotional data."
- When `business_impact_framing: true`, the orchestrator appends:
  > "Write the pain point cell with whatever content is available. Then ask the one follow-up that
  > surfaces the missing impact dimension — frequency, severity, or downstream consequence — and enrich
  > the cell on the next turn. Target structure across turns: [What] affects [Who] [How often], causing
  > [Business consequence]. Never withhold writing a pain point cell while waiting for this structure."
- Both toggles are independent — either, both, or neither can be active
- When both are false (default), nothing is injected
- The user override is always honoured regardless of which toggles are active — if the user says
  "just write it" or makes any bulk population request, the AI writes immediately without follow-up

**Layer:** Backend — `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

---

**US-SACS-06 — Inject Lens Priority + Auto-Confirm Writes directives**

**Story:** As the AI agent, I want the Lens Priority and Auto-Confirm Writes settings applied so the
agent focuses on the right rows and writes cells with the correct confirmation status for this session.

**Acceptance Criteria:**
- `lens_priority: customer` injects:
  > "When choosing which empty area to explore next, prioritise lens rows with `actor_type: customer`."
- `lens_priority: operations` injects:
  > "Prioritise internal actor and handoff lens rows when deciding what to ask about next."
- `lens_priority: engineering` injects:
  > "Prioritise engineering lens rows when deciding what to ask about next."
- `lens_priority: balanced` (default) — no directive injected
- `auto_confirm_writes: true` injects:
  > "Set cell `status` to `confirmed` (not `draft`) for all AI writes this session."
- `auto_confirm_writes: false` (default) — no directive injected (agent uses `draft` per base prompt)
- All directives are appended into the same `## Smart AI Behaviour` section as SACS-04 and SACS-05

**Layer:** Backend — `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

---

**US-SACS-07 — Build the Smart AI Settings panel in the frontend**

**Story:** As a user, I want a Smart AI Settings panel accessible from the chat window header so I
can set the AI's PM/UX interview posture for this journey map without leaving the workspace.

**Placement:** Gear icon in the **chat panel header** (upper-right corner of the right-side chat
drawer), to the left of the existing close `X` button — not in the Journey Settings panel.

```tsx
// webapp/protype-2/src/App.tsx — chat panel header, right-side button group
<div className="flex items-center gap-1">
  <button onClick={() => setIsSmartAiSettingsOpen(true)} ...>
    <Settings className="w-4 h-4" />   {/* ← gear icon */}
  </button>
  <button onClick={() => setIsChatOpen(false)} ...>
    <X className="w-4 h-4" />           {/* ← existing close button */}
  </button>
</div>
```

**Acceptance Criteria:**
- A gear (`Settings`) icon is added in the chat panel header, left of the existing `X` close button
- Clicking the gear opens the Smart AI Settings panel as an overlay within the chat drawer
- **Interview Depth** renders as a 3-option segmented control: Strategic | Discovery | Rapid Capture
  - Description shown: "How deeply the AI works each stage before moving on"
- **Insight Standard** renders as a 3-option segmented control: Surface | Discovery | Deep Dive
  - Description shown: "How hard the AI probes before writing — Surface accepts, Deep Dive applies
    5-Whys to reach root cause"
- **Lens Priority** renders as a 4-option segmented control: Balanced | Customer | Operations | Engineering
  - Description shown: "Which rows the AI focuses on first in Interview Mode"
- **Emotional Mapping** renders as a labelled toggle
  - Description shown: "Always probe for customer emotional state at each touchpoint"
- **Business Impact Framing** renders as a labelled toggle
  - Description shown: "Frame every pain point with frequency, severity, and business consequence"
- **Auto-Confirm AI Writes** renders as a labelled toggle
  - Description shown: "AI-written cells land as Confirmed (not Draft)"
- **Show AI Reasoning** renders as a labelled toggle
  - Description shown: "Show the AI's thinking process beneath each message"
- All controls include a tooltip or one-line description explaining the PM/UX behaviour it activates
- Controls are disabled (with a clear message) when no journey map is loaded
- The Journey Settings panel (left-side drawer) is entirely unaffected

**Layer:** Frontend — `webapp/protype-2/src/App.tsx` + new `SmartAiSettings` component

---

**US-SACS-08 — Load and display smart AI settings from the backend on startup**

**Story:** As a user reopening a journey map, I want my Smart AI Settings pre-applied so the AI
immediately adopts the right PM/UX posture without me needing to re-configure it each session.

**Acceptance Criteria:**
- When the load bundle response arrives, `smart_ai_settings` is read and applied to local state
- The Smart AI Settings panel reflects persisted values immediately on open
- `null` fields fall back to their default values in the UI (no "null" text shown)
- Settings state fully resets to defaults when a different journey map is loaded

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`, `webapp/protype-2/src/xano.ts`

---

**US-SACS-09 — Save smart AI settings changes to the backend**

**Story:** As a user, I want changes in the Smart AI Settings panel saved immediately so my
preferences are applied to the next message without a page reload.

**Acceptance Criteria:**
- Each setting change triggers a PATCH to `journey_map/smart_ai_settings/{journey_map_id}` with only
  the changed field
- A subtle saving indicator appears while the request is in flight
- Errors surface as an inline banner inside the settings panel — the panel does not close on error
- Updated settings are active for the next AI message in the same session with no reload required
- `show_reasoning` change is applied immediately to all visible messages (live toggle)

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`, `webapp/protype-2/src/xano.ts`

---

**US-SACS-10 — Apply `show_reasoning` toggle live to the chat message list**

**Story:** As a user who has disabled AI Reasoning, I want the thinking disclosure panels hidden from
all messages — past and future — immediately on toggle, so the chat stays clean without manual
collapse of each bubble.

**Acceptance Criteria:**
- When `show_reasoning` is `false`, the `ActivityPanel` reasoning/thinking text is not rendered for
  any message (existing or new)
- When `show_reasoning` is `true` (default), existing behaviour is unchanged
- Toggling live updates all currently visible messages without a page reload
- The tool-trace chip (cells read/written summary) is NOT suppressed — only the extended reasoning
  text block is hidden
- State is restored correctly when the user navigates back to the same map

**Layer:** Frontend — `webapp/protype-2/src/App.tsx` → `ActivityPanel` component

---

### Recommended Build Order

```
US-SACS-01 → US-SACS-02 → US-SACS-03 → US-SACS-04 → US-SACS-05 → US-SACS-06
→ US-SACS-07 → US-SACS-08 → US-SACS-09 → US-SACS-10
```

**Phase 1 — Backend (fully testable without any frontend work):**
`US-SACS-01` (schema) → `US-SACS-02` (bundle) → `US-SACS-03` (PATCH endpoint) →
`US-SACS-04` (depth + insight directives) → `US-SACS-05` (emotional + impact directives) →
`US-SACS-06` (lens + confirm directives)

**Phase 2 — Frontend:**
`US-SACS-07` (panel UI) → `US-SACS-08` (load) → `US-SACS-09` (save) → `US-SACS-10` (reasoning toggle)

---

### Architecture Reference

```
Smart AI Settings panel (gear icon, chat header upper-right)
       │
       ├─ PATCH /journey_map/smart_ai_settings/{id}   ← per-change save
       └─ GET  /journey_map/load_bundle/{id}          ← pre-populate on startup

Orchestrator (POST /journey_map/{id}/ai_message)
       └─ reads journey_map.smart_ai_settings
          └─ builds ## Smart AI Behaviour section in $dynamic_context
                ├─ Interview Depth directive      (SACS-04)
                ├─ Insight Standard directive     (SACS-04)
                ├─ Emotional Mapping directive    (SACS-05)
                ├─ Business Impact directive      (SACS-05)
                ├─ Lens Priority directive        (SACS-06)
                └─ Auto-Confirm Writes directive  (SACS-06)

Agent (Journey Map Assistant)
       └─ reads $dynamic_context
          └─ adopts PM/UX posture for the session
                ├─ Interview depth (strategic / rapid / default)
                ├─ Insight probing (5-Whys / surface / default)
                ├─ Emotional arc capture (on/off)
                ├─ Business impact framing (on/off)
                ├─ Lens row priority focus
                └─ Cell write confirmation status

show_reasoning toggle
       └─ Frontend only — controls ActivityPanel rendering, never sent to API
```

### What Each Setting Unlocks (PM/UX Behaviour Map)

| Setting | Off / Default | On / Non-default |
|---|---|---|
| Interview Depth: Strategic | Balanced coverage | Mirrors a senior PM who won't leave a stage until it's understood |
| Interview Depth: Rapid Capture | Balanced coverage | Sprint-style — surface the whole map fast, refine later |
| Insight Standard: Deep Dive | One clarifying probe | Full 5-Whys laddering — root cause, not symptom |
| Insight Standard: Surface | One clarifying probe | Capture-only — records what's said, no challenge |
| Emotional Mapping | Skips emotional arc | UX specialist mode — feelings captured at every customer touchpoint |
| Business Impact Framing | Records pain point as stated | PM mode — every pain point tied to frequency × severity × consequence |
| Auto-Confirm | Cells land as Draft | Cells land as Confirmed — use when the user trusts AI output immediately |
| Show Reasoning | Reasoning panel visible | Reasoning hidden — cleaner chat for users who don't need transparency layer |
