# EPIC P0-1: Constraint Severity Engine

**PRD:** `product/docs/prd/PRD-runtime-engine.md`
**Priority:** P0 — blocks runtime accuracy
**Inspired by:** Telogis `Condition` table (`Severity`, `IsEnabled`, `TimeToTrigger`, `Aggressive`)

---

## Problem

`standing_constraints` on actor identity is a free-text blob. The runtime reads it but cannot
enforce anything. Every constraint is treated identically — there is no hard block vs soft warn.

An operator writes: "Technician must hold active certification."
The runtime reads that string, compares it against the inbound event payload, and returns
`constraints_ok: true | false`. But if it's false, nothing happens — no block, no log, no leakage signal.

This means the `constraints_ok` check is decorative. It produces a value, but that value has
no downstream consequence. The platform cannot enforce its own contracts.

---

## Solution

Replace `standing_constraints` (text blob) with a structured `stage_constraints[]` array.

### Schema

```json
{
  "stage_constraints": [
    {
      "rule":            "Technician must hold active cert",
      "severity":        "critical",
      "time_to_trigger": 0,
      "schedule_window": null,
      "failure_mode":    "block"
    },
    {
      "rule":            "Completion photo required",
      "severity":        "major",
      "time_to_trigger": 5,
      "schedule_window": null,
      "failure_mode":    "warn"
    }
  ]
}
```

### Severity Levels

| Severity | Failure Mode | Runtime Behavior |
|---|---|---|
| `critical` | `block` | Hard stop — event rejected, stage cannot advance |
| `major` | `warn` | Soft warn — violation logged, leakage delta += cost, journey continues |
| `normal` | `log` | Record event only, no execution impact |

### Fields

| Field | Type | Description |
|---|---|---|
| `rule` | Text | Human-readable constraint statement |
| `severity` | Enum | `critical | major | normal` |
| `time_to_trigger` | Int (minutes) | Grace period before violation fires (0 = immediate) |
| `schedule_window` | Object or null | Optional time-of-day scoping (e.g., only enforce Mon-Fri 8-5) |
| `failure_mode` | Enum | `block | warn | log` — derived from severity but overridable |

---

## User Stories

### US-1: Define hard constraint on stage
**As an** operator building a compliance journey,
**I want to** mark a constraint as "critical" so that
**the runtime blocks any execution that violates it.**

Acceptance:
- [ ] `stage_constraints[]` field accepted by `update_actor_identity`
- [ ] `severity: "critical"` constraint fires immediately (time_to_trigger = 0 by default)
- [ ] Runtime returns `constraints_ok: false` + `failure_mode: "block"` when critical constraint violated
- [ ] Block halts event ingestion — no `duration_ok` or `goal_met` check runs

### US-2: Define soft constraint that logs + leakage
**As an** operator wanting to track process quality without blocking execution,
**I want to** mark a constraint as "major" so that
**violations are recorded and added to leakage without stopping the journey.**

Acceptance:
- [ ] `severity: "major"` constraint fires, writes violation record, journey continues
- [ ] Violation record includes `trigger_value` and `time_on` timestamp
- [ ] `calculate_leakage` counts major violations toward `leakage_ratio`

### US-3: Disable a constraint without deleting it
**As an** operator temporarily suspending a rule during a transition period,
**I want to** toggle a constraint off without deleting it so that
**I can re-enable it later without rebuilding it.**

Acceptance:
- [ ] `is_enabled: false` on a constraint entry disables it at runtime
- [ ] Disabled constraints are visible in map data (not hidden)
- [ ] Re-enabling restores enforcement immediately on next publish

---

## Migration Note

Existing maps with `standing_constraints` text blob:
- Preserve the text value in a `_legacy_text` field during migration
- Do not auto-parse or auto-convert — prompt operator to remap through AI interview
- Old maps continue to run with `constraints_ok` as pass/fail binary until operator migrates

See `product/docs/architecture/CONSTRAINT-OWNERSHIP.md` before implementation. Constraint ownership must be decided before adding fields.

---

## References

- `product/learnings/telogis-tde-architecture-analysis.md` — Section 1: Constraint Severity Model
- `product/docs/prd/PRD-runtime-engine.md` — Parent PRD
- `product/docs/architecture/CONSTRAINT-OWNERSHIP.md` — Rule ownership model
- `product/docs/epics/EPIC-P0-violation-log.md` — Sibling epic (violation record written when constraint fires)
- `emgram-skills/skills/atomic_runtime_template.md` — Readiness checklist to update post-ship
