# Execution — Phase 3: Novel Exception Capture, Escalation & Operations Dashboard

**Problem this phase solves:** Two related gaps. First: when an AI hits a situation the map never anticipated, there is no formal path — the agent either halts with a vague error or invents a resolution. Novel exceptions are invisible. Second: all the structured execution data built in Phases 1 and 2 has no UI surface. Map owners cannot see which stages fail most, which runs were blocked, or what the novel exceptions were. The execution data exists but produces no operational intelligence.

**Goal:** Formalize novel exception capture and escalation so every unhandled situation is documented, surfaced, and converted into a map improvement signal. Then surface all execution data in the UI — giving map owners a command center view of how their maps perform across runs.

**Dependency:** Phases 1 and 2 must be complete. Novel exceptions write to `per_stage_log`. The dashboard reads from `per_stage_log` and the upgraded `execution_health` endpoint.

**Exit condition for this phase:** Every novel exception produces a structured, queryable record. Novel exceptions feed a backlog that improves the map. The UI shows an execution timeline overlay, per-stage health metrics, and a full run history.

---

## US-EXE-07 — Novel Exception Instruction in Skills Files

**What:** Add explicit instruction to `emgram-skills/instructions.md` that defines the AI's required behavior when it encounters an unhandled situation during execution. This is the instruction-layer complement to the data-layer `novel_exception_flag` field.

**Required AI behavior on NOVEL_EXCEPTION (add to instructions.md as HARD RULE):**

```
NOVEL EXCEPTION PROTOCOL — HARD RULE

When the AI encounters a situation during execution that:
  - Cannot be resolved by any acceptance criterion in the Validator cell
  - Is not a missing field (that would be BLOCKED)
  - Is a scenario the map simply did not anticipate

The AI MUST:
  1. Stop execution at the current stage — do not advance
  2. Write to per_stage_log: { status: "novel_exception", novel_exception_flag: true,
     novel_exception_description: "[plain language description of the unhandled situation]" }
  3. Surface to the user: "I encountered a situation this map does not cover. I cannot
     proceed without guidance. See novel exception at stage [stage_key]."
  4. Do NOT invent a resolution
  5. Do NOT mark the stage complete or skip it silently

Inventing a resolution to avoid a novel exception is a protocol violation.
```

**Acceptance criteria:**
- NOVEL_EXCEPTION HARD RULE exists in `instructions.md`
- The rule explicitly states that inventing a resolution is a protocol violation — not just discouraged
- AI has a clear definition distinguishing BLOCKED (missing field/criterion failure) from NOVEL_EXCEPTION (unhandled scenario)

---

## US-EXE-08 — Novel Exception Log API

**What:** Expose a dedicated endpoint that returns all novel exceptions across all runs for a given map. This gives map owners a queryable backlog of unhandled situations — the raw material for improving the map.

**Endpoint:** `GET /journey_map/{id}/novel_exceptions`

**Response schema:**
```json
{
  "journey_map_id": 162,
  "total": 3,
  "novel_exceptions": [
    {
      "execution_id": 47,
      "stage_key": "s5",
      "stage_label": "Leakage Trigger",
      "description": "Prospect disclosed a regulatory cap on overtime that changes the leakage formula — not addressed in map",
      "flagged_at": "ISO timestamp",
      "resolved": false,
      "resolution_link_map_id": null
    }
  ]
}
```

**Escalation path — novel exception → map improvement:**
- When `resolved` is set to `true`, the exception is associated with a new `journey_link` of type `exception`
- The linked map is the exception-handling sub-journey built to address this scenario
- `resolution_link_map_id` stores the ID of that sub-journey map

**Acceptance criteria:**
- `GET /journey_map/{id}/novel_exceptions` returns all novel exceptions across all runs
- Each exception links to its `execution_id` and `stage_key` for full traceability
- Marking an exception `resolved` requires a `resolution_link_map_id` — resolution without a linked map is not valid

---

## US-EXE-09 — Operations Dashboard (Execution Intelligence UI)

**What:** Surface execution data in the journey map UI so map owners have a command center view: which runs completed, which stages are the highest failure points, and what the novel exceptions are. This is the "read" layer on top of the data built in Phases 1 and 2.

**Three views to add:**

**View 1 — Execution Timeline Overlay**
- On the journey map grid, each stage column shows a status indicator per recent run
  - ✅ `complete` / 🔴 `blocked` / ⏱ `delayed` / ⚠️ `skipped` / 🆕 `novel_exception`
- Clicking a stage indicator shows the full `per_stage_log` entry for that run: actor, duration, validation result, skip reason
- Togglable — does not replace the map content view

**View 2 — Stage Health Panel**
- Upgrade `execution_health_GET.xs` to read from `per_stage_log[].status` instead of blob inference
- Surface per-stage metrics: total runs, complete rate, blocked rate, avg duration ms, top skip reasons
- Flag stages where `blocked_rate > 0.20` as critical — shown with a red indicator
- Powered by the existing `GET /journey_map/{id}/execution_health` endpoint (upgraded data source)

**View 3 — Run History List**
- Extend `GET /journey_map/{id}/workflow_executions` response to include per-run summary:
  - Stages complete, stages blocked, novel exceptions count, gate timestamps, duration
- Filter by: `status`, `assigned_to_type`, date range
- Each run is expandable to show full `per_stage_log`

**Acceptance criteria:**
- Execution timeline overlay is visible on the journey map grid (toggle on/off)
- Stage health panel shows real per-stage metrics from structured `per_stage_log` data
- Run history list shows per-run summaries with `per_stage_log` expandable per run
- Novel exception count is surfaced in run history — clicking it links to the novel exceptions log 