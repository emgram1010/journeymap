# Epic — AI Builder Reliability & Observability

**Epic goal:** Fix the four confirmed bugs causing incomplete/slow journey map builds, and add a
Debug Mode toggle + per-phase build log panel so that any future failure can be diagnosed in
seconds from a map ID — no guesswork, no verbal description of symptoms.

---

## Context & Motivation

The AI journey map builder produces unreliable results due to four compounding bugs:

1. **Turn 0 dead zone** — build requests send the user's raw text as Turn 0 instead of jumping
   straight to the scaffold phase prompt, burning 60-90s before anything visible happens.
2. **Stall detection fires on scaffold/identity** — the stall counter increments when
   `cells_written == 0`, but scaffold (phase 0) and identity (phase 1) write zero cells by
   design. Two consecutive "stall" turns exits the build after only 2 phases.
3. **build_full missing system context** — the server-side build loop called `ai.agent.run`
   with no system message, so the agent had no `journey_map_id`, `conversation_id`, or
   `turn_id` and called zero tools. *(Partially fixed this session — needs integration test.)*
4. **Phase prompts too permissive** — agent occasionally over-reaches into adjacent phases
   (e.g. description phase also attempts to fill customer cells), corrupting dependency order.

Beyond bugs, there is zero visibility into what the agent did during a build. Diagnosing an
issue requires verbal description + guesswork. The existing `agent_tool_log` and
`agent_turn_log` tables capture everything — they just aren't surfaced anywhere useful.

**Debug Mode toggle:** Yes — implement as a persistent UI toggle (not just `?debug=1`), stored
in `localStorage`. Power users and developers flip it on when something looks wrong; it reveals
per-phase tool call detail without cluttering the default experience.

---

## Dependencies

- `agent-debug-logging-epic.md` — US-DBG-01 (tool logs API) and US-DBG-02 (step limit warning)
  must be complete before US-ARO-05 and US-ARO-06 can ship.
- `apis/journey_map/81_journey_map_journey_map_id_build_full_POST.xs` — bug fixes land here.
- `webapp/protype-2/src/App.tsx` — Turn 0 fix and debug toggle land here.

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Debug mode activation | `localStorage` toggle in chat header | Persists across refreshes; no URL param required; invisible to normal users |
| 2 | Stall exclusion strategy | Exclude phases 0 and 1 from stall counter entirely | They are structural phases — 0 cells written is expected and correct |
| 3 | Phase log visibility | Always show phase summary after a build (not debug-only) | Phase results are useful to all users, not just developers |
| 4 | Tool call detail | Debug mode only | Too granular for general use; surfaced on demand |
| 5 | Diagnostic workflow | Map ID + token → I pull logs directly | Eliminates verbal symptom descriptions; precise root cause in seconds |

---

## Vocabulary

| Term | Definition |
|---|---|
| **Stall** | Two consecutive turns where `cells_written == 0` — triggers early loop exit |
| **Structural phase** | Phases 0 (scaffold) and 1 (identity) — write zero cells by design, must be excluded from stall detection |
| **Debug Mode** | UI toggle that reveals per-phase tool call detail, step limit warnings, and turn IDs |
| **Phase log panel** | Post-build summary showing per-phase status, tool count, and cells written |
| **Step limit warning** | Flag set when agent used ≥ 18 of 20 allowed steps — indicates likely truncation |
| **Manual chat path** | Single-turn `ai_message` call triggered by a user typing a scoped request ("fill descriptions") — distinct from the 8-phase build loop |
| **Actor type context** | The `actor_type` field on each lens, required for the agent to pick the correct write tool per row |
| **Scope fence** | An explicit instruction in a prompt bounding the agent to a single lens or stage — prevents bleed into adjacent rows |

---

## Priority Stack

| Story | Title | Priority |
|---|---|---|
| US-ARO-01 | Fix Turn 0 dead zone | 🔴 HIGH |
| US-ARO-02 | Fix stall detection for structural phases | 🔴 HIGH |
| US-ARO-03 | Integration test build_full system context | 🔴 HIGH |
| US-ARO-04 | Tighten phase prompts — add hard scope fences | 🟡 MEDIUM |
| US-ARO-05 | Phase build log panel (always visible) | 🟡 MEDIUM |
| US-ARO-06 | Debug Mode toggle + tool call detail panel | 🟡 MEDIUM |
| US-ARO-07 | Diagnostic workflow — map ID log pull | 🟢 LOW |
| US-ARO-08 | Fix manual chat partial build reliability | 🔴 HIGH |
| US-ARO-09 | Fix fill counter — include actor_fields data | 🔴 HIGH |

---

## Implementation Sequence

```
US-ARO-01 (Turn 0 fix)
US-ARO-02 (stall fix)        ← both are <10 lines each, do together
US-ARO-03 (integration test) ← verify build_full context fix end-to-end
US-ARO-08 (manual chat fix)  ← fix single-turn partial builds while build_full is being verified
US-ARO-09 (fill counter fix) ← fix cells_filled / progress_percentage to count actor_fields
US-ARO-04 (phase prompts)    ← tighten after build is confirmed working
US-ARO-05 (phase log panel)  ← requires DBG-01 complete
US-ARO-06 (debug toggle)     ← requires DBG-01 + DBG-02 complete
US-ARO-07 (diagnostic docs)  ← document the workflow, no code change
```

---

## Stories

---

### US-ARO-01 — Fix Turn 0 dead zone

**Story:** As a user who asks the AI to build a journey map, I want the build to start
immediately on the scaffold phase — not waste 60-90s processing my raw message first.

**File:** `webapp/protype-2/src/App.tsx` — `handleSendMessage`

**Current behaviour:**
```js
const messageText = currentPhase ? currentPhase.prompt : inputText.trim();
// isBuildRequest is true but messageText is still the raw user input on Turn 0
```

**Fix:**
```js
const isBuildRequest = !isContinuation && !isChatMode && BUILD_REQUEST_REGEX.test(inputText.trim());
const messageText = isContinuation
  ? BUILD_PHASES[buildPhaseIndexRef.current].prompt
  : isBuildRequest
    ? BUILD_PHASES[0].prompt   // jump straight to scaffold
    : inputText.trim();
```

**Acceptance Criteria:**
- When `BUILD_REQUEST_REGEX` matches, the first message sent to the agent is `BUILD_PHASES[0].prompt`
- The user's raw text is still shown optimistically in the chat (unchanged)
- Progress indicator moves off 0% after the first HTTP response, not the second
- Non-build messages are unaffected

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`

---

### US-ARO-02 — Fix stall detection for structural phases

**Story:** As the build loop, I should not count scaffold or identity turns as stalls when they
write zero cells — that is their expected behaviour.

**File:** `apis/journey_map/81_journey_map_journey_map_id_build_full_POST.xs`

**Current behaviour:**
```xs
if ($turn_cells_written == 0) {
  $stall_count += 1   // ← fires on scaffold (phase 0) and identity (phase 1)
}
// stall_count >= 2 → loop exits after only 2 phases
```

**Fix:** Only increment stall counter for fill phases (index ≥ 2):
```xs
conditional {
  if ($turn_cells_written == 0 && $loop_idx >= 2) {
    var.update $stall_count { value = $stall_count + 1 }
  }
  else {
    var.update $stall_count { value = 0 }
  }
}
```

**Acceptance Criteria:**
- Scaffold (index 0) and identity (index 1) never increment `stall_count`
- Stall detection still works correctly for fill phases (index 2–6)
- Build loop runs all 8 phases when no genuine stall occurs
- `tool_trace_summary` response correctly reflects per-phase cells_written

**Layer:** Backend — `apis/journey_map/81_..._build_full_POST.xs`

---

### US-ARO-03 — Integration test build_full system context

**Story:** As a developer, I want confirmed evidence that the system context fix (injecting
`journey_map_id`, `conversation_id`, `turn_id` per turn) results in the agent calling tools
on a real map — not just passing a code review.

**Test:** Call `POST /journey_map/{id}/build_full`, then call `GET /journey_map/{id}/turn-logs`.

**Acceptance Criteria:**
- Every phase turn shows `tool_count >= 1` in turn logs
- Scaffold phase shows `tool_count >= 1` (scaffold_structure called)
- No phase shows `status: empty_reply`
- Map bundle after build shows stages renamed + lenses added + cells filled
- Document actual turn log output in a comment block at the top of `81_build_full.xs`

**Layer:** Backend integration test — no code change if fix is confirmed working

---

### US-ARO-04 — Tighten phase prompts — hard scope fences

**Story:** As the AI builder, I should be explicitly blocked from performing adjacent phase
work so that dependency order is always respected.

**File:** `apis/journey_map/81_..._build_full_POST.xs` + `webapp/protype-2/src/App.tsx`

**Changes:** Append a hard fence to each fill phase prompt:
```
[BUILD_PHASE:description] Fill the Description lens only. Use batch_update only.
DO NOT touch any other lens. DO NOT call scaffold_structure. DO NOT call update_actor_cell_fields.
```

**Acceptance Criteria:**
- Description phase tool logs show only `batch_update` calls
- Customer phase tool logs show only `update_actor_cell_fields` calls
- No cross-phase tool calls appear in any turn log
- Prompts updated in both `build_full` (server) and `BUILD_PHASES` array (frontend)

**Layer:** Backend + Frontend — prompt strings only, no logic change

---

### US-ARO-05 — Phase build log panel (always visible after build)

**Story:** As a user, I want to see a per-phase summary after a build completes so I know
exactly what each phase did without reading raw JSON.

**File:** `webapp/protype-2/src/App.tsx`

**UI spec:**
- Appears as a collapsible section below the final build completion message
- Always visible (not debug-mode-only)
- Title: `Build Summary — {N} phases, {M} cells filled`
- Table columns: `Phase | Status | Tools Called | Cells Written`
- Status icons: ✅ filled cells, ⚠️ step limit warning, ❌ 0 tools called
- Data source: `tool_trace_summary` already returned in `build_full` response

**Acceptance Criteria:**
- Panel renders after every completed build (complete, partial, or stalled)
- Each of the 8 phases appears as a row
- Phases with `tools_called: 0` show ❌ status
- Phases with `step_limit_warning: true` show ⚠️ status
- Panel is collapsed by default, expands on click

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`

---

### US-ARO-06 — Debug Mode toggle + tool call detail panel

**Story:** As a developer or power user troubleshooting a build, I want to flip a Debug Mode
toggle that reveals per-phase tool call detail, turn IDs, and step limit warnings — without
cluttering the default experience for normal users.

**File:** `webapp/protype-2/src/App.tsx`

**Toggle behaviour:**
- Gear/bug icon in chat header (right side, next to close button)
- State stored in `localStorage` key `emgram_debug_mode`
- Persists across page refreshes
- Visual indicator: header badge `DEBUG` in amber when active

**Debug mode reveals (per AI message):**
- Turn ID (copyable — for use with log pull diagnostic)
- `🔧 Debug — {N} tool calls` expandable row beneath ActivityChip
- Tool call table: `# | tool_name | input_summary | output_summary`
- Amber highlight on rows where `output_summary` starts with "Skipped"
- `⚠ Step limit warning` banner when `tool_count >= 18`
- Fetches `GET /journey_map/{id}/tool-logs?turn_id={turn_id}` on expand (lazy)

**Acceptance Criteria:**
- Toggle is invisible / has no effect in normal mode
- Debug panel is only shown when `emgram_debug_mode === true` in localStorage
- Tool log fetch is lazy (only on panel expand, not on message render)
- Skipped cells visually distinct (amber row)
- Step limit warning banner shown when applicable
- Turn ID is copyable with one click

**Requires:** US-DBG-01 (tool logs API) complete

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`

---

### US-ARO-07 — Diagnostic workflow documentation

**Story:** As a developer working with Augment Agent to debug a build issue, I want a defined
workflow so that providing a map ID + auth token gives me full diagnostic information
immediately — no verbal symptom descriptions needed.

**Diagnostic call sequence:**
```
1. GET /journey_map/{id}/turn-logs
   → which phases ran, tool counts, step limit warnings, status per turn

2. GET /journey_map/{id}/tool-logs?turn_id={turn_id_from_step_1}
   → per-tool: what was called, what was passed, what was returned

3. GET /journey_map/load_bundle/{id}
   → current map state: stage labels, lens labels, filled vs empty cells
```

**What this surfaces:**
- Phase that produced 0 tool calls → system context missing or prompt rejected
- Phase that hit step limit → agent truncated, cells after step 18 not written
- Cells skipped (locked/confirmed) → `output_summary` starts with "Skipped"
- Stage/lens labels still generic → scaffold phase didn't run or failed

**Acceptance Criteria:**
- Workflow documented as a comment block in `81_build_full.xs` header
- Endpoints confirmed working via manual test with a real map ID
- No new code required — this is a workflow + documentation story

**Layer:** Documentation only

---

---

### US-ARO-08 — Fix manual chat partial build reliability

**Story:** As a user who asks the chatbot to fill a specific part of the journey map
("fill the descriptions", "add the customer lens content"), I want the agent to use the
correct tool and target only the lenses I asked about — not guess, bleed into adjacent
lenses, or overwrite already-filled cells.

**Root causes:**

1. **Actor type missing from injected context** — the dynamic context injects lens labels
   but not `actor_type`. The agent cannot apply its tool routing rule
   (`actor cells → update_actor_cell_fields`, `structural → batch_update`) without knowing
   which type each lens is. It defaults to `batch_update`, writing plain text into
   structured actor cells.

2. **Agent skips `get_map_state` on "simple" requests** — the system prompt says ALWAYS
   call `get_map_state` first, but the agent judges single-turn requests as too simple to
   warrant it and writes blind — guessing stage keys, missing stages, or overwriting
   already-filled cells.

3. **No scope fence on manual requests** — phase prompts have hard scope fences
   ("Fill ONLY the Description lens"). Manual chat messages have none, so the agent
   interprets "fill the descriptions" however it likes and sometimes touches adjacent
   lenses or restructures stages.

**Changes:**

**`apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`**
- Extend lens label injection to include `actor_type` for each lens:
  ```
  Before: "- Customer (lens-2)"
  After:  "- Customer (lens-2) [actor_type: customer]"
  ```
- Extend cell fill status injection from a count to a per-cell grid:
  ```
  Before: "56 filled, 7 empty"
  After:  per lens row showing which stage keys are filled vs empty
          e.g. "Customer: s1✅ s2✅ s3⬜ s4⬜ s5✅ s6⬜ s7⬜ s8⬜"
  ```

**`agents/2_journey_map_assistant.xs`**
- Strengthen the `get_map_state` rule — remove the "at the start of a new conversation"
  qualifier. Replace with:
  > "Call `get_map_state` before ANY write operation. No exceptions. This is required to
  > know which stage keys exist, which cells are already filled, and which actor_type
  > applies to each lens row."
- Add a manual request scope rule:
  > "When the user asks you to fill a specific lens or stage, treat it as a scoped
  > operation. Write ONLY to the requested lens/stage. Do NOT restructure, rename, or
  > write to other lenses unless explicitly asked."

**Acceptance Criteria:**
- Turn logs for a "fill the descriptions" request show only `batch_update` calls
- Turn logs for a "fill the customer lens" request show only `update_actor_cell_fields` calls
- No cross-lens writes appear in tool logs for any single-lens request
- `get_map_state` appears as the first tool call on every turn that writes cells
- Already-filled cells are not overwritten (content field already non-empty = skip)
- Dynamic context for each lens now includes `actor_type` label

**Files:**
- `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
- `agents/2_journey_map_assistant.xs`

**Layer:** Backend (orchestrator context injection) + Agent (system prompt rule)

---

### US-ARO-09 — Fix fill counter to include actor_fields data

**Story:** As a user viewing the build result, I want `cells_filled` and `progress_percentage`
to reflect actual completion — including actor cells whose data lives in `actor_fields`, not
`content`.

**Root cause:** `build_full` counts empty cells by checking `content == null || content == ""`.
Actor lenses (`actor_type` non-empty) store all structured data in `actor_fields` and leave
`content` blank by design. This makes every actor cell look empty, deflating the progress
percentage by ~40% on a typical build.

**Discovered:** ARO-03 integration test. Map 114 reported 55% complete but was actually 100%
complete — 32 actor cells written to `actor_fields` were invisible to the counter.

**Files changed:**
- `apis/journey_map/81_journey_map_journey_map_id_build_full_POST.xs`
  - In-loop progress check (lines ~397-425): add lens→actor_type map, apply actor_fields check
  - Final progress snapshot (lines ~468-492): same lens map + actor_fields check

**Pattern:** Mirrors the `is_empty` logic already in `tools/9_get_gaps.xs` (lines 240-311) and
the `fc_is_filled` logic in `apis/journey_map/52_ai_message_POST.xs` (lines 3506-3550).

**Acceptance criteria:**
- After a full build where all actor cells are written, `progress_percentage` is ≥ 95
- The `status` field returns `"complete"` not `"stalled"` on a 100% filled map
- Non-actor cells (description, structural) are unaffected — still use content check

**Layer:** Backend — `build_full` orchestrator only. No UI change needed.

---

## Out of Scope

- Streaming tool call output in real time during agent execution
- Log retention / cleanup policies
- Exporting build logs to CSV or external observability tools
- Per-user debug mode settings stored server-side
