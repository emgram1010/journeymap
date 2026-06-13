# Roadmap — emgram Intelligence Layer

> Priority order is P0 → P1 → P2 → P3.
> P0 gaps block runtime accuracy. P1 gaps block mass market usefulness.
> Do not ship dependent P1 runtime behavior before its P0 contracts are complete.
> Independent P1 planning may run in parallel.

---

## P0 — Runtime Accuracy (Build First)

These gaps cause the runtime to silently fail or produce wrong results. Nothing else matters until these are fixed.

| # | Feature | Problem Today | Epic |
|---|---|---|---|
| P0-1 | **Constraint severity model** | `standing_constraints` is a text blob — runtime can't enforce hard vs. soft | `epics/EPIC-P0-constraint-engine.md` |
| P0-2 | **Constraint violation log** | When `constraints_ok = false`, nothing is recorded — no audit trail, no leakage signal | `epics/EPIC-P0-violation-log.md` |
| P0-3 | **Stage execution status enum** | Runtime only produces pass/fail — no `on_time | late | missed | blocked` state | `epics/EPIC-P0-execution-status.md` |

**Inspiration:** Telogis `Condition.Severity` + `Alert` table + `Job.JobStatus` enum.
See `product/learnings/telogis-tde-architecture-analysis.md`.

---

## P1 — Mass Market Usefulness (Build Second)

These unlock the core user story: a solo entrepreneur can run their business with the platform and get reliable leakage numbers.

| # | Feature | Problem Today | Epic |
|---|---|---|---|
| P1-1 | **Dispatch layer** | `publish_map` jumps straight to execution — no pre-flight constraint check | `epics/EPIC-P1-dispatch-layer.md` |
| P1-2 | **Pre-execution violations report** | No way to see constraint failures before execution starts | `epics/EPIC-P1-dispatch-layer.md` |
| P1-3 | **Time tolerance on stage** | `planned_duration` is binary — no `±` allowance before violation fires | `epics/EPIC-P1-dispatch-layer.md` |
| P1-4 | **Actor qualification tags** | No skill/certification matching between actor and stage | `epics/EPIC-P1-dispatch-layer.md` |
| P1-5 | **Completion evidence model** | `stage_goal` is a text string — no structured proof the goal was met | `epics/EPIC-P1-completion-evidence.md` |

**Inspiration:** Telogis `FormInstance` + Fleet Route Builder violations summary + Job Arrival Allowance.
See `product/learnings/fleet-route-lifecycle-analysis.md`.

---

## P2 — Defensibility (Build Third)

These make emgram harder to displace once operators are using it.

| # | Feature | Problem Today | Epic |
|---|---|---|---|
| P2-1 | **ETA downstream propagation** | Stage N late → no downstream impact flagged | TBD |
| P2-2 | **Actor tag qualification matching** | No runtime check of actor skill vs. stage requirement at dispatch | TBD |
| P2-3 | **Max duration hard cap** | `planned_duration` is a soft SLA — no hard ceiling that blocks execution | TBD |
| P2-4 | **Execution FSM template per map** | All maps use the same linear flow — no per-map or per-industry state machine | TBD |
| P2-5 | **Stage cost components** | Leakage math only counts actor labor — execution costs, per-event costs, and variance costs are invisible | TBD |

**Inspiration:** Fleet `ETA recalculation` + `WorkPlan Status Flow Templates` + `VehicleCapacityLimit` + `FuelTransaction` (spirit only — translated to domain-agnostic cost components).

**Cost component note:** The logistics concept of a fuel rate input ($3.50/gallon) translates in the intelligence layer to a `per_event` or `consumption` cost component — not fuel-specific vocabulary. The model must stay domain-agnostic. See `product/learnings/INSPIRATION.md` — "The Cost Translation" section.

---

## Scale Resilience — Infrastructure Track

> **Prerequisite for P3 and for any 100k+ production deployment.**
> This track runs **in parallel** with product features — it does not gate P2 but must
> be complete before scale targets are hit. See full scope →
> `product/resilience/resilience-prd.md` and `product/resilience/EPIX/` for the 9 epics.

| Epic | Title | Category | Model |
|---|---|---|---|
| RES-0 | Source-of-Truth Consolidation | Maintenance | 🔴 Higher model |
| RES-1 | Data Integrity & Constraints | DB | 🟡 4.6 w/ guardrails |
| RES-2 | Indexing & Tenant-Scoped Access | DB | ✅ 4.6 |
| RES-3 | High-Volume Table Lifecycle | DB | 🔴 Higher model |
| RES-4 | DB-Side Filtering & Pagination | Logic | 🟡 4.6 w/ guardrails |
| RES-5 | Hot-Path De-Nesting & Batch Writes | Logic | ✅ 4.6 |
| RES-6 | Resilience Patterns: Idempotency & Errors | Logic | 🔴 Higher model |
| RES-7 | Frontend Scale: Virtualization & Pagination | Frontend | 🟡 4.6 w/ guardrails |
| RES-8 | Observability & Slow-Query Telemetry | Ops | 🟡 4.6 w/ guardrails |

**Critical path:** RES-0 → RES-2 → RES-4 → RES-7.
**Can run in parallel after RES-0:** RES-1, RES-2, RES-3, RES-8.

---

## P3 — Intelligence Depth (Future)

| # | Feature | Problem Today |
|---|---|---|
| P3-1 | Actor availability windows | No concept of shift-hours constraints on an actor |
| P3-2 | Journey lock on completion | No auto-lock when `end_point` stage completes |
| P3-3 | Mid-execution re-plan | Cannot reorder stages in an active journey without full republish |
| P3-4 | Stage sign-off (digital signature) | No cryptographic proof of stage completion |
| P3-5 | Multi-execution cohort analysis | No aggregate view across 1,000 runs of the same map |

---

## Definition of Done — Per Priority Level

### P0 Done When:
- `standing_constraints` is replaced with `stage_constraints[]` with severity enum
- Every constraint failure writes a `constraint_violation` event record
- Runtime computes `stage_status` enum from planned vs actual delta
- `calculate_leakage` uses violation log — not just duration delta

### P1 Done When:
- A pre-publish violations report runs all constraint checks and returns failures
- Actor can be assigned to a journey instance at dispatch time
- Time tolerance field exists on stage cells and runtime respects it
- Completion evidence (form/signature/signal) can be attached to a stage

### P2 Done When:
- A late stage at position N flags all downstream stages as "at risk"
- Actor tag requirements on a stage are checked at dispatch
- Maps can define an execution FSM template with configurable transition rules

---

## What Not To Build

Features that don't serve Blueprint, Watcher, or Signal are noise:

- ❌ Rich text editor / document builder
- ❌ Meeting scheduling
- ❌ Generic reporting dashboards not anchored to leakage
- ❌ Social / collaboration features (comments, emoji reactions)
- ❌ Anything that requires a user to understand what a "webhook" is

---

## References

- `product/docs/01-ARCHITECTURE.md` — Technical model behind this roadmap
- `product/docs/DEPENDENCY-MAP.md` — What must run sequentially vs. what can run in parallel
- `product/docs/releases/MVP-DEFINITION.md` — Minimum sellable intelligence layer
- `product/learnings/telogis-tde-architecture-analysis.md` — P0/P1 feature gaps
- `product/learnings/fleet-route-lifecycle-analysis.md` — Dispatch layer design
- `product/stories/` — Existing implementation epics and stories
