# EPIC P1-1: Dispatch Layer — Pre-Execution Validation

**PRD:** `product/docs/prd/PRD-runtime-engine.md`
**Priority:** P1 — unlocks reliable runtime enforcement before execution starts
**Depends on:** P0 constraint engine + violation log
**Inspired by:** Fleet Route Builder violations summary + WorkPlan actor assignment

---

## Problem

Today `publish_map` jumps directly from blueprint to live execution. There is no phase where:
- Constraints are checked before execution starts
- An actor is explicitly assigned to a journey instance
- Violations are surfaced for human review before the first webhook fires

In logistics, the Route Builder runs all constraint checks after optimization and *before* the
driver touches the route. A violations report is shown. Hard violations must be cleared. Only then
does the "publish to driver" action proceed.

emgram has no equivalent. Constraint failures are only discovered during live execution — too late
to prevent them, only possible to record them.

---

## Solution

Add a **Dispatch step** between `publish_map` and live execution.

Current code reality: `validate_workflow` already acts like a pre-flight checker for AI Orchestrator mode, and `workflow_execution.validation_snapshot` already exists. Dispatch should build from this pattern instead of duplicating it. External `dispatch_token` behavior is future-facing for webhook mode.

### The 3-Step Dispatch Flow

```
1. ASSIGN       → operator assigns actor(s) to a journey instance
2. VALIDATE     → runtime runs all constraints against the assignment
3. DISPATCH     → violations reviewed; hard violations cleared; execution unlocked
```

### New Endpoint: POST /journey_map/{id}/dispatch

**Input:**
```json
{
  "external_ref_id": "job-9981",
  "actor_assignments": [
    { "lens_key": "l1", "actor_id": "tech-447", "actor_tags": ["CDL-A", "ForkLift"] }
  ],
  "scheduled_start": "2026-06-13T08:00:00Z"
}
```

**Output — violations report:**
```json
{
  "dispatch_ready": false,
  "hard_violations": [
    {
      "stage_key": "s3",
      "lens_key":  "l1",
      "rule":      "Technician must hold active cert",
      "severity":  "critical",
      "reason":    "Actor tech-447 missing tag: CertifiedTech"
    }
  ],
  "soft_violations": [
    {
      "stage_key": "s5",
      "lens_key":  "l1",
      "rule":      "Preferred start window is 08:00–10:00",
      "severity":  "major",
      "reason":    "Scheduled start 08:00 is at edge of window"
    }
  ],
  "dispatch_token": null
}
```

When `hard_violations` is empty:
```json
{
  "dispatch_ready": true,
  "hard_violations": [],
  "soft_violations": [ ... ],
  "dispatch_token": "dtk_8a91c3"
}
```

The `dispatch_token` is passed with subsequent webhook events to link them to this instance.

### Time Tolerance Field

Add `time_tolerance_value` (int, minutes) to stage cells:
- `planned_duration` exceeded but within tolerance → no violation
- `planned_duration + tolerance` exceeded → soft violation (`major`)
- `max_duration` (if set) exceeded → hard violation (`critical`)

---

## User Stories

### US-1: Run constraint check before execution starts
**As an** operator assigning a technician to a job,
**I want to** see any constraint failures before the job starts so that
**I can reassign or resolve issues proactively.**

Acceptance:
- [ ] `POST /dispatch` runs all `stage_constraints[]` against actor assignments
- [ ] Hard violations returned with stage, rule, actor, reason
- [ ] Soft violations returned separately — operator can acknowledge and proceed
- [ ] `dispatch_ready: true` only when zero hard violations remain

### US-2: Block execution if hard violations not cleared
**As the** runtime engine,
**I need** to reject webhook events without a valid `dispatch_token` so that
**executions cannot start without passing dispatch validation.**

Acceptance:
- [ ] Events without `dispatch_token` (or with invalid token) return HTTP 403
- [ ] Token is bound to `external_ref_id` + `journey_map_id` + snapshot version
- [ ] Expired tokens (after `scheduled_start + buffer`) are rejected

### US-3: Actor tag requirement check at dispatch
**As an** operator with stage-level skill requirements,
**I want** dispatch to check that the assigned actor has the required tags so that
**unqualified actors are flagged before execution, not during.**

Acceptance:
- [ ] `stage_constraints[]` can include `required_actor_tags: ["CDL-A"]`
- [ ] Dispatch checks `actor.actor_tags ⊇ stage.required_actor_tags`
- [ ] Mismatch = hard violation (critical) returned in violations report

---

## References

- `product/learnings/fleet-route-lifecycle-analysis.md` — Section: Phase 2 Dispatch
- `product/learnings/telogis-tde-architecture-analysis.md` — Section 6: Tag-Based Constraint Matching
- `product/docs/prd/PRD-runtime-engine.md` — Parent PRD
- `product/docs/epics/EPIC-P0-constraint-engine.md` — Constraint severity model (P0 dependency)
- `product/docs/epics/EPIC-P0-violation-log.md` — Violation record (P0 dependency)
- `product/docs/architecture/SNAPSHOT-VERSIONING.md` — Snapshot binding to dispatch/execution
- `product/docs/DEPENDENCY-MAP.md` — Parallel/sequential build order
