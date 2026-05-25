# AI Build Intelligence & MCP Readiness Epic

**Epic goal:** The AI journey map builder must plan before it acts, complete work reliably across multiple turns, keep the user informed with per-action feedback, and expose the full build capability to MCP callers so 3rd-party systems (CRMs, ticket systems) can trigger and monitor map builds programmatically.

---

## Context & Motivation

The current AI build flow has four compounding problems:

1. **Builds blind** — the agent starts writing cells without knowing how many empty cells exist or how many turns are required. It silently hits `max_steps: 40` mid-build with no warning.
2. **No user visibility** — the user sees a spinner; they have no idea which tools fired, which cells were written, or whether any writes were skipped.
3. **Frontend-only loop** — the continuation loop (`ai-map-build-continuation-epic.md`) lives in `App.tsx`. MCP callers (no browser) get Turn 1 only and receive a half-built map.
4. **Static estimate** — if the AI does communicate a turn estimate, it never revises it as real remaining gaps change.

---

## Dependencies

- `ai-map-build-continuation-epic.md` — US-AMBC-01 → 06 must be complete (step budget raised to 40, continuation loop in frontend). This epic extends those stories with planning, transparency, and server-side equivalents.
- `tools/9_get_gaps.xs` — already returns `total_gaps`, `by_stage`, `by_lens`. Used by the planning rule.
- `tables/11_agent_tool_log.xs` — already captures `tool_name`, `tool_category`, `input_summary`, `output_summary` per tool call. Used by the activity feed.
- `webapp/protype-2/src/App.tsx` — `ActivityPanel` component already renders `tool_trace`. Status dot change is additive.

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Planning gate | System prompt rule + `get_gaps` call before build starts | Data already exists; zero new tools needed |
| 2 | Capacity math | `ceil((total_gaps + 5) / 30)` turns estimate | 30 usable write steps per turn (40 max − 10 overhead/actor cells) |
| 3 | Activity feed trigger | Auto-expand `ActivityPanel` while `isBuildLooping === true` | Reuses existing component; no new UI infrastructure |
| 4 | Status dots | Derive from `output_summary` prefix: "Applied" → 🟢, "Skipped"/"Failed" → 🔴 | `output_summary` already carries this signal in every tool log |
| 5 | Silent retry rule | System prompt: log skip, move on, surface only if > 3 skips | Reduces noise; user cares about aggregate, not every locked cell |
| 6 | Revised estimate | Inline in continuation reply: `~{ceil(remaining/25)} more turns` | One-line system prompt change; self-correcting per turn |
| 7 | Server-side loop | New `POST /journey_map/{id}/build_full` endpoint | MCP callers have no frontend; loop must be backend-owned |
| 8 | MCP tool name | `build_journey_map` | Consistent naming with `log_exception`, `get_resolution` pattern |

---

## Vocabulary

| Term | Definition |
|---|---|
| **Planning gate** | The mandatory `get_gaps` call + capacity estimate the agent performs before writing any cell on a map-level build |
| **Turn estimate** | `ceil((total_gaps + 5) / 30)` — the agent's upfront prediction of how many continuation turns are needed |
| **Activity feed** | The per-turn list of tool calls rendered in the chat sidebar with 🟢/🔴 status dots |
| **Silent retry** | Agent behaviour: when a write is skipped (locked/confirmed cell), log it and continue without surfacing it to the user unless a threshold is exceeded |
| **Server-side loop** | The `build_full` endpoint that runs the multi-turn continuation loop on the backend, making the build callable from MCP |
| **build_journey_map** | The MCP tool that wraps `build_full` and returns a structured completion summary |

---

## Priority Stack

```
🔴 HIGH   US-BIM-01  Pre-build planning rule (system prompt)
🔴 HIGH   US-BIM-02  Server-side build orchestration endpoint
🟡 MEDIUM US-BIM-03  Activity feed auto-expand during build loop
🟡 MEDIUM US-BIM-04  Green/red status dots on tool trace entries
🟡 MEDIUM US-BIM-05  Silent retry rule (system prompt)
🟢 LOW    US-BIM-06  Revised turn estimate per continuation reply
🟢 LOW    US-BIM-07  MCP build_journey_map tool definition
```

---

## User Stories

### US-BIM-01 — Pre-build planning rule
**Priority:** 🔴 HIGH
**File:** `agents/2_journey_map_assistant.xs`

**Story:** As the Journey Map Assistant, before starting any map-level build I must call `get_gaps`, estimate the number of turns required, and communicate the plan to the user — so I never start writing cells blind.

**System prompt addition (under `## Build Sequence Order`):**
```
## Pre-build capacity rule
Before writing ANY cell on a map-level build:
1. Call get_gaps to get total_gaps count.
2. Estimate turns needed: ceil((total_gaps + 5) / 30).
3. Communicate the plan:
   "This map has {N} empty cells — I'll complete it in ~{turns} turn(s). Starting now..."
4. THEN begin the Build Sequence Order.
Never start writing before completing steps 1–3.
```

**Acceptance criteria:**
- Agent always calls `get_gaps` as the first action on a map-level build request
- Agent reply includes cell count and turn estimate before any writes
- If `total_gaps === 0`, agent replies "Map is already complete" and stops
- Estimate uses `ceil((total_gaps + 5) / 30)` formula
- Existing `[CONTINUE_BUILD]` flow is unaffected

---

### US-BIM-02 — Server-side build orchestration endpoint
**Priority:** 🔴 HIGH
**File:** New Xano API endpoint

**Story:** As an MCP caller (CRM, ticket system, external AI agent), I need a single endpoint that runs the full multi-turn map build on the backend so I get a complete result without needing a browser or frontend loop.

**Endpoint:** `POST /journey_map/{journey_map_id}/build_full`
**Auth:** User token (same as `ai_message`) or account API key for MCP

**Input:**
```json
{
  "journey_map_id": 7,
  "context": "B2B SaaS onboarding flow for mid-market customers",
  "max_turns": 8
}
```

**Response:**
```json
{
  "status": "complete" | "partial" | "stalled",
  "turns_used": 3,
  "cells_filled": 58,
  "cells_remaining": 5,
  "progress_percentage": 92,
  "skipped_cells": [
    { "stage_key": "checkout", "lens_key": "metrics", "reason": "locked" }
  ],
  "tool_trace_summary": [
    { "turn": 1, "tools_called": 12, "cells_written": 22, "skips": 1 },
    { "turn": 2, "tools_called": 10, "cells_written": 20, "skips": 0 },
    { "turn": 3, "tools_called": 8,  "cells_written": 16, "skips": 0 }
  ]
}
```

**Behavior:**
- Calls `ai_message` internally with `[CONTINUE_BUILD]` in a loop
- Loop exits when `progress >= 95%`, stall detected (2 zero-write turns), or `max_turns` reached
- Aggregates `agent_tool_log` entries across all turns for `tool_trace_summary`

**Acceptance criteria:**
- Returns `status: "complete"` when `progress >= 95%`
- Returns `status: "stalled"` when 2 consecutive turns have `cells_written === 0`
- Returns `status: "partial"` when `max_turns` exhausted below threshold
- `skipped_cells` lists every cell where a write was blocked (locked or confirmed)
- Endpoint callable with account API key (machine-to-machine, no user session required)
- Browser `App.tsx` continuation loop continues to work independently — no regression

---

### US-BIM-03 — Activity feed auto-expand during build loop
**Priority:** 🟡 MEDIUM
**File:** `webapp/protype-2/src/App.tsx`

**Story:** As a user watching the AI build my map, I want the tool trace activity panel to automatically expand for each turn so I can see what the AI is doing without manually clicking to reveal it.

**Behavior:**
- While `isBuildLooping === true`, set `isTraceExpanded: true` by default on each new `MessageActivity`
- When build loop exits, revert to collapsed default for subsequent non-build messages
- Each turn shows its own activity panel with the turn label: `"Turn {N} of ~{estimate}"`

**Acceptance criteria:**
- Activity panel auto-expands for every turn during an active build loop
- Auto-expand does not affect non-build (chat/interview) messages
- No layout reflow — expansion uses existing `ActivityPanel` styles

---

### US-BIM-04 — Green/red status dots on tool trace entries
**Priority:** 🟡 MEDIUM
**File:** `webapp/protype-2/src/App.tsx` (ActivityPanel component)

**Story:** As a user, I want each tool call in the activity feed to show a green dot for success or a red dot for skip/failure so I can instantly see whether the AI's actions landed.

**Current state:** Category icons only (`📖` read, `✏️` write, etc.) — no success/failure signal.

**Derive status from `entry.outputSummary`:**
- Starts with `"Applied"` or contains `"filled"` or `"written"` → 🟢
- Starts with `"Skipped"` or `"Failed"` → 🔴
- Read tool outputs → neutral (⚪)

**Acceptance criteria:**
- 🟢 dot for `output_summary` matching Applied / written / filled
- 🔴 dot for `output_summary` matching Skipped / Failed
- ⚪ dot for read tools (`get_map_state`, `get_gaps`, `get_slice`, `search_cells`)
- No change to `agent_tool_log` schema — purely frontend derivation
- Existing category icons remain; dot is additive

---

### US-BIM-05 — Silent retry rule
**Priority:** 🟡 MEDIUM
**File:** `agents/2_journey_map_assistant.xs`

**Story:** As a user, I don't want to be interrupted every time the AI skips a locked cell — I only want to know if a meaningful number of cells were blocked.

**System prompt addition (under `## Core rules`):**
```
## Skip handling rule
When a write tool returns "Skipped" (locked or confirmed cell):
- Log it internally and continue to the next cell immediately.
- Do NOT mention individual skips in your reply text.
- At the END of a turn, if total skips >= 3, include one summary line:
  "Note: {N} cells were skipped (locked or confirmed) — see the activity log for details."
- If skips < 3, do not mention them at all.
```

**Acceptance criteria:**
- Agent never interrupts the build flow to report a single skip
- Summary line appears only when `skipped_count >= 3` in a turn
- Summary is one sentence — no enumeration of individual cells in reply text
- Full skip list remains available in `tool_trace` / `agent_tool_log`

---

### US-BIM-06 — Revised turn estimate per continuation reply
**Priority:** 🟢 LOW
**File:** `agents/2_journey_map_assistant.xs`

**Story:** As a user watching a multi-turn build, I want each continuation reply to update the remaining turn estimate based on actual gaps remaining — not the original guess.

**System prompt change (update `## Continuation turn rule` step 4):**
```
4. Reply with a one-line status:
   "Continued — {N} cells filled. {remaining} remaining (~{ceil(remaining/25)} more turn(s))."
   If remaining === 0: "Build complete — all cells filled."
```

**Acceptance criteria:**
- Every `[CONTINUE_BUILD]` reply ends with the one-line status format above
- `remaining` is derived from `get_gaps().total_gaps` called at turn start
- Estimate recalculates each turn — converges toward 0 as the build completes
- Completion message fires when `remaining === 0`

---

### US-BIM-07 — MCP `build_journey_map` tool definition
**Priority:** 🟢 LOW
**File:** `mcp_servers/journey_map.xs` (new file)
**Depends on:** US-BIM-02 (server-side endpoint must exist first)

**Story:** As an enterprise AI agent or 3rd-party system, I want to call `build_journey_map` via MCP so I can trigger a full AI map build without custom REST integration.

**MCP tool name:** `build_journey_map`

**Input schema:**
```json
{
  "journey_map_id": "integer, required",
  "account_id":     "integer, required",
  "context":        "string, optional — domain context to guide the AI build",
  "max_turns":      "integer, optional, default 8"
}
```

**Response:** Same shape as `POST /journey_map/{id}/build_full`

**Acceptance criteria:**
- MCP tool wraps `build_full` endpoint — no duplicate loop logic
- Account-scoped via `X-Account-Key` header (consistent with `incident_tracking.xs` pattern)
- Tool description: `"Builds or completes a journey map using AI. Returns when all cells are filled or max turns reached. Returns status, cells filled, and a per-turn tool trace summary."`
- Returns MCP error `{ code: "not_found" }` if `journey_map_id` does not belong to the account
- Returns MCP error `{ code: "unauthorized" }` for missing or invalid account key

---

## Recommended Implementation Sequence

```
US-BIM-01 (pre-build planning rule — system prompt)  →
US-BIM-05 (silent retry rule — system prompt)        →
US-BIM-06 (revised estimate — system prompt)         →
US-BIM-03 (activity feed auto-expand — frontend)     →
US-BIM-04 (status dots — frontend)                   →
US-BIM-02 (server-side build endpoint)               →
US-BIM-07 (MCP tool definition)
```

System prompt changes first (lowest risk, highest leverage). Frontend transparency next. Server-side loop and MCP last (highest effort, unlocks external integrations).

---

## Out of Scope (this epic)

- Streaming tool-call progress mid-turn (blocked by `ai.agent.run` being synchronous)
- Per-cell preview / confirm-before-write mode
- Build scheduling (trigger build at a future time)
- Cross-map batch builds (building multiple maps in one MCP call)
