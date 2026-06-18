# PRD: Runtime Engine — Conformance, Constraints, and Dispatch

> The runtime is the proof. Without accurate constraint enforcement and execution status,
> the leakage number is guesswork.

---

## Problem

The current runtime engine runs 4 checks per incoming webhook event. But two of those checks
are structurally incomplete:

Current code reality:
- `event_log` exists today as generic `action` + `metadata`, not a dedicated violation table.
- `workflow_execution.validation_snapshot` already exists and is the natural place to persist pre-flight validation/dispatch output.
- `automation_snapshot` is currently upserted per map with a version increment, not historical append-only snapshot storage.

- **`constraints_ok`** reads `standing_constraints` — a free-text blob. The runtime cannot
  distinguish between a hard violation (block the stage) and a soft violation (log + leakage).
  Every constraint failure today is a silent binary pass/fail.

- **`duration_ok`** produces a boolean. There is no computed status (`late | missed | blocked`).
  The leakage math uses the delta, but the operator cannot see the execution state of a stage.

Additionally, there is **no Dispatch layer** between publish and execute. In logistics, the Route
Builder runs all constraint checks *before* a driver starts the route and surfaces a violations
report for human review. emgram skips this step entirely — constraint failures are only discovered
at runtime, during an active execution.

---

## Solution

### P0: Constraint Severity Model

Replace `standing_constraints` (text blob) with a structured `stage_constraints[]` array:

```json
{
  "rule": "Technician must hold active cert",
  "severity": "critical",
  "time_to_trigger": 0,
  "failure_mode": "block"
}
```

Severity levels:
- `critical` → **hard block** — execution cannot advance past this stage
- `major` → **soft warn** — logs violation + adds to leakage delta, journey continues
- `normal` → **log only** — records event, no execution impact

### P0: Constraint Violation Log

When a constraint fires, write a structured `constraint_violation` event:
```json
{
  "stage_key":        "s3",
  "lens_key":         "l1",
  "constraint_rule":  "Technician must hold active cert",
  "severity":         "critical",
  "trigger_value":    "cert_expired",
  "time_on":          "2026-06-12T09:14:00Z",
  "time_off":         null,
  "execution_ref_id": "job-9981"
}
```

Hard violations block event ingestion. Soft violations log + contribute to leakage delta.

### P0: Stage Execution Status Enum

Compute `stage_status` from planned vs. actual delta at runtime:

| Status | Condition |
|---|---|
| `pending` | Stage not yet started |
| `active` | Stage started, within planned_duration |
| `on_time` | Stage completed within planned_duration |
| `late` | Stage completed but actual_duration > planned_duration |
| `missed` | Stage expected but no event received within tolerance |
| `blocked` | Hard constraint fired — stage halted |

### P1: Dispatch Layer

Add a pre-execution validation step between `publish_map` and live execution:

1. Operator assigns actor to a journey instance
2. Runtime runs all constraint checks against the published snapshot
3. Violations report returned: list of `stage_key`, `constraint_rule`, `severity`
4. Hard violations must be resolved before execution can start
5. Soft violations surface as warnings — operator can acknowledge and proceed

**This separates "constraint check" from "execution start"** — the same way Fleet's Route Builder
shows violations before a driver touches a route.

### P1: Time Tolerance

Add `time_tolerance_value` (minutes) alongside `planned_duration` on stage cells:

- `planned_duration` exceeded but within `±tolerance` → no violation
- `planned_duration + tolerance` exceeded → soft violation (`major`)
- `max_duration` exceeded → hard violation (`critical`)

---

## Epics Under This PRD

| Epic | Priority | File |
|---|---|---|
| Constraint Engine (severity model) | P0 | `epics/EPIC-P0-constraint-engine.md` |
| Violation Log (structured record) | P0 | `epics/EPIC-P0-violation-log.md` |
| Stage Execution Status Enum | P0 | `epics/EPIC-P0-execution-status.md` |
| Dispatch Layer (pre-flight) | P1 | `epics/EPIC-P1-dispatch-layer.md` |

---

## Acceptance Criteria

- [ ] `stage_constraints[]` replaces `standing_constraints` on actor identity
- [ ] Hard constraint violation halts event ingestion and returns error to caller
- [ ] Soft constraint violation writes a `constraint_violation` record and continues
- [ ] `stage_status` is computed and returned with every runtime check result
- [ ] Dispatch endpoint accepts a journey instance + actor assignment, runs all checks, returns violations list
- [ ] `calculate_leakage` uses violation log counts for `leakage_ratio` — not just duration delta

---

## Inspiration

- Telogis `Condition.Severity` (Normal | Major | Critical) — constraint severity model
- Telogis `Alert` table (TimeOn, ConditionId, TriggerValue) — violation log pattern
- Fleet `Job.JobStatus` (OK | Late | Early | Missed) — stage status enum
- Fleet Route Builder violations summary — dispatch pre-flight check

See `product/learnings/telogis-tde-architecture-analysis.md` and
`product/learnings/fleet-route-lifecycle-analysis.md` for full schema details.

---

## References

- `product/docs/01-ARCHITECTURE.md` — Runtime check field mapping
- `product/docs/02-VOCABULARY.md` — Constraint and status term definitions
- `product/docs/ROADMAP.md` — P0/P1 priority context
- `product/docs/architecture/CONSTRAINT-OWNERSHIP.md` — Where rules live before schema changes
- `product/docs/architecture/RUNTIME-EVENT-CONTRACT.md` — Stable inbound event contract
- `product/docs/architecture/SNAPSHOT-VERSIONING.md` — Snapshot binding rules
- `product/docs/architecture/SECURITY-WEBHOOKS.md` — Webhook authentication expectations
- `emgram-skills/skills/atomic_runtime_template.md` — Current readiness checklist (to be updated when P0 ships)
