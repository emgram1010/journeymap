# AI Agent Orchestrator — Bug Fixes

**Date:** 2026-04-10
**Status:** ✅ FIXED
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
**Discovered via:** Playwright smoke test against live Xano backend

---

## BUG F1 — `Unable to locate var: agent_response.content` (HTTP 500)

### Symptom
Every `POST /journey_map/{id}/ai_message` call returns:
```json
{"code": "ERROR_FATAL", "message": "Unable to locate var: agent_response.content"}
```

### Root Cause
The orchestrator reads `$agent_response.content` after the `group { stack { } }` block,
but the working Xano demo agent pattern (`9_demo_agent_conversation_POST.xs`) shows
that the agent result lives at `$agent_response.result` — not `.content`.

**Working demo pattern:**
```xs
group {
  stack {
    ai.agent.run "Xano Example Agent" {
      args = {}|set:"messages":$messages
      allow_tool_execution = true
    } as $Simple_Agent1
  }
}

var $agent_response {
  value = $Simple_Agent1.result
}
```

**Our broken pattern:**
```xs
group {
  stack {
    ai.agent.run "Journey Map Assistant" {
      args = {}|set:"messages":$agent_messages
      allow_tool_execution = true
    } as $agent_response
  }
}

// Then directly reads $agent_response.content — WRONG
```

### Fix
After the `group { stack { } }` block, extract the result into a new variable,
then use that variable for reply text extraction:

```xs
// ── Call the agent ──
group {
  stack {
    ai.agent.run "Journey Map Assistant" {
      args = {}|set:"messages":$agent_messages
      allow_tool_execution = true
    } as $agent_run
  }
}

// Extract the agent result (accessible outside group scope)
var $agent_result {
  value = $agent_run.result
}

// ── Extract assistant reply text ──
// $agent_result is a string (the agent's text reply)
var.update $reply_text {
  value = $agent_result
}
```

This eliminates:
1. The `.content` property access that doesn't exist
2. The `api.lambda` extraction step (the result is already a plain string)
3. The conditional null-check on a non-existent property

### Lines changed
- ✅ **Replaced lines 390-422** — renamed `$agent_response` → `$agent_run`, added `$agent_result = $agent_run.result`, removed `api.lambda` block, simplified to direct string assignment

---

## BUG F2 — `api.lambda` extraction is unnecessary

### Symptom
The orchestrator uses `api.lambda` with inline JavaScript to extract text from
`$agent_response.content` as if it were a structured array. But the demo shows
that `ai.agent.run` returns a plain string in `.result`.

### Root Cause
Assumed the agent response shape was `{content: [{type: "text", text: "..."}]}`.
In reality, `$agent_run.result` is already the plain text reply string.

### Fix
✅ Removed the `api.lambda` block entirely. `$agent_run.result` assigned directly to `$reply_text`.
See the fix in BUG F1 above.

---

## Verification

After applying fixes, the expected flow is:
1. `POST /journey_map/61/ai_message` with `{content: "hello", mode: "chat"}` → **200**
2. Response contains `reply` with actual AI-generated text (not hardcoded)
3. Frontend displays the real agent reply in the chat sidebar
4. If mode is `interview`, cells may be updated and returned in `cell_updates`

### Test command (curl)
```bash
curl -X POST "https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ/journey_map/61/ai_message" \
  -H "Content-Type: application/json" \
  -d '{"content": "hello", "mode": "chat"}'
```

Expected: 200 with `{"reply": "...", "cell_updates": [], ...}`
