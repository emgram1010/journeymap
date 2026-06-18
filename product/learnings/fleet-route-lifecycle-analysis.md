# Fleet Route Planning Lifecycle → emgram Architecture Learnings
> Source: fleet-help.verizonconnect.com — Dispatch, Response, WorkPlan, Fleet sections
> Purpose: Map the full Plan→Execute→Monitor lifecycle to emgram's journey map model

---

## The Full Fleet Lifecycle (3 Phases)

```
PHASE 1: DESIGN         PHASE 2: DISPATCH        PHASE 3: EXECUTE
─────────────────        ─────────────────        ────────────────────
Scenarios (planner)  →   Route Builder        →   Job Monitor (auto)
  - jobs defined          - optimizer runs         - GPS arrival detect
  - time windows set      - violations check       - On Site / Complete
  - tags/requirements     - driver assigned        - Wrong Order / Missed
  - linked stops          - route published        ETA recalc downstream

                         WorkPlan (driver)
                           - Status Flow FSM
                           - Manual Complete/Reject
                           - Forms on transitions
```

emgram today has Phase 1 (build_journey_map) and Phase 3 (runtime webhook).
**Phase 2 — Dispatch — is the missing layer.**

---

## Layer-by-Layer Feature Mapping

### Phase 1: Design (Journey Map Build)

| Fleet Concept | Fleet Details | emgram Equivalent |
|---|---|---|
| Scenarios workspace | Multi-day route planning canvas | `journey_architecture` |
| Job definition | Name, code, time window, notes, tags, load | Stage cell content |
| Job Time Window | `requested_arrival ± allowance`, days/times allowed | `planned_duration` + **missing: `time_tolerance`** |
| Job Requirements (tags) | Driver/Vehicle must have matching tags | **missing: `required_tags` on stage** |
| Linked Stops | Jobs that must execute in sequence | `sub_journey` link |
| Load Information | Capacity metric (weight/volume per job) | **missing: resource capacity per stage** |

---

### Phase 2: Dispatch (The Missing Layer)

**This is where Fleet does constraint pre-checking BEFORE execution starts.**

| Fleet Concept | Fleet Details | emgram Gap |
|---|---|---|
| Route Builder optimizer | Auto-assigns drivers+vehicles, sequences jobs | `build_journey_map` (partial match) |
| **Violations summary after build** | Lists constraint failures post-optimization | **No pre-execution validation report** |
| Actor assignment | Driver + Vehicle explicitly bound to route | Actors are defined on lenses but not "assigned" at dispatch time |
| Shift selection | Specific shift bound to route at build time | No explicit shift binding before execution |
| **Route Card** | Printed snapshot of route for driver | `publish_map` automation snapshot (functional parallel) |
| Territory scoping | Route is scoped to a territory | `journey_architecture_id` (partial) |

**Key insight: Fleet separates "constraint check" from "execution start".** The optimizer runs, shows violations, and a human reviews before clicking "publish to driver." emgram currently does this in one step.

---

### Phase 3: Execute (Runtime Engine)

| Fleet Concept | Fleet Details | emgram Equivalent |
|---|---|---|
| Job Monitor | Auto-detects arrival via GPS boundary | Runtime webhook event processor |
| Stage transition FSM | `pending → in_transit → arrived → on_site → complete` | `duration_ok + sequence_ok + goal_met + constraints_ok` (4 checks, no explicit FSM) |
| Arrival window | `planned_arrival ± Job Arrival Allowance` | `planned_duration` — **missing: `±tolerance` field** |
| "Stayed on Site" rule | ignition_off OR time_exceeded OR 10min+ | `goal_met` check |
| Job Status enum | `On Site / Complete / Wrong Order / Missed / Early / Late` | **No computed status enum — only pass/fail** |
| **ETA propagation** | Recalculates all downstream job ETAs from current delay | **No downstream impact calculation** |
| Route locked at depot | Execution locked when driver returns to start | No journey "lock on completion" concept |
| Resequence mid-route | Re-optimize remaining jobs during active execution | **No mid-execution re-planning** |

---

### Driver Execution: Status Flow Templates

**This is the most important missing concept for emgram.**

WorkPlan uses **Status Flow Templates** — configurable finite state machines (FSM) per industry:
- `Basic Jobs with DVIR`: PreDVIR → Driving → Arrived → OnSite → PostDVIR → Complete
- `Ready Mix`: specialized for construction materials
- `Long-Haul`: for over-the-road trucking

Each FSM node can:
- **Require a form** before transition (DVIR inspection, delivery confirmation)
- **Block transition** if pre-condition not met (hard constraint)
- **Log the transition** with timestamp + location

**emgram gap:** stages advance linearly. There's no per-map or per-architecture execution FSM template. A "Basic Service Call" journey needs different transition rules than a "Compliance Audit" journey.

**Borrow:** Add `execution_template` to journey map settings:
```json
{
  "execution_template": "service_call | compliance | field_ops | long_haul",
  "transitions": [
    { "from": "pending", "to": "active", "requires_evidence": false },
    { "from": "active", "to": "complete", "requires_evidence": true, "evidence_type": "form | signature" }
  ]
}
```

---

### Job Requirements = Tag-Based Constraint Matching

Fleet's requirement system is elegant and simple:
- Job has `driver_requires: ["CraneOperator"]` and `vehicle_requires: ["BoomArm"]`
- At assignment: `driver.tags ⊇ job.driver_requires` → pass or warn
- Warning shown at dispatch time, not a silent failure at runtime

**emgram borrow:**
- Stage has `required_actor_tags: ["CDL-A", "ForkliftCert"]`
- At dispatch/assignment: check `actor.tags ⊇ stage.required_tags`
- Failure severity: `hard` = block, `soft` = warn with leakage flag

---

## The 3-Layer Architecture emgram Needs

```
Layer 1: DESIGN          Layer 2: DISPATCH         Layer 3: EXECUTE
─────────────────         ─────────────────          ─────────────────
AI + human build          Pre-execution setup        Runtime engine

build_journey_map  →      assign actors         →    webhook events
scaffold_map               bind shift/window          FSM transitions
fill_cells                 run constraint check       status enum
                           show violations            ETA propagation
publish_map ─────────────► SNAPSHOT ─────────────►   locked on complete
```

Today `publish_map` jumps directly from Layer 1 to Layer 3.
**The Dispatch layer is where constraint pre-checking, actor assignment, and execution FSM binding would live.**

---

## Priority Feature Gaps (from this research)

| Priority | Feature | Inspired By | emgram Change |
|---|---|---|---|
| 🔴 P0 | Execution status enum | `Job.JobStatus` | `pending/active/complete/late/missed/wrong_order/blocked` |
| 🔴 P0 | Pre-execution violations report | Route Builder violations summary | Run all constraint checks at `publish_map`, return violations |
| 🟠 P1 | Stage FSM execution template | WorkPlan Status Flow Templates | `execution_template` on map settings; transition rules per stage |
| 🟠 P1 | Time tolerance on stage | Job Arrival Allowance `±` | `time_tolerance_value` (minutes) alongside `planned_duration` |
| 🟠 P1 | Actor tag requirements on stage | Job Requirements (tags) | `required_actor_tags: Set<Text>` — checked at dispatch |
| 🟡 P2 | Dispatch phase (Layer 2) | Route Builder → publish → driver | Explicit pre-execution actor binding + constraint check step |
| 🟡 P2 | ETA downstream propagation | Response ETA recalculation | When stage is late, recalculate and flag downstream stages |
| 🟢 P3 | Mid-execution re-plan | Resequence mid-route | Allow stage reorder on active journeys without full republish |
| 🟢 P3 | Journey lock on completion | Route locked at depot | Auto-lock journey when `end_point` stage is complete |
