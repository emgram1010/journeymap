# EPIC-COP-10 — The AI checks a map against the real publish checklist

**Status:** 🟡 Built and live (2026-11-18, Sonnet 5.5). The Journey Map Assistant (interview mode) does not have the tool yet: see Results.
**Model:** **Sonnet 5.5**. It wraps a function that already exists and is tested.
**Depends on:** PUB-1 (the publish gate, live), COP-1 (`journey/tool_gate`, run tickets).
**Risk:** low. The tool only reads. It never publishes.

---

## 1. Goal

**Pain:** the map AI can build every part of a publishable map (stage names, owner roles, tasks,
durations, "done when", the title), but it can't see the checklist that **Publish version**
uses. Its `get_gaps` tool uses different rules. So it can't tell you "this map will pass",
and you only find out when you press publish and get E-PUB-001.

**Fix:** one read-only AI tool, `check_publish_ready`. It runs **the same server function** that
Publish version uses (`pub/build_map_snapshot` → `exceptions/exception_targets` →
`pub/evaluate_gate`, the chain in endpoint 520) and returns the blockers and warnings in plain
words, with the stage and row for each.

**Win:** the AI fixes what it can, tells you what only you can decide, and says "ready to publish"
only when the server agrees.

### What the checklist checks today (verified 2026-11-18 in `pub/evaluate_readiness` and `pub/evaluate_gate`)

| Code | Meaning |
|---|---|
| `NO_WORK_TYPE_NAME` | The map has no name |
| `NO_STAGES` | The map has no stages |
| `NO_STAGE_NAME` | A stage has no name |
| `NO_OWNER` | A stage has no owner role |
| `OWNER_NOT_WORK_ROLE` | The owner row isn't a work role |
| `NO_TASK` | A work cell has no task |
| `NO_DURATION` | A work cell has no duration |
| `NO_DONE_WHEN` | A stage has no "done when" |
| `PARTIAL_WORK_CELL` | A work cell is half filled |
| (gate) placeholder title | The map is still called "Untitled Journey Map" |
| (gate) inactive item rate | A rate pins an item that has been switched off |

The tool must **not** copy this list. It returns whatever the function returns, so a new rule
added later appears in the tool with no change.

---

## 2. Stories

### US-COP-10-01 — A read-only tool that runs the real checklist

**As an** owner **I want** the AI to check a map with the same rules as Publish version **so that**
"ready" means ready.

```gherkin
Scenario: a map that would pass
  Given a map that passes the publish gate
  When the AI calls check_publish_ready for it
  Then the tool returns ready = true, no blockers, and any warnings

Scenario: a map that would fail
  Given a map with a stage that has no owner and a work cell with no duration
  When the AI calls check_publish_ready
  Then the tool returns ready = false
  And one blocker per problem, each with its code, stage name, row name and a plain message

Scenario: same answer as the server
  Given any map
  Then check_publish_ready's blockers equal the gate_failures that Publish version would return for that map
  # one rule, one place: the tool calls pub/evaluate_gate, it holds no rule of its own

Scenario: it never publishes
  Then the tool writes nothing to the map, its versions or its status
```

### US-COP-10-02 — Only maps the caller may see

**As an** owner **I want** the AI to check only maps in my business **so that** it can't read
another account's map through this door.

```gherkin
Scenario: through the gate
  When the tool runs
  Then it goes through journey/tool_gate with kind "read" and the run ticket, like every map tool

Scenario: a map outside the business or account
  When the AI asks about a map it may not see
  Then the tool refuses with the gate's existing code and logs it in tool_call_log
```

### US-COP-10-03 — All the AIs that build maps get it

**As an** owner **I want** every AI that edits maps to have the check **so that** none of them
says "done" on a map that would fail.

```gherkin
Scenario: the map AIs
  Then Journey Map Builder, Journey Map Assistant and Journey Map Chat Agent list check_publish_ready
  # the Chat Agent is read-only; this tool is read-only, so it fits

Scenario: the main copilot
  Then Emgram Copilot lists check_publish_ready too, since it also creates maps
```

### US-COP-10-04 — The AI uses it before saying "ready"

**As an** owner **I want** the AI to check before it tells me a map is ready **so that** I don't
press publish on a promise.

```gherkin
Scenario: before "ready to publish"
  When the AI is about to tell me a map is ready to publish
  Then it has called check_publish_ready in the same turn and ready was true
  # instruction in each agent's system prompt; measured in the test scenarios, see §5

Scenario: it fixes what it can
  Given blockers it can fix with its own tools (a missing duration, a missing "done when")
  When I asked it to finish the map
  Then it fixes them and checks again

Scenario: it hands back what only I can decide
  Given a blocker that needs my choice (which role owns a stage)
  Then it asks me one question about it rather than guessing
```

---

## 3. Governance

- **Tables:** none. No schema change.
- **Validation:** `journey_map_id` at least 1; the gate does the rest.
- **Error codes:** reuse the gate's existing codes for refusals. **E-COP-088** if the checklist
  function itself fails ("I couldn't run the publish checklist just now. Nothing was changed.").
- **Events:** success and failure of each check in `event_log` (`copilot.publish_check.ran` /
  `.failed`), and the call in `tool_call_log`.
- **Delete behaviour:** none. Read-only.

## 4. Counter-measures

| Risk | Counter-measure |
|---|---|
| The tool and Publish version disagree | The tool calls the same functions as endpoint 520; FT-COP-10-02 compares them on real maps |
| The AI says "ready" without checking | Instruction in the prompt, and a test scenario that asks for "finish and tell me when it's ready" |
| A new checklist rule never reaches the AI | The tool passes the function's output through; no copy of the codes in the tool |
| The tool reads another account's map | `journey/tool_gate` with kind "read" (COP-1) |

## 5. Test plan

| ID | Type | Checks |
|---|---|---|
| FT-COP-10-01 | Function | A passing map → ready true; a failing map → one blocker per problem |
| FT-COP-10-02 | Function | For 3 real maps, the tool's blockers equal endpoint 520's `gate_failures` |
| FT-COP-10-03 | Function | A map outside the account is refused and logged |
| FT-COP-10-04 | Function | The tool changes nothing (map row, versions, status unchanged) |
| AI-COP-10-01 | Real AI chat | "Finish this map and tell me when it's ready": it calls the tool, fixes what it can, says ready only when true |
| UT-COP-10-* | Unit | E-COP-088 in the error catalog; one message per code |

## 6. Test results

**What was built**

| Piece | Where | Live id |
|---|---|---|
| The checklist function (same three functions endpoint 520 chains) | `functions/pub/check_map_ready.xs` | fn 402 |
| The read-only tool | `ai/tool/check_publish_ready.xs` | tool 186 |
| E-COP-088 | `webapp/protype-2/src/ops/errorCatalog.json` | — |
| Listed on | Journey Map Builder (9), Journey Map Chat Agent (10), Emgram Copilot (40); prompts tell them to check first | pushed live |

**Results**

| Check | Result |
|---|---|
| UT-COP-10-01..07 (`cop10Publish.test.ts`) | 7/7 |
| FT-COP-10-01 / 02: the function against endpoint 520 on real maps | Same answer on all three maps 520 would show: map 266 (10 blockers, 1 warning, 0 of 8 ready), map 261 (ready, 2 of 2), map 267 (9 blockers incl. the placeholder-title rule). Map 260 belongs to another user, so 520 refuses it (403); the function returns its 4 stage-owner blockers |
| FT-COP-10-03 / 04 (gate, read-only) | Tool goes through `journey/tool_gate` as a read; the tool and function contain no write. Real calls were logged as `allowed` in `tool_call_log` (rows 389, 391 by the copilot; 392 by the map chat) |
| AI-COP-10-01 real AI (`tests/cop10_ai_probe.py`, result beside it) | 5/5. Map "Day-Before…" → "Not ready", 4 blockers, every stage needs an owner; map "COP-5 chain fixture" → "Yes, ready"; asked to publish → "I can't publish maps – only you can" |
| Map chat (Chat Agent) asked "Is this map ready to publish?" on map 266 | Reported the same 10 blockers and the warning in plain words |

**Not done / differences**
- 🔴 **Journey Map Assistant (id 18, interview mode) does not have the tool live.** Its repo file said `system_prompt: "temp"` while the live agent holds a 70,000-character prompt, so pushing from the file would have wiped it, and pushing the live text means re-sending all of it. The repo file is now refreshed from the live source (with the tool added) and **not pushed**. **Founder, 10 seconds in Xano:** AI → Agents → Journey Map Assistant → Tools → add `check_publish_ready` (and `get_how_i_work`, COP-12) → save.
- The function copies endpoint 520's glue (Items-row rates) rather than being called by it. Both call the same three functions; FT-COP-10-02 guards drift. Switching 520 and Publish version (201) to call it is a separate, careful change.
- Publish version (201) calls the gate without the Items and exception inputs; those only add warnings, so its blockers equal the tool's.
- Found while here: the live Builder prompt contains leftover merge-conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) and a duplicated "Stage Contract awareness" block. Left as it was; worth a clean-up.
