# Skill: Atomic Runtime Template — L3 Map Requirements for Journey Runtime Layer

## Purpose
Every L3 Atomic map that will receive live webhook events from the Journey Runtime Layer
must be built to this spec. Without these fields, the 4 runtime checks cannot execute,
`calculate_leakage` returns $0, and the validation engine has nothing to compare against.

Use this skill alongside `create_map.md` whenever `map_level = "atomic"`.

---

## 🚨 HARD RULES

1. **Never publish an L3 Atomic map without passing the Runtime Readiness Checklist** (below)
2. **Every stage must have `stage_goal` AND `planned_duration`** — these are the completion signal and duration baseline the runtime checks against
3. **Every primary actor lens must have `cost_rate_value` + `standing_constraints`** — without these, leakage math and constraints_ok both fail silently
4. **`measurement_frequency` is non-negotiable** — without it, annual and 3yr leakage = $0

---

## Mandatory Lens Structure for Runtime Maps

```
scaffold_map { lens_operations: [
  { action: "add", label: "<Primary Actor>", actor_type: "internal" | "customer" | ... },
  { action: "add", label: "Handoff",          actor_type: "handoff"   },
  { action: "add", label: "Exception Handler",actor_type: "handoff"   },
  { action: "add", label: "Metrics",          actor_type: "metrics"   }
]}
```

Minimum 4 lenses. The primary actor lens is where `planned_duration`, `time_duration_value`,
and `cost_rate_value` live. Exception Handler wires to exception maps via `link_map`.

---

## Required Fields — Per Stage

Run this for EVERY stage in the map:

| Field | Tool | Why Runtime Needs It |
|---|---|---|
| `stage_goal` | `scaffold_map` rename OR `update_stage_contract` | `goal_met` check — completion signal match |
| `primary_actor_lens` | `scaffold_map` rename OR `update_stage_contract` | Identifies which actor owns this stage |
| `planned_duration` | `fill_cells` on primary actor cell | `duration_ok` check — baseline for leakage delta |
| `time_duration_value` + `time_duration_unit` | `fill_cells` / `update_cell` | Leakage math input |

---

## Required Fields — Per Actor Lens Identity

Run `update_actor_identity` for EVERY actor lens:

| Field | Why Runtime Needs It |
|---|---|
| `persona_description` | Context for exception routing and audit |
| `primary_goal` | Validates `goal_met` interpretation |
| `standing_constraints` | `constraints_ok` check — rules the actor must follow at every stage |
| `cost_rate_value` + `cost_rate_unit` | Leakage math: `leakage_delta = time_over × cost_rate` |

`standing_constraints` must be explicit even if minimal — write "none" if truly unconstrained.
Never leave it null on a runtime map.

---

## Required Fields — Journey Settings

Call `update_journey_settings` with ALL of these before publishing:

```
update_journey_settings {
  journey_map_id,
  intent:                    "sop" | "automation" | "hybrid",
  primary_actor:             "<actor name>",
  journey_scope:             "<what's in scope>",
  start_point:               "<triggering event>",
  end_point:                 "<final outcome>",
  duration:                  "<typical full-journey timespan>",
  success_metrics:           "<how success is measured>",
  key_stakeholders:          "<teams involved>",
  measurement_frequency:     <int — annual run count>,   ← REQUIRED for leakage math
  measurement_period_label:  "<per job | per shift | per call>"  ← REQUIRED
}
```

---

## The 4 Runtime Checks — Field Mapping

```
duration_ok     →  actual_duration ≤ cell.planned_duration
                   REQUIRES: planned_duration on primary actor cell

sequence_ok     →  inbound stage order == stage.display_order
                   REQUIRES: stages ordered correctly in scaffold

goal_met        →  inbound completion_signal == stage.stage_goal
                   REQUIRES: stage_goal set on every stage

constraints_ok  →  inbound payload satisfies lens.standing_constraints
                   REQUIRES: standing_constraints set on actor identity
```

Each missing field silently disables one check. All 4 must be satisfiable.

---

## Inbound Event Contract (what external systems must send)

Every POST to a stage hook must include exactly these fields:

```json
{
  "external_ref_id":    "job-9981",         ← threads all stage events for one instance
  "stage_key":          "s2",               ← routes to the correct stage contract
  "actual_duration":    18.5,               ← compared against planned_duration
  "completion_signal":  "arrived_at_address" ← compared against stage_goal
}
```

Map builders must ensure `stage_goal` values match the `completion_signal` strings
the external system will send — agree on these values before publishing.

---

## Pre-Publish Runtime Readiness Checklist

Run `get_map` and verify every item before calling `publish_map`:

**Stages (check every stage):**
- [ ] `stage_goal` — non-null and matches an expected `completion_signal`
- [ ] `primary_actor_lens` — non-null
- [ ] Primary actor cell has `planned_duration` — non-null, non-zero

**Actor Identities (check every actor lens):**
- [ ] `standing_constraints` — non-null (even if "none")
- [ ] `cost_rate_value` + `cost_rate_unit` — non-null on primary actor lens

**Journey Settings:**
- [ ] `measurement_frequency` — non-null, non-zero integer
- [ ] `measurement_period_label` — non-null string
- [ ] `start_point` + `end_point` — non-null

**Metrics (at least one):**
- [ ] At least one cell has `actor_fields.metrics[]` with an entry where `flag == "leakage"`

If ANY item is unchecked → fill the gap before publishing. A map published with missing
runtime fields will silently pass validation checks it should fail.
