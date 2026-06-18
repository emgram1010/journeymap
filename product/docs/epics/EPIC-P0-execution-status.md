# EPIC P0-3: Stage Execution Status Enum

**PRD:** `product/docs/prd/PRD-runtime-engine.md`
**Priority:** P0 — runtime produces pass/fail only; no computed execution state
**Inspired by:** Telogis `Job.JobStatus` (OK | Late | Early | Missed) + Fleet WorkPlan FSM

---

## Problem

The runtime runs 4 checks and returns `true | false` per check. That's it. There is no computed
state for how a stage is doing relative to its contract.

An operator watching their operation cannot answer:
- "Is job-9981 running late right now?" — no live status
- "How many jobs were blocked by constraints this week?" — no status history
- "Which stages are chronically missed?" — no pattern data

The runtime is a check engine, not a state machine. It needs both.

---

## Solution

Add a computed `stage_status` enum. The runtime sets this on every event processed.

Current code reality: `workflow_execution.status` already exists at the run level (`pending`, `running`, `paused`, `completed`, `failed`, `cancelled`). The new `stage_status` must be stage-level and should not replace run-level status. Initial storage can live in `workflow_execution.stage_outputs[stage_key].status` and/or `event_log.metadata.stage_status`.

### Status Enum

| Status | Condition | Leakage Impact |
|---|---|---|
| `pending` | Stage not yet started; expected but no event received | None |
| `active` | Stage started; within planned_duration window | None |
| `on_time` | Stage completed; actual_duration ≤ planned_duration | None |
| `late` | Stage completed; actual_duration > planned_duration | ✅ Adds to leakage delta |
| `early` | Stage completed; actual_duration < (planned_duration × 0.5) | Log only — may signal skipped steps |
| `missed` | Stage expected; no event within (planned_duration + tolerance) | ✅ Full stage cost to leakage |
| `blocked` | Hard constraint fired; stage halted | ✅ Adds blocked-time to leakage |
| `wrong_order` | Event arrived at this stage out of sequence | ✅ Sequence violation flag |

### Computation Logic

```
On event received for stage_key:
  actual_duration provided?
    YES → compare to planned_duration
          actual ≤ planned                         → status = "on_time"
          actual > planned AND ≤ max_duration      → status = "late"
          actual > max_duration (if set)            → status = "blocked" (hard cap exceeded)
          actual < planned × 0.5                   → status = "early"
    NO  → stage_goal check passed?
          goal not yet met, within window          → status = "active"
          goal not met, window exceeded            → status = "missed"

sequence_ok = false?
  → status = "wrong_order" (overrides other status)

constraints_ok = false + severity = critical?
  → status = "blocked" (overrides other status)
```

---

## User Stories

### US-1: See live stage status for an active journey instance
**As an** operator monitoring a job in progress,
**I want to** see the current `stage_status` for each stage of that job so that
**I can intervene before a late stage cascades.**

Acceptance:
- [ ] `GET /journey_map/{id}/execution_health?external_ref_id=job-9981` returns `stage_status` per stage
- [ ] Status reflects latest event — not cached from publish
- [ ] `active` status includes time elapsed vs planned_duration

### US-2: Aggregate status across all runs of a map
**As an** operator reviewing a week of operations,
**I want to** see a breakdown of `on_time | late | missed | blocked` across all job instances so that
**I can see which stages are chronically problematic.**

Acceptance:
- [ ] `GET /journey_map/{id}/execution_health` (no ref filter) returns aggregate counts per stage per status
- [ ] `late_rate` = `late_count / total_count` per stage
- [ ] `missed_rate` = `missed_count / total_count` per stage
- [ ] Both feed into `calculate_leakage` leakage_ratio

### US-3: Stage status feeds leakage math
**As the** leakage math engine,
**I need** `late` and `missed` counts per stage so that
**`leakage_ratio` is computed from real execution data.**

Acceptance:
- [ ] `calculate_leakage` reads `stage_status` history from `event_log`
- [ ] `leakage_ratio = (late_count + missed_count + blocked_count) / total_executions`
- [ ] `early` status is logged but excluded from leakage ratio (not a cost signal)

---

## Downstream Impact

When P0-3 ships, update:
- `emgram-skills/skills/atomic_runtime_template.md` — add stage_status to readiness checklist
- `product/docs/02-VOCABULARY.md` — stage status enum definitions already stubbed
- `calculate_leakage` tool — use status data instead of estimated leakage_ratio

---

## References

- `product/learnings/telogis-tde-architecture-analysis.md` — Section 4: Job Table as Stage Execution Record
- `product/learnings/fleet-route-lifecycle-analysis.md` — Phase 3: Job Status enum
- `product/docs/prd/PRD-runtime-engine.md` — Parent PRD
- `product/docs/epics/EPIC-P0-violation-log.md` — Violation data feeds leakage_ratio here
- `product/docs/architecture/RUNTIME-EVENT-CONTRACT.md` — Event ordering and idempotency rules
