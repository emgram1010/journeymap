# Architecture — emgram Intelligence Layer

> The map is the intelligence. The runtime is the proof. The leakage is the cost of not following your own rules.

---

## The 3-Layer Model

```
LAYER 1: DESIGN          LAYER 2: DISPATCH (gap)    LAYER 3: EXECUTE
─────────────────         ──────────────────────      ─────────────────
AI + human build          Pre-execution setup         Runtime engine

build_journey_map  →      assign actors          →    webhook events
scaffold_map               constraint pre-check        FSM transitions
fill_cells                 violations report           status enum
publish_map ──────────►   SNAPSHOT ─────────────►    leakage calc
```

**Today:** Layers 1 and 3 exist. Layer 2 (Dispatch) is the P1 gap.

---

## The Map Structure

A journey map is a grid: **stages (columns) × lenses (rows)**.

```
            Stage 1    Stage 2    Stage 3    Stage 4
           ─────────  ─────────  ─────────  ─────────
Actor      │  cell  │  cell   │  cell   │  cell   │
Handoff    │  cell  │  cell   │  cell   │  cell   │
Metrics    │  cell  │  cell   │  cell   │  cell   │
```

- **Stage** = one discrete step in the process. Has a `stage_goal` (exit condition) and a `primary_actor_lens`.
- **Lens** = one actor's row. Has `persona_description`, `primary_goal`, `standing_constraints`, `cost_rate`.
- **Cell** = the intersection. Holds `content`, `planned_duration`, `time_duration_value`, `actor_fields`.

The grid is **deliberately flat** — human-readable, AI-buildable, domain-agnostic.

---

## Map Levels (L1 → L2 → L3)

| Level | Name | Purpose | Leakage? |
|---|---|---|---|
| L1 | Architecture Map | Executive overview, multiple actors | ❌ |
| L2 | Actor Journey Map | One actor's end-to-end process | ⚠️ Partial |
| L3 | Atomic Stage Map | One discrete task — metric + leakage capture | ✅ Required |

Levels link via `sub_journey`. Exceptions branch via `exception` link.
**Only L3 maps are valid for leakage analysis and runtime conformance.**

---

## The 4 Runtime Checks

When a webhook event arrives, the runtime runs 4 checks against the published map snapshot:

```
sequence_ok     →  event.stage_key order == stage.display_order
duration_ok     →  event.actual_duration ≤ cell.planned_duration
goal_met        →  event.completion_signal == stage.stage_goal
constraints_ok  →  event payload satisfies lens.standing_constraints
```

Each missing field silently disables one check. All 4 must be satisfiable for a map to be runtime-ready.

**Inbound event contract (what external systems must POST):**
```json
{
  "external_ref_id":   "job-9981",
  "stage_key":         "s2",
  "actual_duration":   18.5,
  "completion_signal": "arrived_at_address"
}
```

---

## Leakage Math

### Current Model (labor only)
```
stage_cost_per_event  = time_duration_value × cost_rate_value
annual_leakage        = stage_cost_per_event × measurement_frequency × leakage_ratio
cost_of_inaction_3yr  = annual_leakage × 3
```

- `leakage_ratio` = proportion of events where the leakage metric fires (e.g. 0.43 = 43% of jobs)
- `measurement_frequency` = how many times per year the journey runs (set on journey settings)
- **The 3-year number is always the close.** Annual is forgettable; 3-year is visceral.

### Target Model — Full Cost Components (P2)

A stage has costs beyond the actor's time. The full model introduces `stage_cost_components[]`:

```
stage_cost_components: [
  { type: "labor",       rate: 28.00, unit: "per_hour"  },   ← actor time (exists today)
  { type: "per_event",   rate: 3.50,  unit: "per_event" },   ← flat cost per run
  { type: "consumption", rate: 4.20,  unit: "per_unit", quantity_key: "units_used" },
  { type: "variance",    rate: 15.00, unit: "per_event", trigger: "duration_exceeded" }
]

total_stage_cost = sum of all component costs for one execution
leakage_delta    = (total_actual - total_planned) × leakage_ratio × measurement_frequency
```

**Language rule:** Never use domain-specific nouns (fuel, mileage, vehicle) in the data model.
Use `per_event`, `consumption`, `variance` — terms that apply to any business domain.
See `product/docs/02-VOCABULARY.md` for the full cost component vocabulary.

---

## Publish = The Snapshot

`publish_map` compiles the current map state into an **immutable automation snapshot**. This is the "route card" equivalent from logistics — the contract that the runtime engine checks against.

- Runtime always checks against the snapshot, not the live draft
- Map edits after publish do not affect running executions
- Re-publishing creates a new snapshot version; old executions continue against their snapshot

---

## Map Links (Branching Logic)

Branching is expressed as **map topology** — not in-cell logic:

| Link Type | Meaning |
|---|---|
| `sub_journey` | This cell delegates to a sub-process map (L1→L2→L3 drill-down) |
| `exception` | Something went wrong here; this cell routes to a recovery map |
| `anti_journey` | Actor did NOT follow expected path; routes to alternate map |

---

## Current State vs. Target State

### ✅ Exists Today
- L1/L2/L3 map building (AI + human)
- `publish_map` → automation snapshot
- 4 runtime checks via webhook events
- Leakage math (`calculate_leakage`)
- Scenario cloning + comparison
- Map linking (exception, anti_journey, sub_journey)

### 🔴 P0 Gaps (blocking runtime accuracy)
- `standing_constraints` is a text blob — no severity (hard/soft), no violation log
- No computed `stage_status` enum (`on_time | late | missed | blocked`)

### 🟠 P1 Gaps (unlock mass market usefulness)
- No Dispatch layer (pre-flight constraint check before execution starts)
- No structured violation record when a constraint fires
- No time tolerance (`±` allowance on `planned_duration`)
- No actor tag requirements on stage (`required_actor_tags`)

### 🟡 P2 Gaps
- No ETA downstream propagation (when stage N is late, flag stages N+1…)
- No execution FSM template per map type
- **No stage cost components** — leakage math only counts actor labor; execution costs, per-event costs, and variance costs are not captured

See `product/docs/ROADMAP.md` for full prioritized list.

---

## Key Files

| File | Purpose |
|---|---|
| `emgram-skills/instructions.md` | Agent decision brain — session start always reads this |
| `emgram-skills/skills/intelligence_layer.md` | Prescription interview + leakage-ready cell rules |
| `emgram-skills/skills/atomic_runtime_template.md` | L3 map runtime readiness checklist |
| `product/docs/architecture/CONSTRAINT-OWNERSHIP.md` | Where constraints live: lens vs stage vs cell vs execution |
| `product/docs/architecture/RUNTIME-EVENT-CONTRACT.md` | Stable inbound runtime event payload |
| `product/docs/architecture/SNAPSHOT-VERSIONING.md` | How publish versions bind to executions |
| `product/learnings/telogis-tde-architecture-analysis.md` | Constraint schema gaps from Telogis research |
| `product/learnings/fleet-route-lifecycle-analysis.md` | Dispatch layer lifecycle analysis |
