# AI PM Agent Transparency — Test Simulation & Findings

## Test Methodology

**Dual-hat evaluation:**
1. 🧑‍💼 **User Hat** — Act as the user, send a message, state expectations BEFORE seeing the AI response
2. 🗺️ **Journey Map PM Hat** — Review the AI's tool calls, cell writes, and transparency output
3. 🎨 **UX PM Hat** — Review what the user actually sees in the UI — is the transparency useful?

---

## Scenario 1: First Message — "Help me map our employee onboarding process"

### 🧑‍💼 User Expectation
- AI should ask what my onboarding stages look like
- I expect it to orient itself (read the map) before responding
- I do NOT expect it to write anything yet — it doesn't know my process

### 🤖 Simulated AI Behavior

**Tool calls (predicted):**
1. `get_map_state` → reads full map (8 default stages × 10 lenses = 80 empty cells)
2. Agent reasons: "Map is 0% filled, all defaults. I need to understand the user's process first."
3. No write tools called.

**AI Reply:** "I see an empty journey map with 8 stages. Before we start filling it in, can you walk me through the key phases of your onboarding process? For example: what happens from the moment someone accepts an offer to when they're fully productive?"

**Tool trace returned:**
```json
[
  { "tool_name": "get_map_state", "tool_category": "read", "input_summary": "Full map: Employee Onboarding", "output_summary": "0 filled, 80 empty, 0 locked", "execution_order": 1 }
]
```

**Thinking:** "Map is completely empty with default stage names. I should not scaffold structure yet — I need to learn the user's actual process steps first. Will ask an open-ended question about their onboarding phases."

**Activity chip:** (nothing — no cells updated, no structure changed)

### 🗺️ Journey Map PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| AI read the map first | Yes | `get_map_state` called | ✅ |
| AI did NOT write any cells | Yes | No `update_cell`/`batch_update` called | ✅ |
| AI did NOT restructure | Yes | No `mutate_structure`/`scaffold_structure` called | ✅ |
| Tool trace has 1 entry | Yes | 1 read tool | ✅ |
| Reply asks about user's stages | Yes | Open-ended question about phases | ✅ |

**Verdict: PASS** ✅

### 🎨 UX PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| Activity chip visible? | No (nothing happened) | No chip shown | ✅ |
| Tool trace available on expand? | Yes — 1 read action | ❌ **GAP: `tool_trace` not wired to frontend** |
| Thinking available on expand? | Yes — reasoning visible | ❌ **GAP: `thinking` not wired to frontend** |

**Findings:**
- **GAP-01**: `PersistedAiConversationThread` interface missing `toolTrace` and `thinking` fields
- **GAP-02**: `sendAiMessage()` doesn't extract `tool_trace` or `thinking` from response
- **GAP-03**: No UI component for tool trace expand (Layer 2 frontend not built)
- **GAP-04**: No UI component for reasoning panel (Layer 3 frontend not built)

---

## Scenario 2: User describes stages — "We have: offer accepted, pre-boarding docs, first day, week 1 buddy program, 30-day check-in, 90-day review"

### 🧑‍💼 User Expectation
- AI should restructure the map to match my 6 stages
- AI should rename the default stages to my names
- AI should NOT start writing cell content yet — just the structure
- I want to see that the structure changed

### 🤖 Simulated AI Behavior

**Tool calls (predicted):**
1. `get_map_state` → reads current state (still 8 default stages, 80 empty cells)
2. `scaffold_structure` → bulk rename 6 stages + remove 2 extra stages in one call:
   ```json
   {
     "stage_operations": [
       {"action": "rename", "key": "s1", "label": "Offer Accepted"},
       {"action": "rename", "key": "s2", "label": "Pre-boarding Docs"},
       {"action": "rename", "key": "s3", "label": "First Day"},
       {"action": "rename", "key": "s4", "label": "Week 1 Buddy Program"},
       {"action": "rename", "key": "s5", "label": "30-Day Check-in"},
       {"action": "rename", "key": "s6", "label": "90-Day Review"},
       {"action": "remove", "key": "s7"},
       {"action": "remove", "key": "s8"}
     ]
   }
   ```
3. No cell writes.

**AI Reply:** "I've restructured your map to 6 stages: Offer Accepted → Pre-boarding Docs → First Day → Week 1 Buddy Program → 30-Day Check-in → 90-Day Review. Let's start filling it in. Who owns the 'Offer Accepted' stage?"

**Tool trace:**
```json
[
  { "tool_name": "get_map_state", "tool_category": "read", "input_summary": "Full map: Employee Onboarding", "output_summary": "0 filled, 80 empty, 0 locked", "execution_order": 1 },
  { "tool_name": "scaffold_structure", "tool_category": "structure", "input_summary": "6 renamed, 0 added, 2 removed stages", "output_summary": "6 stages, 10 lenses final", "execution_order": 2 }
]
```

**Activity chip:** `🏗️ Structure changed · 0% complete`

### 🗺️ Journey Map PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| AI used `scaffold_structure` (not 8 individual `mutate_structure` calls) | Yes | 1 scaffold call | ✅ |
| 6 stages renamed correctly | Yes | Labels match user input | ✅ |
| 2 extra stages removed | Yes | s7, s8 removed | ✅ |
| Cells auto-scaffolded (6×10 = 60) | Yes | 20 cells deleted (2 removed stages) | ✅ |
| AI did NOT write content | Yes | No write tools | ✅ |
| Tool trace has 2 entries | Yes | 1 read + 1 structure | ✅ |

**Verdict: PASS** ✅

**BUT — FINDING-01:** What if the agent calls `get_map_state` first and THEN `scaffold_structure`? That's 2 steps out of max 10. If the agent is smart, it could skip `get_map_state` since it received the dynamic context with fill summary already. Need to check if the agent is being wasteful with `get_map_state` calls when the dynamic context already provides orientation.

### 🎨 UX PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| Activity chip shows structure changed | Yes | `🏗️ Structure changed` | ✅ |
| Activity chip shows 0% complete | Yes | `0% complete` | ✅ |
| Frontend reloads stages/lenses | Yes | `structuralChanges.stages_changed = true` triggers `loadJourneyMapBundle` | ✅ |
| Tool trace shows scaffold_structure | Yes | ❌ **GAP-01 still open** |

**Findings:**
- Same GAP-01 through GAP-04 from Scenario 1
- **FINDING-01**: Agent may waste a step calling `get_map_state` when dynamic context already has map summary. Evaluate whether to make `get_map_state` optional when context is fresh.

---

## Scenario 3: Rich interview answer — "The HR coordinator sends the offer letter through DocuSign, the main pain point is that 40% of candidates take more than 3 days to sign, and the key metric we track is time-to-sign"

### 🧑‍💼 User Expectation
- AI should write to MULTIPLE cells from one answer (Description, Pain Point, Key Metric)
- I expect `batch_update` not 3 individual `update_cell` calls
- I expect the activity chip to show "3 cells updated"
- AI should ask about the NEXT area (owner? notifications?)

### 🤖 Simulated AI Behavior

**Tool calls (predicted):**
1. `batch_update` → writes 3 cells for "Offer Accepted" stage:
   ```json
   [
     {"stage_key": "s1", "lens_key": "description", "content": "HR coordinator sends offer letter via DocuSign for candidate signature."},
     {"stage_key": "s1", "lens_key": "painpoint", "content": "40% of candidates take >3 days to sign the offer letter."},
     {"stage_key": "s1", "lens_key": "keyvariable", "content": "Time-to-sign (target: <3 days)"}
   ]
   ```
2. `get_gaps` → checks what's still empty for this stage to decide next question

**AI Reply:** "Logged the DocuSign workflow, the signing delay pain point, and the time-to-sign metric for Offer Accepted. Who owns this stage — is it the HR coordinator, the hiring manager, or someone else?"

**Tool trace:**
```json
[
  { "tool_name": "batch_update", "tool_category": "write", "input_summary": "3 cells targeted", "output_summary": "3 applied, 0 skipped", "execution_order": 1 },
  { "tool_name": "get_gaps", "tool_category": "read", "input_summary": "Stage: s1", "output_summary": "7 gaps found", "execution_order": 2 }
]
```

**Activity chip:** `✏️ 3 cells updated · 5% complete`

### 🗺️ Journey Map PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| AI used `batch_update` (not 3 individual calls) | Yes | 1 batch call | ✅ |
| 3 cells written correctly | Yes | Description, Pain Point, Key Variable | ✅ |
| AI used `get_gaps` to decide next question | Yes | Checked stage gaps | ✅ |
| Content quality — specific, includes numbers | Yes | "40%", ">3 days" preserved | ✅ |
| Follow-up targets the next empty lens | Yes | Asks about owner (empty) | ✅ |

**Verdict: PASS** ✅

**FINDING-02:** The `batch_update` tool trace says "3 cells targeted" but doesn't say WHICH cells. The `input_summary` is too vague. A better input_summary would be: `"s1 × description, s1 × painpoint, s1 × keyvariable"`. This is important for the tool trace UX — users want to know WHAT was written, not just how many.

### 🎨 UX PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| Activity chip shows 3 cells updated | Yes | ✅ |
| Updated cells listed with labels | Expected | ❌ **GAP-05: Activity chip shows count but NOT which cells** |
| User can see stage × lens labels | Expected | ❌ **GAP-05 cont: `updatedCells` array exists in `MessageActivity` but not rendered** |

**Findings:**
- **FINDING-02**: `batch_update` and `update_cell` `input_summary` should list specific stage×lens pairs, not just counts
- **GAP-05**: `<ActivityChip />` shows counts but doesn't render the `updatedCells[]` array with stage/lens labels. Users need to see "✏️ Offer Accepted → Description, Pain Point, Key Metric" not just "✏️ 3 cells"

---

## Scenario 4: User asks a question — "What are all the pain points we've identified so far?"

### 🧑‍💼 User Expectation
- AI should read the pain point lens horizontally (across all stages)
- AI should list what's filled and what's missing
- AI should NOT write anything
- I want to see that it read a specific lens, not the whole map

### 🤖 Simulated AI Behavior

**Tool calls (predicted):**
1. `get_slice` (lens_key: "painpoint") → reads the pain point row across all 6 stages

**AI Reply:** "Here are the pain points identified so far: ① Offer Accepted — 40% of candidates take >3 days to sign. Stages 2–6 have no pain points yet. Want me to start exploring pain points for Pre-boarding Docs next?"

**Tool trace:**
```json
[
  { "tool_name": "get_slice", "tool_category": "read", "input_summary": "Row: painpoint (1 filled)", "output_summary": "Row: painpoint (1 filled)", "execution_order": 1 }
]
```

**Activity chip:** (nothing — no writes)

### 🗺️ Journey Map PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| AI used `get_slice` with lens_key (not `get_map_state`) | Yes | 1 targeted read | ✅ |
| AI listed filled pain points by stage | Yes | Shows stage 1 content | ✅ |
| AI identified missing pain points | Yes | "Stages 2–6 have no pain points" | ✅ |
| AI did NOT write anything | Yes | No write tools | ✅ |
| Token efficiency (slice vs full map) | ~800 tokens vs ~4200 | ✅ 81% reduction |

**Verdict: PASS** ✅

**FINDING-03:** The `get_slice` tool trace `output_summary` is identical to `input_summary`. This is because in the current implementation, both are set to the same `$slice_summary` variable. The output_summary should add value — e.g., "1 of 6 filled, 5 empty" instead of repeating the input.

### 🎨 UX PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| Activity chip hidden (no writes) | Yes | No chip | ✅ |
| Tool trace shows targeted read | Yes | ❌ **GAP-01 still open** |
| User can trust AI read the right data | Not verifiable without trace | ❌ **This is exactly why Layer 2 matters** |

**Findings:**
- **FINDING-03**: `get_slice` output_summary duplicates input_summary. Should differentiate: input = what was requested, output = what was found.
- **INSIGHT-01**: This scenario proves Layer 2 is critical — the user asked a question, the AI answered correctly, but the user has NO WAY to verify the AI read the right row. Trust deficit.

---

## Scenario 5: User locks a cell, then AI tries to write to it — "Actually, the time-to-sign metric is wrong. Change it to offer acceptance rate."

### 🧑‍💼 User Expectation
- User previously locked the "Key Variable" cell for "Offer Accepted" (via set_cell_status)
- AI should DETECT the lock and NOT overwrite it
- AI should explain that the cell is locked and ask user to unlock it
- Transparency should show the skip

### 🤖 Simulated AI Behavior

**Tool calls (predicted):**
1. `update_cell` (stage_key: "s1", lens_key: "keyvariable", content: "Offer acceptance rate")
   → Tool returns: `{ applied: false, skip_reason: "Cell is locked" }`

**AI Reply:** "I can't update the Key Variable cell for Offer Accepted — it's currently locked. If you'd like to change it, unlock the cell first, and I'll update it. Or you can edit it directly in the grid."

**Tool trace:**
```json
[
  { "tool_name": "update_cell", "tool_category": "write", "input_summary": "s1 × keyvariable", "output_summary": "Skipped: Cell is locked", "execution_order": 1 }
]
```

**Activity chip:** `⏭️ 1 skipped`

### 🗺️ Journey Map PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| AI attempted to write | Yes | `update_cell` called | ✅ |
| Tool respected the lock | Yes | `applied: false` | ✅ |
| AI explained the lock | Yes | Clear message | ✅ |
| Tool trace shows skip with reason | Yes | "Skipped: Cell is locked" | ✅ |
| Cell content was NOT changed | Yes | Lock enforced | ✅ |

**Verdict: PASS** ✅

### 🎨 UX PM Review

| Check | Expected | Actual | ✅/❌ |
|-------|----------|--------|------|
| Activity chip shows skip | Yes | ❌ **GAP-06: Activity chip has `cellsSkipped` hardcoded to 0** |
| Skip reason visible | Yes | ❌ **GAP-06 cont: No skip data flows from response** |
| User understands WHY it was skipped | Partially — AI reply explains | ✅ (via reply text) |

**Findings:**
- **GAP-06**: `cellsSkipped` in `MessageActivity` is hardcoded to 0 (`// TODO: wire skipped_updates when backend returns it`). The orchestrator's `skipped_updates` field needs to be consumed.
- **FINDING-04**: The `update_cell` trace correctly shows "Skipped: Cell is locked" which is excellent for Layer 2. But Layer 1 (activity chip) can't show this yet because it doesn't have skip data.

---

## Consolidated Findings

### 🔴 Critical Gaps (Must Fix for Layer 2 to Work)

| ID | Gap | Impact | Fix |
|----|-----|--------|-----|
| GAP-01 | `PersistedAiConversationThread` missing `toolTrace` and `thinking` fields | Layer 2 & 3 data never reaches frontend | Add fields to interface, extract from response in `sendAiMessage()` |
| GAP-02 | `sendAiMessage()` doesn't extract `tool_trace` or `thinking` from API response | Data is returned by backend but dropped by frontend | Map `response.tool_trace` → `toolTrace` and `response.thinking` → `thinking` |

### 🟡 Important Gaps (Should Fix for Good UX)

| ID | Gap | Impact | Fix |
|----|-----|--------|-----|
| GAP-03 | No `<ToolTrace />` expand component | Users can't see Layer 2 | Build expand/collapse component consuming `toolTrace[]` |
| GAP-04 | No `<ReasoningPanel />` component | Users can't see Layer 3 | Build expand/collapse component consuming `thinking` |
| GAP-05 | Activity chip shows counts not labels | Users see "3 cells" but not WHICH cells | Render `updatedCells[]` array with stage×lens labels |
| GAP-06 | `cellsSkipped` hardcoded to 0 | Skip events invisible to user | Wire `skipped_updates` from orchestrator response |

### 🟠 Tool Trace Quality Issues (Should Fix for Clarity)

| ID | Finding | Current | Better |
|----|---------|---------|--------|
| FINDING-01 | Agent may waste a step on `get_map_state` when context is fresh | Calls `get_map_state` every turn | Evaluate if dynamic context is sufficient; add instruction to skip when context has fresh summary |
| FINDING-02 | `batch_update` input_summary too vague | "3 cells targeted" | "s1 × description, s1 × painpoint, s1 × keyvariable" |
| FINDING-03 | `get_slice` output_summary = input_summary | "Row: painpoint (1 filled)" | input: "Row: painpoint" output: "1 of 6 filled, 5 empty" |
| FINDING-04 | Skip data path incomplete | Backend has it → Frontend drops it | Wire `skipped_updates` through entire path |

### 💡 Key Learnings

1. **Layer 1 is 80% there** — the data exists, the chip renders, but it's missing skip data and cell labels.
2. **Layer 2 backend is complete** — `agent_tool_log` table, all 10 tools log, orchestrator returns `tool_trace[]`. But the **frontend bridge is missing** (GAP-01, GAP-02).
3. **Layer 3 backend is complete** — `thinking_tokens: 1000`, thinking persisted in `agent_message`, returned in response. But **frontend bridge is missing** (same gaps).
4. **Tool trace quality matters** — the summaries need to be human-readable and specific. Generic counts ("3 cells") aren't useful. Stage×lens labels ARE useful.
5. **The dual-hat review is essential** — the Journey Map PM sees the tools working correctly, but the UX PM catches that the user sees NONE of it until the frontend gaps are closed.

---

## Corrective Actions (Priority Order)

### P1 — Wire Layer 2 & 3 to Frontend

**Action 1:** Update `PersistedAiConversationThread` to include:
```typescript
toolTrace: { tool_name: string; tool_category: string; input_summary: string; output_summary: string; execution_order: number }[];
thinking: string | null;
```

**Action 2:** Update `sendAiMessage()` to extract `tool_trace` and `thinking` from response.

**Action 3:** Update `MessageActivity` to include `toolTrace` and `thinking`, tag messages.

### P2 — Improve Activity Chip

**Action 4:** Render `updatedCells[]` labels in chip (expandable list of "Stage → Lens").

**Action 5:** Wire `skipped_updates` → `cellsSkipped` count + reasons.

### P3 — Improve Tool Trace Summaries

**Action 6:** `batch_update` input_summary → list each stage×lens pair.

**Action 7:** `get_slice` → separate input vs output summaries.

### P4 — Build Layer 2 & 3 UI Components

**Action 8:** `<ToolTrace />` expandable panel.

**Action 9:** `<ReasoningPanel />` expandable panel.

---

## Live API Test Results (actual Xano calls)

### Test Run: `node test_api.mjs`

**Step 1: Create draft map** → ✅ `Map ID: 65` created successfully.

**Step 2: Load bundle** → ✅ `8 stages, 10 lenses, 80 cells` returned correctly.

**Step 3: ai_message POST** → ❌ `500 — Unable to locate input: selected_cell.reference`

### Root Cause

The `ai_message` endpoint (API 52) requires a `selected_cell` input with a nested `reference` field. This is the cell the user currently has selected in the UI grid. The orchestrator uses it to provide context to the agent about where the user is focused.

This is **NOT optional** — it's a required input that the frontend sends automatically when the user clicks a cell, but API callers (tests, CLI, integrations) don't have a "selected cell."

### GAP-07: ai_message API not callable without UI context

The `ai_message` endpoint is **tightly coupled to the frontend** — it requires `selected_cell.reference` which only exists in the grid UI. This means:
- ❌ Can't test via standalone API scripts
- ❌ Can't integrate with other systems (Slack, email, CLI)
- ❌ Can't run automated tests without mocking UI state
- ❌ Playwright tests would need to click a cell first before sending a message

**Fix options:**
1. Make `selected_cell` optional — if not provided, agent just doesn't know what cell is focused (acceptable for interview/chat mode)
2. Add a separate `ai_message_headless` endpoint that strips UI-specific inputs
3. Default to a no-op selected_cell when not provided

### Playwright Test Status

Dev server running at `localhost:3002`. Browser automation not yet executed because:
1. The Playwright MCP server connection was failing (page not open)
2. Need to verify the app loads correctly before running UI tests
3. The API test failure means the full AI flow can't execute yet anyway — fixing GAP-07 is prerequisite

### Next steps for live testing

1. Fix GAP-07 (make `selected_cell` optional in the orchestrator)
2. Re-run `test_api.mjs` to validate tool_trace and thinking in responses
3. Open app in Playwright, navigate to a map, send a message, inspect DOM for activity chip rendering

---

## Architecture Learnings

### 🧠 Learning 1: Backend ≠ Frontend ≠ API contract

The backend tools work correctly in isolation. The orchestrator returns the right data. But:
- The **frontend doesn't consume** `tool_trace` or `thinking` yet (GAP-01/02)
- The **API contract** requires UI-specific inputs that API-only callers can't provide (GAP-07)
- The **activity chip renders** but is incomplete (GAP-05/06)

**Lesson:** Test at ALL three levels — tool unit tests, API integration tests, and UI tests. Each catches different problems.

### 🧠 Learning 2: Tool trace summaries are a UX product, not a debugging log

The tool trace isn't a developer debug log — it's a **user-facing product**. That means:
- "3 cells targeted" is a debug message. "Offer Accepted → Description, Pain Point, Key Metric" is a product message.
- `input_summary` and `output_summary` need to be designed like copy, not like log output.
- The trace needs to answer "What did you do?" not "What function did you call?"

**Lesson:** Treat tool trace summaries like microcopy. Design them from the user backward, not from the code forward.

### 🧠 Learning 3: The `selected_cell` coupling reveals a design assumption

The entire orchestrator was built assuming the user is always interacting through the grid UI. The `selected_cell` input:
- Drives the agent's context ("user is focused on Stage 3, Pain Point lens")
- Determines which cell gets updated on ambiguous writes
- Anchors the conversation to a spatial location

But interview mode and chat mode don't need spatial anchoring — the AI picks what to work on based on gaps, not user selection. This coupling creates friction for:
- Headless/API usage
- Mobile clients
- Voice interfaces
- Automated testing

**Lesson:** Separate "interview context" from "grid UI context." The agent should work in both spatially-anchored (cell selected) and free-roaming (no cell selected) modes.

### 🧠 Learning 4: The transparency stack is three separate products

```
Layer 1 (Activity Feed) → A STATUS indicator → "here's what happened"
Layer 2 (Tool Trace)    → An AUDIT LOG      → "here's how it happened"
Layer 3 (Reasoning)     → A THOUGHT PROCESS  → "here's why it happened"
```

Each layer serves a different user need:
- Layer 1: Reduces anxiety ("did it do something?")
- Layer 2: Builds trust ("did it do the RIGHT thing?")
- Layer 3: Enables learning ("can I understand its logic?")

**Lesson:** Ship Layer 1 fully before starting Layer 2. A bad Layer 1 undermines all higher layers. Users who can't trust "what happened" won't bother reading "how" or "why."
