# AI Map Build — Continuation & Stall Recovery Epic

**Epic goal:** When a user asks the AI to build a full journey map the agent must complete every cell, not silently stop mid-build. This epic raises the agent step budget, adds a frontend multi-turn continuation loop, surfaces per-turn progress to the user, and provides a visible Resume path when the agent stalls.

---

## Root Cause

The Journey Map Assistant has `max_steps: 20`. A typical map build (7 stages × 9 lenses = 63 cells) requires 25–35 tool calls (get_map_state + scaffold_structure + update_journey_settings + 8–10 batch_update calls). The agent silently exhausts its step budget after writing structure and a handful of cells — no error is shown.

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Agent step budget | Raise `max_steps` 20 → 40 | Covers most maps without timeout risk |
| 2 | Continuation trigger | `progress.percentage < 95` AND `cellUpdates.length > 0` | Avoids looping when agent is genuinely done or fully stalled |
| 3 | Stall detection | 2 consecutive turns with `cellUpdates.length === 0` | One zero-write turn can be legitimate (settings-only); two in a row is a stall |
| 4 | Max auto-turns | 8 | Caps API spend; surfaced to user if hit |
| 5 | Continuation prompt | Hardcoded "Continue — call get_gaps, fill next batch" | Avoids asking user for input mid-build |
| 6 | Resume button | Re-triggers loop from current map state | Uses same `get_gaps`-based prompt; no special endpoint needed |
| 7 | Progress indicator | Inline "Building… X% complete" in chat panel | Reuses existing `progress.percentage` from every ai_message response |

---

## Vocabulary

| Term | Definition |
|---|---|
| **Continuation turn** | An auto-fired ai_message with the standard continuation prompt — user did not type it |
| **Stall** | Two consecutive turns where `cellUpdates.length === 0` while `progress.percentage < 95` |
| **Build loop** | The frontend-controlled sequence of continuation turns triggered after the user's initial build request |
| **Resume** | User-initiated re-trigger of the build loop from a stalled or incomplete state |
| **Step budget** | `max_steps` in the agent definition — the maximum tool calls per single LLM turn |

---

## User Stories

### US-AMBC-01 — Raise agent step budget
**File:** `agents/2_journey_map_assistant.xs`

Increase `max_steps` from `20` to `40`.

**Acceptance criteria:**
- `max_steps: 40` in the agent LLM config
- Existing workflow tests still pass (no regressions)

---

### US-AMBC-02 — Add continuation prompt instruction to agent system prompt
**File:** `agents/2_journey_map_assistant.xs`

Add a section to the system prompt that instructs the agent how to behave when it receives a continuation turn.

Instruction to add (under `## Interview mode rules`):
```
## Continuation turn rule
When the user message starts with "[CONTINUE_BUILD]", you are mid-way through
a map-level build. Call get_gaps immediately to find empty cells, then fill
the next batch using batch_update and/or update_actor_cell_fields. Do not
re-introduce yourself or summarise what was done. Just continue writing.
```

**Acceptance criteria:**
- Agent recognises `[CONTINUE_BUILD]` prefix and goes straight to `get_gaps` → write loop
- No re-introduction or recap in the reply text

---

### US-AMBC-03 — Frontend: build loop state
**File:** `webapp/protype-2/src/App.tsx`

Add state to track the active build loop:

```ts
const [isBuildLooping, setIsBuildLooping] = useState(false);
const [buildLoopTurns, setBuildLoopTurns] = useState(0);
const [buildStallCount, setBuildStallCount] = useState(0);
const BUILD_LOOP_MAX_TURNS = 8;
const BUILD_COMPLETE_THRESHOLD = 95;
```

**Acceptance criteria:**
- State initialises at `false / 0 / 0`
- State resets when user opens a new map or starts a new conversation

---

### US-AMBC-04 — Frontend: auto-continuation after build request
**File:** `webapp/protype-2/src/App.tsx`

After `handleSendMessage` resolves, check whether a continuation turn should fire:

```
if (
  isBuildLooping &&
  aiThread.progress.percentage < BUILD_COMPLETE_THRESHOLD &&
  buildLoopTurns < BUILD_LOOP_MAX_TURNS
) {
  if (aiThread.cellUpdates.length === 0) {
    setBuildStallCount(prev => prev + 1);
  } else {
    setBuildStallCount(0);
  }

  if (buildStallCount + 1 < 2) {
    setBuildLoopTurns(prev => prev + 1);
    // auto-fire continuation
    sendAiMessage({ content: '[CONTINUE_BUILD] Continue filling empty cells.', ... })
  } else {
    // stall — stop loop, surface resume UI
    setIsBuildLooping(false);
  }
} else {
  setIsBuildLooping(false);
}
```

Detect the initial build request by checking if `inputText` matches the build scope patterns already defined in the agent system prompt (`"build me a journey map"`, `"generate the full map"`, etc.). When matched, set `isBuildLooping(true)` and `buildLoopTurns(0)` before the first send.

**Acceptance criteria:**
- Loop fires continuation turns automatically without user input
- Loop stops at `BUILD_LOOP_MAX_TURNS` or `progress >= 95%`
- Stall detection stops loop after 2 zero-write turns
- Loop never fires in chat mode — only interview/build context

---

### US-AMBC-05 — Frontend: build progress indicator
**File:** `webapp/protype-2/src/App.tsx`

While `isBuildLooping === true`, replace the standard "AI is thinking…" indicator in the chat panel with:

```
⚙ Building map… {progress.percentage}% complete  (turn {buildLoopTurns}/{BUILD_LOOP_MAX_TURNS})
```

**Acceptance criteria:**
- Indicator visible only during active build loop
- Percentage updates live after each continuation turn
- Reverts to normal "AI is thinking…" indicator for non-loop turns

---

### US-AMBC-06 — Frontend: stall / incomplete warning + Resume button
**File:** `webapp/protype-2/src/App.tsx`

When the build loop exits with `progress.percentage < BUILD_COMPLETE_THRESHOLD`, render a warning message in the chat thread:

```
⚠ Build stopped — {progress.percentage}% complete ({empty} cells still empty).
[Resume →]
```

Clicking **Resume** resets `buildLoopTurns` and `buildStallCount` to 0, sets `isBuildLooping(true)`, and fires the continuation prompt immediately.

**Acceptance criteria:**
- Warning message appears as a system message (not user, not AI) in the thread
- Resume button re-triggers the loop from current map state
- Warning does NOT appear when loop exits because progress ≥ 95%
- Warning also appears if `BUILD_LOOP_MAX_TURNS` is exhausted below threshold

---

## Out of Scope

- Server-side continuation (all orchestration stays in the frontend)
- Persisting build loop state across page refreshes
- Per-stage progress breakdown (covered by agent-debug-logging-epic.md)
