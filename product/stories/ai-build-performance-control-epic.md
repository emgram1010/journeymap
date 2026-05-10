# AI Build Performance & Control Epic

**Epic goal:** Reduce full journey map build time from 4-5 minutes to under 2 minutes, give users real-time progress narration and a stop button, eliminate duplicate lens/stage creation, and align the architecture to scale cleanly to MCP system-to-system integrations.

---

## Context & Motivation

The current AI build flow has four compounding problems discovered during testing, plus two additional issues surfaced during post-implementation testing:

1. **4-5 minute wait with no feedback** — the user sees a spinner for the entire duration. A build loop of up to 8 turns × ~45s per turn (with `reasoning: true` on every turn) produces a degraded experience and appears broken.
2. **No way to stop** — the user cannot abort a build in progress. When the AI produces duplicate lenses or stages, there is no escape hatch.
3. **Duplicate lenses and stages** — on `[CONTINUE_BUILD]` turns the agent occasionally re-calls `scaffold_structure`, stacking duplicate rows on top of existing structure.
4. **Reasoning tax on every turn** — `reasoning: true` adds 20-40s per turn. For fill turns (pure cell writing with explicit scoped instructions), extended thinking provides no value and only costs time.
5. **Hidden Turn 0 dead zone** *(post-implementation)* — when `BUILD_REQUEST_REGEX` matches, the user's raw message is sent to the agent as a full reasoning turn before the phase queue fires. This burns 60-90s with no progress update — the indicator stays at 0% for the entire duration of Turn 0 + scaffold phase.
6. **Merge conflict in `build_full`** *(post-implementation)* — a sync conflict between local and Xano server versions left conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) inside `81_journey_map_journey_map_id_build_full_POST.xs`, breaking the server-side phase loop silently.

---

## Dependencies

- `ai-build-intelligence-mcp-readiness-epic.md` — US-BIM-01 → 07 must be complete. This epic extends the build loop with phase queuing, abort control, and reasoning optimisation.
- `ai-map-build-continuation-epic.md` — US-AMBC-01 → 06 must be complete (continuation loop in `App.tsx`).
- `agents/2_journey_map_assistant.xs` — existing agent, extended with a second config for fill turns.
- `apis/journey_map/81_journey_map_journey_map_id_build_full_POST.xs` — existing server-side loop, updated to consume the phase queue.
- `webapp/protype-2/src/App.tsx` — existing build loop and `ActivityPanel`, extended with phase queue state, abort controller, and timer.
- `webapp/protype-2/src/xano.ts` — `sendAiMessage` extended to accept `AbortSignal`.

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Build loop structure | Replace single `[CONTINUE_BUILD]` with an 8-phase prompt queue | Scoped phases = fewer tool calls per turn = faster turns + meaningful narration |
| 2 | Reasoning strategy | ON for phases 1, 2, 8 only; OFF for phases 3-7 | Scaffold + verify require judgment; fill turns are pure execution |
| 3 | Two agent configs | `Journey Map Assistant` (reasoning ON) + `Journey Map Builder` (reasoning OFF) | Cannot toggle reasoning per turn in one config |
| 4 | Stop button | `AbortController` threaded through `xanoRequest` + red square UI button | Kills in-flight HTTP request; stop is immediate at phase boundary |
| 5 | Elapsed timer | `setInterval` in React, ticking while `isSendingMessage === true` | Zero backend changes; pure frontend; matches Augment AI UX pattern |
| 6 | Scaffold guard | System prompt rule blocking `scaffold_structure` / `mutate_structure` on non-scaffold phases | Eliminates duplicate structure at source |
| 7 | MCP compatibility | Phase prompts live in `build_full` backend loop — same phases, no frontend dependency | MCP callers get phase-aware builds without UX changes |
| 8 | Skip Turn 0 | On `BUILD_REQUEST_REGEX` match, send scaffold phase prompt as the first message — skip raw user message turn | Eliminates 60-90s dead zone at 0%; user sees movement immediately |
| 9 | Conflict resolution strategy | Always resolve `build_full` conflicts by keeping the phase-queue version (our canonical) | Server-side loop must be clean for MCP and frontend builds to work |

---

## Vocabulary

| Term | Definition |
|---|---|
| **Phase queue** | An ordered array of 8 scoped build prompts that replace the single generic `[CONTINUE_BUILD]` message |
| **Scaffold phase** | Phase 1 — creates stages and lens rows only; no cell content written |
| **Fill phase** | Phases 3-7 — each fills one lens row across all stages |
| **Verify phase** | Phase 8 — cross-lens consistency check; surfaces issues, does not rewrite |
| **Reasoning tax** | The 20-40s latency overhead of `reasoning: true` on turns that do not require multi-step judgment |
| **Scaffold guard** | System prompt rule that blocks structure mutations on all non-scaffold phases |
| **AbortController** | Browser-native API used to cancel an in-flight `fetch` request when the user clicks Stop |
| **Turn 0 dead zone** | The hidden extra agent turn caused by sending the user's raw message before the phase queue fires — eliminated in US-BPC-07 |
| **Conflict markers** | `<<<<<<<` / `=======` / `>>>>>>>` syntax left in `.xs` files after a failed sync merge — causes silent parse failures on Xano |

---

## Priority Stack

```
🔴 HIGH   US-BPC-01  Phase queue architecture (App.tsx + agent prompt)
🔴 HIGH   US-BPC-02  Scaffold guard (agent prompt)
🔴 HIGH   US-BPC-03  Stop button + AbortController (xano.ts + App.tsx)
🟡 MEDIUM US-BPC-04  Elapsed timer (App.tsx)
🟡 MEDIUM US-BPC-05  Reasoning optimisation — two agent configs
🟢 LOW    US-BPC-06  Phase queue in build_full (MCP backend)
🔴 HIGH   US-BPC-07  Skip Turn 0 — start phase queue immediately on build request
🔴 HIGH   US-BPC-08  Resolve build_full merge conflict
```

---

## User Stories

### US-BPC-01 — Phase queue build architecture
**Priority:** 🔴 HIGH
**Files:** `webapp/protype-2/src/App.tsx`, `agents/2_journey_map_assistant.xs`

**Story:** As a user asking the AI to build my journey map, I want to receive a chatbox update after each meaningful build phase so I know exactly what the AI just completed and what it is doing next — instead of waiting 4-5 minutes with no feedback.

**Phase queue definition:**

| Index | Phase key | Prompt sent to agent | Reasoning |
|---|---|---|---|
| 0 | `scaffold` | `[BUILD_PHASE:scaffold] Scaffold stages and lenses only. Do NOT fill any cells. Report what you created.` | ON |
| 1 | `identity` | `[BUILD_PHASE:identity] Fill actor identity (persona_description, primary_goal, standing_constraints) for all actor lenses. Do not fill cells.` | ON |
| 2 | `description` | `[BUILD_PHASE:description] Fill the Description lens across all stages using batch_update only.` | OFF |
| 3 | `customer` | `[BUILD_PHASE:customer] Fill the Customer lens across all stages using update_actor_cell_fields only.` | OFF |
| 4 | `internal` | `[BUILD_PHASE:internal] Fill all Internal Actor lenses across all stages using update_actor_cell_fields only.` | OFF |
| 5 | `structural` | `[BUILD_PHASE:structural] Fill Top Pain Point, Key Variable, Cascade Risk, and Systems lenses across all stages using batch_update only.` | OFF |
| 6 | `metrics` | `[BUILD_PHASE:metrics] Fill Metrics and Financial lenses across all stages using update_actor_cell_fields only.` | OFF |
| 7 | `verify` | `[BUILD_PHASE:verify] Run cross-lens consistency check. Call get_map_state. Surface inconsistencies only — do not rewrite any cells.` | ON |

**Frontend changes (`App.tsx`):**
- Replace `BUILD_CONTINUATION_PROMPT` string with `BUILD_PHASES` array (8 entries above)
- Replace `buildLoopTurnsRef` turn counter with `buildPhaseIndexRef` phase index
- Loop advances `phaseIndex` after each successful turn
- Loop exits when all 8 phases complete or user stops
- `buildLoopProgress` derived from `(phaseIndex / 8) * 100`

**Agent prompt additions (`agents/2_journey_map_assistant.xs`):**
```
## Phase turn rules
When the user message starts with "[BUILD_PHASE:{key}]":
- Execute ONLY the task described in the phase message.
- Do NOT execute tasks belonging to other phases.
- Reply with one concise sentence confirming what was completed.
  Format: "{Phase} complete — {N} {items} created/filled. Moving to next phase..."
- Do NOT re-introduce yourself or summarise prior phases.
```

**Acceptance criteria:**
- User receives a chatbox message after every phase (max ~20-30s between updates)
- Each message names what was just completed and what comes next
- The build loop advances through all 8 phases in order
- Skipping a phase (e.g. no internal actors) moves to the next phase without error
- `buildLoopProgress` reflects phase index (0% → 12.5% per phase completed)
- Existing single-turn interview and chat flows are unaffected
- `[CONTINUE_BUILD]` generic prompt is removed from `App.tsx`

---

### US-BPC-02 — Scaffold guard
**Priority:** 🔴 HIGH
**File:** `agents/2_journey_map_assistant.xs`

**Story:** As a user, I want the AI to never create duplicate stages or lenses when resuming or continuing a build, so my journey map does not require manual cleanup after an AI build session.

**System prompt addition:**
```
## Scaffold guard
On any turn where the user message starts with "[BUILD_PHASE:" and the key is NOT "scaffold":
- NEVER call scaffold_structure.
- NEVER call mutate_structure with action add_stage or add_lens.
- The map structure already exists. Your only job is to fill cells or verify content.
Violating this rule creates duplicate rows that cannot be auto-resolved.
```

**Acceptance criteria:**
- `scaffold_structure` is never called on phases 1-7 (identity through verify)
- `mutate_structure` with `add_stage` or `add_lens` is never called outside phase 0
- If the agent detects missing structure during a fill phase, it surfaces a note in its reply rather than adding structure
- No regression on Phase 0 (scaffold) — structure creation still works correctly

---

### US-BPC-03 — Stop button + AbortController
**Priority:** 🔴 HIGH
**Files:** `webapp/protype-2/src/xano.ts`, `webapp/protype-2/src/App.tsx`

**Story:** As a user watching the AI build my map, I want a visible stop button I can click at any time to immediately halt the build — so I am never trapped watching a runaway or incorrect build with no escape.

**`xano.ts` changes:**
- Add `signal?: AbortSignal` to `RequestOptions` type
- Pass `signal` to the `fetch()` call in `xanoRequest`
- Add `signal?: AbortSignal` to `SendAiMessageInput` type
- Pass `input.signal` to `xanoRequest` in `sendAiMessage`

**`App.tsx` changes:**
- Add `abortControllerRef = useRef<AbortController | null>(null)`
- On each `handleSendMessage` call: create a new `AbortController`, store in ref, pass `signal` to `sendAiMessage`
- Add `handleStopBuild` callback:
  - Sets `isBuildLoopingRef.current = false`
  - Sets `setIsBuildLooping(false)` and `setIsSendingMessage(false)`
  - Calls `abortControllerRef.current?.abort()`
  - Appends a system message: `"Build stopped by user at {progress}% — you can resume anytime."`
- **UI:** While `isSendingMessage === true`, replace the Send button (▶) with a red Stop button (■)

**Acceptance criteria:**
- Stop button (red square) is visible whenever `isSendingMessage === true`
- Clicking Stop immediately ends the build loop — no further phases fire
- The in-flight HTTP request to `/ai_message` is aborted via `AbortController`
- A system message appears in the chat confirming the stop and current progress %
- Send button returns after stop
- Stopping mid-build does not corrupt map data — partial writes from the aborted turn remain as draft
- `AbortError` from the cancelled fetch is caught silently (no error toast shown to user)

---

### US-BPC-04 — Elapsed timer
**Priority:** 🟡 MEDIUM
**File:** `webapp/protype-2/src/App.tsx`

**Story:** As a user waiting for the AI to respond, I want to see a ticking elapsed time counter so I always know the AI is still working and how long the current operation has taken.

**Changes:**
- Add `elapsedSeconds` state, reset to `0` when `isSendingMessage` becomes `true`
- `useEffect` with `setInterval(1000)` that increments `elapsedSeconds` while `isSendingMessage === true`
- Display `MM:SS` format in the amber build indicator and the standard thinking indicator
- Timer resets to `0:00` on each new user message send

**UI placement:** Inline with the existing "Building map… X% complete (turn N/8)" text:
```
Building map… 37% complete (phase 3/8)   0:47
```

**Acceptance criteria:**
- Timer starts at `0:00` the moment `isSendingMessage` becomes `true`
- Timer ticks every second accurately
- Timer displays in `M:SS` format (e.g. `0:52`, `1:04`, `2:31`)
- Timer resets to `0:00` on each new send (not cumulative across turns)
- Timer is visible in both build loop mode and single-turn mode
- Timer stops and resets when `isSendingMessage` becomes `false`

---

### US-BPC-05 — Reasoning optimisation — two agent configs
**Priority:** 🟡 MEDIUM
**File:** `agents/2_journey_map_assistant.xs` (new sibling file `agents/4_journey_map_builder.xs`)

**Story:** As a product team, we need the AI fill phases (3-7) to run without extended thinking to reduce per-turn latency by 30-40%, while preserving reasoning quality on the phases that require multi-step judgment (scaffold, identity, verify).

**New agent file `agents/4_journey_map_builder.xs`:**
- Clone of `agents/2_journey_map_assistant.xs`
- `reasoning: false`
- `max_steps: 15` (fill phases are narrow-scoped; 15 steps is sufficient for one lens row)
- `model: "claude-sonnet-4-5"` (same model, no quality regression on fill tasks)
- Canonical name: `"Journey Map Builder"`

**`agents/2_journey_map_assistant.xs` changes:**
- `max_steps: 20` (reduced from 40; scaffold + verify phases do not need 40 steps)

**`App.tsx` phase routing:**
- Phases 0, 1, 7 (scaffold, identity, verify): call existing `ai_message` endpoint (uses `Journey Map Assistant` with reasoning)
- Phases 2-6 (fill phases): call `ai_message` endpoint with `builder_mode: true` flag, which routes to `Journey Map Builder`

**`apis/journey_map/52_..._ai_message_POST.xs` change:**
- Accept optional `bool builder_mode?`
- When `builder_mode === true`, invoke `ai.agent.run "Journey Map Builder"` instead of `"Journey Map Assistant"`

**Acceptance criteria:**
- Phases 0, 1, 7 use `Journey Map Assistant` (reasoning ON, max_steps 20)
- Phases 2-6 use `Journey Map Builder` (reasoning OFF, max_steps 15)
- Fill turn latency reduced by measurable amount (target: < 25s per fill phase turn)
- Cell content quality on fill phases is not degraded vs. baseline
- Chat mode and single-turn interview mode continue to use `Journey Map Assistant` (no change)
- `Journey Map Builder` agent is not exposed directly to users — internal routing only

---

### US-BPC-06 — Phase queue in build_full (MCP backend)
**Priority:** 🟢 LOW
**File:** `apis/journey_map/81_journey_map_journey_map_id_build_full_POST.xs`
**Depends on:** US-BPC-01, US-BPC-02, US-BPC-05

**Story:** As an MCP caller triggering a headless map build, I want the server-side build loop to use the same 8-phase architecture as the frontend so I get faster, more reliable builds with per-phase progress in the tool trace summary.

**Changes to `build_full`:**
- Replace the single `[CONTINUE_BUILD]` continuation message with a `$phase_prompts` array (same 8 phases as US-BPC-01)
- Loop index maps to phase index (0-7) instead of a generic turn counter
- Per-phase agent routing: phases 0, 1, 7 → `Journey Map Assistant`; phases 2-6 → `Journey Map Builder`
- `tool_trace_summary` response extended with `phase_key` per turn entry

**Updated response shape:**
```json
{
  "tool_trace_summary": [
    { "turn": 1, "phase_key": "scaffold",     "tools_called": 6,  "cells_written": 0,  "skips": 0 },
    { "turn": 2, "phase_key": "identity",     "tools_called": 4,  "cells_written": 0,  "skips": 0 },
    { "turn": 3, "phase_key": "description",  "tools_called": 8,  "cells_written": 6,  "skips": 0 },
    { "turn": 4, "phase_key": "customer",     "tools_called": 12, "cells_written": 18, "skips": 1 }
  ]
}
```

**Acceptance criteria:**
- `build_full` runs all 8 phases in order using the phase prompt array
- Each phase uses the correct agent (reasoning ON/OFF per US-BPC-05)
- `tool_trace_summary` includes `phase_key` on every entry
- MCP callers receive phase-aware progress without any frontend dependency
- Existing `build_journey_map` MCP tool (US-BIM-07) works unchanged — no input schema change
- `status: "complete"` only returned after all 8 phases have run or `progress >= 95%`

---

## Recommended Implementation Sequence

```
US-BPC-02  (scaffold guard — system prompt, zero risk)            → ✅ DONE
US-BPC-03  (stop button + AbortController — xano.ts + App.tsx)   → ✅ DONE
US-BPC-04  (elapsed timer — App.tsx only)                         → ✅ DONE
US-BPC-01  (phase queue — App.tsx + agent prompt)                 → ✅ DONE
US-BPC-05  (reasoning optimisation — new agent file + routing)    → ✅ DONE
US-BPC-06  (phase queue in build_full — MCP backend)              → ✅ DONE
US-BPC-08  (resolve build_full merge conflict)                    → 🔴 NEXT
US-BPC-07  (skip Turn 0 — start phase queue immediately)          → 🔴 NEXT
```

US-BPC-08 must come before US-BPC-07 — the conflict must be clean before the Turn 0 fix is pushed.

---

---

### US-BPC-07 — Skip Turn 0 — start phase queue immediately on build request
**Priority:** 🔴 HIGH
**File:** `webapp/protype-2/src/App.tsx`
**Depends on:** US-BPC-01, US-BPC-08

**Story:** As a user who asks the AI to build my journey map, I want the build indicator to show progress immediately — not stay at 0% for 2 minutes while the AI processes my raw message before doing any real work.

**Root cause:** When `BUILD_REQUEST_REGEX` matches the user's input, the current code still sends the raw user message (`"create a pizza delivery journey map"`) to the agent as Turn 0 before firing the phase queue. The agent runs `reasoning: true`, executes the pre-build capacity rule (`get_gaps` → estimate → respond), and only then does the phase queue start. This creates a 60-90s dead zone where the indicator shows `0%` with no progress.

**Fix — `App.tsx` `handleSendMessage`:**

When `BUILD_REQUEST_REGEX` matches and `isBuildLooping` is armed, **replace the message sent to the agent with the scaffold phase prompt** — skip Turn 0 entirely. The user's original message is already shown optimistically in the chat; the agent does not need to process it as a separate turn.

```js
// BEFORE (current)
const messageText = isContinuation ? currentPhase.prompt : inputText.trim();
// Turn 0 sends raw user input → agent does pre-build capacity check → 60-90s wasted

// AFTER
const isBuildRequest = !isChatMode && BUILD_REQUEST_REGEX.test(inputText.trim());
const messageText = isContinuation
  ? BUILD_PHASES[buildPhaseIndexRef.current].prompt
  : isBuildRequest
    ? BUILD_PHASES[0].prompt   // ← jump straight to scaffold
    : inputText.trim();
```

The `builderMode` for Turn 0 must be `false` (scaffold uses `Journey Map Assistant` with reasoning ON — this is correct).

**Acceptance criteria:**
- On a build request, the very first message sent to the agent is `[BUILD_PHASE:scaffold]`
- The user's raw message text is still shown in the chat (optimistic render is unchanged)
- `buildPhaseIndexRef.current` starts at `0` — scaffold is Turn 0, not Turn 1
- Progress updates to `12.5%` after the first turn completes (not still at `0%`)
- Non-build messages (chat, single-turn interview) are completely unaffected
- `BUILD_REQUEST_REGEX` detection logic is unchanged

---

### US-BPC-08 — Resolve build_full merge conflict
**Priority:** 🔴 HIGH
**File:** `apis/journey_map/81_journey_map_journey_map_id_build_full_POST.xs`
**Depends on:** None

**Story:** As a developer, I need the `build_full` endpoint to be free of merge conflict markers so it parses and executes correctly on Xano for both frontend and MCP builds.

**Root cause:** A sync conflict between the local push and the Xano server version left `<<<<<<<`, `=======`, `>>>>>>>` markers inside the file. The two sides of the conflict are functionally identical — only whitespace/formatting differs. The conflict must be resolved by keeping the phase-queue version and removing all conflict markers.

**The conflict (lines 100, 136, 150, 155, 162):**
Both sides declare `$use_builder_agent` identically — one uses inline format, the other uses block format. The correct resolution is the **block format** (matches the rest of the file style):

```xs
var $use_builder_agent {
  value = $builder_phase_indices|contains:$loop_idx
}
```

**Acceptance criteria:**
- No `<<<<<<<`, `=======`, or `>>>>>>>` markers exist anywhere in the file
- `$phase_prompts`, `$phase_keys`, `$builder_phase_indices` arrays are intact
- Phase-aware agent routing (`Journey Map Builder` for indices 2-6) is intact
- `phase_key` in `tool_trace_summary` is intact
- File pushes to Xano with no critical errors
- `build_full` endpoint executes a full 8-phase build without error

---

## Out of Scope (this epic)

- Streaming tool-call progress mid-turn (blocked by `ai.agent.run` being synchronous)
- Per-phase cancel with rollback (partial phase writes remain as draft — acceptable)
- Model downgrade to Haiku for fill turns (quality risk not justified at this stage)
- Cross-map batch phase builds
- User-configurable phase order or phase skipping
