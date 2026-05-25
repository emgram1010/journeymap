# Actor-to-AI-Agent Conversion Epic

**Status:** Planning
**Goal:** Give users a structured, guided workflow to convert any actor row on a journey map into a deployed AI agent spec — including sub-journey creation, map linking, actor type promotion, and 12-field specification.

---

## Context

Today an actor on a journey map (e.g. "Route Planner", "Dispatch", "Driver") holds high-level, human-readable content describing what that role does at each stage. Converting that actor into an AI agent means more than flipping a field — it requires:

1. A **detailed sub-journey map** for that actor's process (the AI's operating spec)
2. A **`sub_journey` link** connecting the main map cell to that sub-journey
3. **Promoting the actor type** to `ai_agent` on the main map
4. **Filling the 12 structured AI agent fields** per stage on the main map (confidence threshold, escalation logic, decision output, etc.)

Without all four, the agent spec is incomplete and not ready for the Automation Bridge (Epic AB-4).

### Why a sub-journey is required

The main journey map holds happy-path, high-level content. It cannot capture the depth of decisions, exceptions, and data flows an AI agent needs to operate. The sub-journey is the agent's full operating manual — its own stages, its own exceptions, its own handoff points. The main map cell becomes a delegation point; the sub-journey is what executes.

---

## Existing Architecture (Do Not Break)

- `journey_lens.actor_type` — enum includes `ai_agent`; template `ai-agent-v1` already scaffolds 12 fields
- `journey_link` table — `(source_cell, target_map)` unique; `link_type: sub_journey` is the correct type here
- `POST /journey_architecture/{id}/link` — creates the link (both maps must belong to same architecture)
- `update_actor_cell_fields` tool — accepts all 12 `ai_agent` field keys per cell
- `update_actor_identity` tool — sets `persona_description`, `primary_goal`, `standing_constraints` on lens
- `link_map` MCP tool — **planned (Epic LM-1, not yet built)** — required for Step 2 of this flow
- Orchestrator agent: `agents/6_journey_map_orchestrator.xs` — future runtime consumer of the linked graph

---

## Priority Stack

```
🔴 HIGH   Epic-A2A-1   Sub-Journey Creation Wizard
🔴 HIGH   Epic-A2A-2   Actor Type Promotion Flow
🟡 MED    Epic-A2A-3   12-Field AI Agent Spec Assistant
🟡 MED    Epic-A2A-4   Conversion Completeness Validator
```

---

## Epic A2A-1 — Sub-Journey Creation Wizard

### US-A2A-01 — Trigger: "Convert to AI Agent" action on actor lens

**Story:** As a user, when I right-click or open the context menu on an actor lens row, I want a "Convert to AI Agent" option that launches a guided conversion flow.

**Entry point:** Actor lens header context menu (or lens settings panel)
**Gate:** Actor must NOT already be `actor_type: ai_agent`

**Acceptance Criteria:**
- [ ] "Convert to AI Agent" appears in actor lens context menu for all non-`ai_agent` actor types
- [ ] Clicking it opens a conversion wizard modal (does not immediately change anything)
- [ ] Wizard shows the actor name, current type, and a summary of what the conversion entails
- [ ] User can cancel at any point before Step 4 with no changes made

---

### US-A2A-02 — Wizard Step 1: Create or select sub-journey map

**Story:** As a user, I want to either create a new sub-journey map for this actor's detailed process or link to an existing map in the same architecture.

**Input options:**
- Create new: provide a title (pre-filled: `"{Actor Label} — Detailed Process"`)
- Select existing: dropdown of maps in the same architecture (excluding the current map)

**Acceptance Criteria:**
- [ ] Pre-filled title is editable
- [ ] New map is created in the same `journey_architecture` as the source map
- [ ] Existing map selector shows all maps in the architecture except the source map
- [ ] Selected/created map ID is carried through to Step 2

---

### US-A2A-03 — Wizard Step 2: Link sub-journey to source cell

**Story:** As a user, I want the wizard to wire the `sub_journey` link from the correct cell on the main map to the sub-journey map I just created or selected.

**Logic:**
- Source cell: the cell at the actor's lens row × the stage where the AI agent is most active (user selects stage from dropdown, or "all stages" creates one link per stage)
- Link type: always `sub_journey`
- Calls `link_map` MCP tool internally

**Dependency:** Requires Epic LM-1 (`link_map` tool) to be complete.

**Acceptance Criteria:**
- [ ] User selects which stage cell(s) to anchor the link from
- [ ] Link is created via `link_map` with `link_type: sub_journey`
- [ ] If `(source_cell, target_map)` already exists, wizard shows error and skips duplicate
- [ ] `publish_map` is called on source map after link creation

---

## Epic A2A-2 — Actor Type Promotion Flow

### US-A2A-04 — Wizard Step 3: Promote actor type to `ai_agent`

**Story:** As a user, I want the wizard to promote the actor lens from its current type to `ai_agent`, applying the `ai-agent-v1` template and scaffolding the 12 fields.

**Logic:**
- Calls `PATCH /journey_lens/actor_fields/{lens_id}` with `actor_type: "ai_agent"`, `template_key: "ai-agent-v1"`
- Scaffolds 12 `actor_fields` keys on all existing cells for this lens (all set to `null` initially)
- Preserves existing cell `content` text — only the `actor_fields` JSON is scaffolded, not overwritten

**Acceptance Criteria:**
- [ ] Lens `actor_type` updated to `ai_agent`
- [ ] All 12 field keys present on every cell for this lens after promotion
- [ ] Existing `content` text on cells is preserved
- [ ] Lens badge in UI updates to show AI agent indicator

---

## Epic A2A-3 — 12-Field AI Agent Spec Assistant

### US-A2A-05 — Wizard Step 4: AI-assisted field pre-fill

**Story:** As a user, I want the wizard to use the existing cell content on the actor row (from the main map) plus any sub-journey map content to pre-fill the 12 AI agent fields as a starting draft — so I'm not starting from blank.

**Logic:**
- Read existing `content` from each cell on the promoted actor row
- Read sub-journey map summary if available
- Call Journey Map Assistant agent to infer draft values for each of the 12 fields
- Present as editable suggestions (not auto-saved)

**Acceptance Criteria:**
- [ ] Pre-fill is offered as suggestions — user must confirm before saving
- [ ] Each field shows confidence indicator (high / medium / low based on source material available)
- [ ] User can edit any field before confirming
- [ ] Saving calls `update_actor_cell_fields` for each cell

---

## Epic A2A-4 — Conversion Completeness Validator

### US-A2A-06 — Completeness check on AI agent lenses

**Story:** As a user, I want to see a completeness indicator on any `ai_agent` lens row that shows how many of the 12 required fields are filled vs. empty — so I know which agents are spec-complete vs. draft.

**Display:** Progress bar or field count badge on the lens header (e.g. "7/12 fields")
**Threshold for "ready":** `confidence_threshold`, `escalation_logic`, and `decision_output` must all be non-null

**Acceptance Criteria:**
- [ ] Lens header shows filled field count for `ai_agent` rows
- [ ] Badge turns green when the 3 critical fields are filled
- [ ] Badge shows amber when partially filled, red when all empty
- [ ] Clicking badge opens the cell detail panel for that stage

---

## Conversion Flow Summary

```
User triggers "Convert to AI Agent" on actor lens
    → Step 1: Create or select sub-journey map
    → Step 2: Wire sub_journey link (source cell → sub-journey map)
    → Step 3: Promote actor_type to ai_agent (scaffold 12 fields)
    → Step 4: AI-assisted pre-fill of 12 fields (draft, confirm to save)
    → Completeness badge appears on lens header
        → Sub-journey map opens for detailed editing
            → Automation Bridge (Epic AB-4) — future runtime
```

---

## Dependencies

| Dependency | Status |
|---|---|
| `link_map` MCP tool (Epic LM-1) | Planning — blocks US-A2A-03 |
| `journey_link` table + link endpoint | ✅ Complete |
| `ai_agent` template + 12 fields | ✅ Complete |
| `update_actor_cell_fields` tool | ✅ Complete |
| Automation Bridge (Epic AB-4) | Future — runtime consumer |

---

## Non-Goals

- Automated runtime execution of the agent (that is Epic AB-4)
- Reverse conversion (AI agent back to human actor)
- Cross-architecture sub-journey links
- Bulk conversion of multiple actors at once (v1 is one actor at a time)
