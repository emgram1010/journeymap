# Validation — Phase 3: "I Don't Know" Protocol

**Problem this phase solves:** When an AI hits a gap — missing context, ambiguous instruction, a situation not covered by the map — the path of least resistance is to fill it in with a plausible guess and keep moving. That is hallucination. There is currently no explicit instruction that forces the AI to stop, flag the gap, and refuse to proceed. Silence and forward motion are treated as the same thing.

**Goal:** Define `BLOCKED` and `NOVEL_EXCEPTION` as first-class output states. Establish the exact conditions that trigger each, the exact format the AI must emit when it hits one, and the escalation path that follows. Make "I don't know" a required, structured response — not a failure mode.

**Dependency:** Phases 1 and 2 define what "done" looks like. This phase defines what happens when the AI cannot reach "done."

**Exit condition for this phase:** An AI agent running any atomic map has explicit, unambiguous instruction to stop and flag rather than hallucinate forward. The BLOCKED and NOVEL_EXCEPTION states are documented in skills files and produce structured, actionable output.

---

## US-VAL-07 — BLOCKED Status Definition and Trigger Conditions

**What:** Define `BLOCKED` as a required output state with specific trigger conditions. The AI must emit a BLOCKED signal — not a workaround — when any of these conditions are true.

**BLOCKED trigger conditions:**
| Condition | Required AI response |
|---|---|
| Validator cell is empty for the current stage | `BLOCKED [stage_key]: Acceptance criteria not defined. Cannot validate output.` |
| Stage has no `stage_goal` (exit condition) | `BLOCKED [stage_key]: Exit condition missing. Completion cannot be verified.` |
| Output does not satisfy a Validator criterion | `BLOCKED [stage_key]: Output fails criterion — "[exact criterion text]"` |
| Required field missing (`time_duration`, `cost_rate`) | `BLOCKED [stage_key]: Required field [field_name] not set. Leakage math incomplete.` |
| Primary actor identity not defined on lens | `BLOCKED [lens_key]: Actor persona_description or cost_rate not set.` |

**Rules for BLOCKED:**
- BLOCKED is a stop — the AI does not proceed to the next stage while a BLOCKED exists
- BLOCKED must cite the specific stage key and specific condition — not a generic message
- BLOCKED must be resolved by fixing the root cause — not by lowering the criteria
- The AI may not re-label a BLOCKED stage as complete without re-running the Validator check

**Acceptance criteria:**
- HARD RULE block in `instructions.md` lists all BLOCKED trigger conditions
- AI emits BLOCKED with stage_key and condition string — never a generic "something went wrong"
- BLOCKED stages are surfaced in the validation report (US-VAL-09) with reasons

---

## US-VAL-08 — NOVEL_EXCEPTION Flag and Escalation Path

**What:** Define `NOVEL_EXCEPTION` as a special subtype of BLOCKED for situations the map never anticipated. When an AI encounters a scenario with no handling path in the map, it stops, documents it precisely, and escalates — it does not invent a resolution.

**NOVEL_EXCEPTION trigger:** Any situation that meets all of the following:
- The current stage has a defined Validator cell (so it is not a BLOCKED due to missing criteria)
- The AI cannot produce an output that satisfies any of the acceptance criteria
- The failure is not due to a missing field — it is due to a scenario the map did not account for

**Required AI behavior on NOVEL_EXCEPTION:**
1. Stop execution at the current stage — do not advance
2. Emit: `NOVEL_EXCEPTION [stage_key]: [Plain language description of the unhandled situation]`
3. Surface to the human or orchestrator: "This situation is not covered by the map. I cannot proceed without guidance."
4. Do NOT invent a resolution, approximate a workaround, or mark the stage complete
5. Log the exception description for map review

**Escalation path:**
- Novel exceptions are collected and reviewed by the map owner
- Each resolved novel exception becomes a candidate for a new `exception` sub-journey linked via `link_map`
- The map learns from what it missed — the exception backlog is the improvement signal

**Acceptance criteria:**
- NOVEL_EXCEPTION is defined separately from BLOCKED in `instructions.md`
- AI has explicit instruction that inventing a resolution is a protocol violation
- NOVEL_EXCEPTION output includes a plain-language description sufficient for a human to understand what happened

---

## US-VAL-09 — Structured Validation Report

**What:** After running all three passes (content, leakage fields, Validator check), the AI produces a single structured validation report before offering any publish action. The report makes the map's readiness state explicit and actionable.

**Validation report schema:**
```json
{
  "map_id": 162,
  "map_title": "Discovery-Interview-L3",
  "validated_at": "ISO timestamp",
  "pass_1_content": { "passed": true, "gap_count": 0 },
  "pass_2_leakage": { "passed": true, "incomplete_cells": [] },
  "pass_3_validator": {
    "passed": false,
    "blocked_stages": [
      {
        "stage_key": "s4",
        "reason": "Output fails criterion — 'Cost rate must be sourced from prospect, not estimated'"
      }
    ]
  },
  "novel_exceptions": [],
  "ready_for_publish": false,
  "next_action": "Resolve 1 blocked stage before publishing."
}
```

**Rules:**
- `ready_for_publish` is only `true` when all three passes return clean
- The report is always shown to the user before a publish action is offered
- The AI does not offer to publish if `ready_for_publish = false`
- `next_action` is always a specific, actionable instruction — not "review the map"

**Acceptance criteria:**
- Validation report is produced after every build or update session on an atomic map
- Report is shown to user before any publish is offered
- `ready_for_publish: false` blocks the publish offer — AI asks user to resolve first
