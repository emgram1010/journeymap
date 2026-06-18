# Vocabulary — emgram Intelligence Layer

> Use these terms consistently across all docs, code, and agent instructions.
> When in doubt, prefer the emgram term. Use the Celonis term only when
> communicating with external audiences already familiar with process intelligence.

---

## Core Mechanisms

| Term | Definition | Celonis Equivalent |
|---|---|---|
| **Blueprint** | The journey map — the machine-readable contract defining what correct execution looks like | Process Model |
| **Watcher** | The runtime engine — compares real-world events against the blueprint | Conformance Checker |
| **Signal** | Leakage — the financial cost of every deviation from the blueprint | Revenue Leakage |

---

## Map Structure

| Term | Definition |
|---|---|
| **Journey Map** | A grid of stages × lenses representing one business process |
| **Stage** | A column in the grid. One discrete step in the process. Has a `stage_goal` and `primary_actor_lens`. |
| **Lens** | A row in the grid. One actor's perspective across all stages. |
| **Cell** | The intersection of one stage and one lens. Holds content, duration, and actor fields. |
| **Journey Architecture** | A workspace grouping related maps (L1 → L2 → L3 hierarchy) |

---

## Map Levels

| Term | Definition |
|---|---|
| **L1 — Architecture Map** | Executive overview of a business domain. Multiple actors. No leakage data. |
| **L2 — Actor Journey Map** | One actor's end-to-end process. Partial leakage capability. |
| **L3 — Atomic Stage Map** | One actor performing one discrete task. Required for leakage analysis and runtime conformance. |

---

## Runtime Terms

| Term | Definition |
|---|---|
| **Conformance Checking** | Comparing a real-world execution event against the published map snapshot. Celonis term — borrow it. |
| **Process Deviation** | Any event that fails one or more of the 4 runtime checks. Celonis term — equivalent to `sequence_ok = false`. |
| **Automation Snapshot** | The immutable compiled version of a published map. The runtime always checks against this. |
| **external_ref_id** | The unique ID threading all stage events for one instance of a journey (e.g., one job, one case, one call). |
| **completion_signal** | The string sent by an external system to prove a stage is done. Must match `stage_goal` for `goal_met = true`. |

---

## The 4 Runtime Checks

| Check | Definition |
|---|---|
| `sequence_ok` | Event arrived at the correct stage in the correct order |
| `duration_ok` | `actual_duration ≤ planned_duration` |
| `goal_met` | `completion_signal == stage_goal` |
| `constraints_ok` | Event payload satisfies the actor's `standing_constraints` |

---

## Stage Fields

| Term | Definition |
|---|---|
| `stage_goal` | Exit condition / definition of done. The string the runtime checks `completion_signal` against. |
| `primary_actor_lens` | The lens key of the actor who owns this stage's output. |
| `planned_duration` | Target/SOP time for this stage (soft SLA). Exceeded = leakage logged. |
| `actual_duration` | Real observed time. Gap vs `planned_duration` = leakage delta. |
| `time_duration_value` | Planned time the actor spends at this stage (leakage math input). |

---

## Actor (Lens) Fields

| Term | Definition |
|---|---|
| `persona_description` | Who this actor is — role, background, context. |
| `primary_goal` | The overarching outcome this actor is trying to achieve in this journey. |
| `standing_constraints` | Rules this actor must follow at every stage. Currently a text blob. P0: replace with structured `stage_constraints[]`. |
| `cost_rate_value` | Actor's labor cost rate (e.g., 30.00). |
| `cost_rate_unit` | Unit for cost rate: `per_minute | per_hour | per_day | per_week | per_event`. |

---

## Cost Components (P2 — Being Planned)

The current cost model is actor-time only. The full model introduces **stage cost components** —
all the costs attached to running a stage, not just the actor's time.

> **Language rule:** Never use logistics nouns (fuel, mileage, vehicle). Use domain-agnostic terms below.
> The intelligence layer serves nurses, consultants, and contractors — not just truck drivers.

| Term | Definition | Example |
|---|---|---|
| **Execution cost** | Resource cost incurred per run of this stage — beyond actor labor | $4.20 in cleaning supplies per job |
| **Per-event cost** | Flat cost that fires every time this stage runs, regardless of duration | $35 software license fee per proposal |
| **Consumption rate** | Cost that scales with output or usage: `rate × quantity` | $0.12/sq ft in product used |
| **Variance cost** | Extra cost incurred only when the stage exceeds planned bounds | Rush fee, overtime premium, rework materials |
| **Stage cost component** | One entry in the full cost picture for a stage. Type: `labor | per_event | consumption | variance` | See schema below |
| `stage_cost_components[]` | Array of all cost inputs for a stage — replaces single `cost_rate_value` in future model | `[{ type: "labor" }, { type: "per_event", rate: 3.50 }]` |

**Full cost formula (target state):**
```
total_stage_cost = labor_cost + execution_cost + per_event_cost + variance_cost
leakage_delta    = (total_stage_cost_actual - total_stage_cost_planned) × leakage_ratio × frequency
```

---

## Leakage Terms

| Term | Definition |
|---|---|
| **Leakage** | Money lost inside process deviations. `time_over × cost_rate × measurement_frequency`. |
| **Leakage ratio** | Proportion of events where the leakage metric fires. E.g., 43 bad jobs / 1,000 total = 0.043. |
| **Cost of inaction (3yr)** | `annual_leakage × 3`. Always surface this — it's the close. |
| `measurement_frequency` | How many times per year this journey runs. The compounding multiplier. |
| `measurement_period_label` | Human label for the cadence: "per job", "per shift", "per call". |

---

## Constraint Terms (P0 Gap — Being Built)

| Term | Definition |
|---|---|
| **Hard constraint** | `severity: "critical"` — blocks execution if violated. Journey cannot advance. |
| **Soft constraint** | `severity: "major"` — logs violation + adds to leakage delta. Journey continues. |
| **Log constraint** | `severity: "normal"` — records event, no execution impact. |
| **Violation log** | Structured record written when a constraint fires: `stage_key`, `rule`, `severity`, `trigger_value`, timestamps. |
| **Stage status** | Computed enum from runtime: `pending | active | on_time | late | missed | blocked`. P0 gap. |

---

## Map Links

| Term | Definition |
|---|---|
| `sub_journey` | Target map is a delegated sub-process invoked at this cell (L1→L2→L3 drill-down). |
| `exception` | Something went wrong here; target map handles recovery. |
| `anti_journey` | Actor did NOT follow expected path; target map handles the alternate. |

---

## Dispatch Layer (P1 Gap — Being Planned)

| Term | Definition |
|---|---|
| **Dispatch** | The missing layer between publish and execute. Pre-flight validation: constraint pre-check, actor assignment, violations report. |
| **Violations report** | List of constraint failures produced at dispatch time — before execution starts. Borrowed from Telogis Route Builder. |
| **Route card equivalent** | The `automation_snapshot` — the compiled, immutable map handed to the runtime engine at dispatch. |

---

## Borrowed Terms (from Celonis — use freely)

These are enterprise-accepted terms from the $13B Process Intelligence category:
- **Conformance checking** — our 4 runtime checks
- **Process deviation** — any failed check
- **Revenue leakage** — our leakage math output
- **Digital twin** — the journey map as operational model of the business
- **As-is vs. to-be** — actual execution vs. the blueprint
