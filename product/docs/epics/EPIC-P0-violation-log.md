# EPIC P0-2: Constraint Violation Log

**PRD:** `product/docs/prd/PRD-runtime-engine.md`
**Priority:** P0 — blocks leakage accuracy and audit trail
**Depends on:** `EPIC-P0-constraint-engine.md` (severity model must ship first)
**Inspired by:** Telogis `Alert` table (`TimeOn`, `TimeOff`, `ConditionId`, `TriggerValue`)

---

## Problem

When `constraints_ok = false` fires today, nothing is recorded. No audit trail. No data for the
leakage math to consume. No way for the operator to see *which* constraint failed, *how often*,
or *how much it cost*.

The leakage formula uses `leakage_ratio` — but today that ratio is manually estimated. Without a
violation log, there is no objective data to compute it from. Every leakage number is a guess.

---

## Solution

When a constraint fires at runtime, write a structured `constraint_violation` event to the
`event_log` table.

Current code reality: `event_log` has `action` and `metadata`. The first implementation should use `action = "constraint_violation"` and store the full structured payload in `metadata`. Do not create a dedicated violation table until event volume/query needs prove it is required.

### Violation Record Schema

```json
{
  "event_type":        "constraint_violation",
  "journey_map_id":    42,
  "stage_key":         "s3",
  "lens_key":          "l1",
  "external_ref_id":   "job-9981",
  "constraint_rule":   "Technician must hold active cert",
  "severity":          "critical",
  "trigger_value":     "cert_status=expired",
  "failure_mode":      "block",
  "time_on":           "2026-06-12T09:14:00Z",
  "time_off":          "2026-06-12T09:18:00Z",
  "resolved":          false,
  "snapshot_version":  7
}
```

### Field Definitions

| Field | Description |
|---|---|
| `event_type` | Always `"constraint_violation"` — allows filtering in event_log |
| `journey_map_id` | The map that defined the violated constraint |
| `stage_key` | Stage where violation occurred |
| `lens_key` | Actor lens whose constraint fired |
| `external_ref_id` | The job/case/call instance — threads all events for one execution |
| `constraint_rule` | The rule text from `stage_constraints[]` |
| `severity` | `critical | major | normal` |
| `trigger_value` | The actual value that caused the breach (from inbound event payload) |
| `failure_mode` | `block | warn | log` |
| `time_on` | When violation started |
| `time_off` | When violation ended (null if still active) |
| `resolved` | Whether the violation was manually cleared |
| `snapshot_version` | Which published snapshot was active when violation fired |

---

## Runtime Behavior

```
Inbound event arrives
  → constraint check runs (EPIC-P0-constraint-engine)
  → constraint fires
      → write constraint_violation record
      → if severity = critical: reject event, return { blocked: true, violation_id: X }
      → if severity = major:    continue, add (time_over × cost_rate) to leakage_delta
      → if severity = normal:   continue, record only
```

---

## User Stories

### US-1: See which constraints failed on a specific job
**As an** operator reviewing a completed journey,
**I want to** see a list of all constraint violations for that job instance so that
**I can understand what went wrong and why.**

Acceptance:
- [ ] `GET /event_log?external_ref_id=job-9981&event_type=constraint_violation` returns all violations for that instance
- [ ] Each record includes rule, severity, trigger_value, timestamps
- [ ] Violations are ordered by time_on ASC

### US-2: leakage_ratio computed from violation data
**As the** leakage math engine,
**I need** total violations per stage per map so that
**`calculate_leakage` produces an accurate ratio instead of an estimate.**

Acceptance:
- [ ] `calculate_leakage` queries `event_log` for `event_type = constraint_violation` per `stage_key`
- [ ] `leakage_ratio` = `violation_count / total_executions` for that stage
- [ ] Returns computed ratio alongside the leakage number

### US-3: Hard violation blocks the caller
**As an** external system sending events,
**I need** a clear error response when a hard constraint blocks my event so that
**I can handle the rejection and route to the exception map.**

Acceptance:
- [ ] Critical violation returns HTTP 422 with `{ "blocked": true, "stage_key": "s3", "violation_id": 91, "rule": "..." }`
- [ ] Caller can use `violation_id` to fetch full violation details
- [ ] Exception map link (if configured) is included in response as `exception_map_id`

---

## References

- `product/learnings/telogis-tde-architecture-analysis.md` — Section 2: Alert as Violation Log
- `product/docs/prd/PRD-runtime-engine.md` — Parent PRD
- `product/docs/epics/EPIC-P0-constraint-engine.md` — Constraint severity model (must ship first)
- `product/docs/epics/EPIC-P0-execution-status.md` — Stage status enum (companion P0)
- `product/docs/architecture/RUNTIME-EVENT-CONTRACT.md` — Event payload and idempotency rules
- `product/docs/architecture/OBSERVABILITY.md` — Logging expectations
