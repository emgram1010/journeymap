# Epic — Agent Debug Logging

## Purpose

Expose the existing backend logging infrastructure (already captured per-turn and per-tool) through a queryable API endpoint and a lightweight UI panel so that incomplete or hallucinated AI responses can be diagnosed without guesswork.

## Problem

The agent already writes `agent_tool_log` (one row per tool call) and `agent_turn_log` (one row per turn) on every message. But there is no API to fetch the per-tool records, and the UI never surfaces them. When the agent claims success but fields are empty — or silently stops mid-operation due to step exhaustion — there is no way to see exactly which tools fired, in what order, and what they returned.

**Root cause examples this epic directly addresses:**
- Metrics lens: agent hit `max_steps` limit, stopped at step 9 of 11 — invisible to user
- System Handoff: agent skipped `update_actor_identity` entirely, reported "fully populated" — no warning shown

## What already exists (no changes needed)

| Asset | Status |
|---|---|
| `agent_tool_log` table | ✅ exists, populated on every tool call |
| `agent_turn_log` table | ✅ exists, populated on every turn |
| `GET /journey_map/{id}/turn-logs` | ✅ exists, returns turn-level summary |
| Tool trace in `ai_message` response (`tool_trace[]`) | ✅ exists, returned per turn |

**What's missing:** no endpoint to query `agent_tool_log` by `turn_id` for per-call detail.

---

## Stories

### US-DBG-01 — Tool logs API endpoint

**Story:** As a developer or power user, I want to fetch the individual tool call records for a specific agent turn so I can see exactly which tools fired, what inputs they received, and what they returned.

**File:** `apis/journey_map/80_journey_map_journey_map_id_tool_logs_GET.xs`

**Endpoint:** `GET /journey_map/{journey_map_id}/tool-logs`

**Query params:**
- `turn_id` (text, required) — filter to a specific turn's tool calls
- `conversation_id` (int, optional) — scope to a conversation for safety check

**Response shape:**
```json
{
  "journey_map_id": 12,
  "turn_id": "turn_abc123",
  "count": 9,
  "tool_calls": [
    {
      "id": 1,
      "tool_name": "get_map_state",
      "tool_category": "read",
      "input_summary": "Full map: Last-mile",
      "output_summary": "56 filled, 7 empty, 0 locked",
      "execution_order": 1,
      "created_at": "2026-04-22T16:24:00Z"
    }
  ]
}
```

**Acceptance Criteria:**
- Returns all `agent_tool_log` rows matching `turn_id` scoped to `journey_map_id`
- Sorted by `execution_order` asc, then `created_at` asc
- Returns `count: 0` with empty array when no records match — never 404
- `journey_map_id` ownership is validated (auth guard, owner-scoped)
- If `conversation_id` provided, validates it belongs to the journey map

---

### US-DBG-02 — Turn logs include tool call count and step limit warning

**Story:** As a developer, I want the existing `GET /turn-logs` response to include the tool call count alongside a warning flag when the count is close to or at the agent's `max_steps` limit so I can spot step-exhaustion without manually counting.

**File:** `apis/journey_map/59_journey_map_journey_map_id_turn_logs_GET.xs`

**Changes:** Add `step_limit_warning: bool` to each turn record in the response. Set to `true` when `tool_count >= 18` (90% of current `max_steps: 20`).

**Acceptance Criteria:**
- `step_limit_warning: true` when `tool_count >= 18`
- `step_limit_warning: false` otherwise
- Existing `count`, `turns` fields unchanged

---

### US-DBG-03 — Debug panel in chat UI (collapsible, dev-mode only)

**Story:** As a developer troubleshooting a broken populate, I want an expandable "Debug" section beneath each AI message showing the full tool call sequence for that turn so I can see exactly where execution stopped.

**File:** `webapp/protype-2/src/App.tsx` (or new `DebugPanel.tsx` component)

**UI spec:**
- Hidden by default; shown when `?debug=1` query param is present in the URL
- Appears beneath the `<ActivityChip />` (Layer 1 transparency chip)
- Label: `🔧 Debug — {n} tool calls`
- Expands to a table: `#  |  tool_name  |  input_summary  |  output_summary`
- Rows where `output_summary` contains "Skipped" are highlighted in amber
- Fetches `GET /journey_map/{id}/tool-logs?turn_id={turn_id}` on expand (lazy load)
- Shows `⚠ Step limit warning` banner when `step_limit_warning: true` on the turn

**Acceptance Criteria:**
- Panel is invisible in normal use (no `?debug=1`)
- Lazy-loads tool log data only when expanded
- Skipped rows visually distinct from applied rows
- Step limit warning banner shown when applicable

---

## Build Order

```
US-DBG-01 → US-DBG-02 → US-DBG-03
```

Backend first (01, 02), then frontend panel (03).
US-DBG-01 unblocks everything — it's the missing data access layer.

---

## Out of Scope

- Exporting logs to CSV or external observability tools
- Real-time streaming of tool calls during agent execution
- Log retention policy or cleanup jobs
