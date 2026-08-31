# emgram — Product Overview PRD

> A primer for an AI collaborator. Read this first. Everything else flows from it.

---

## 1. What emgram is

emgram is a **process intelligence platform for solo operators and small teams**.

It lets a non-technical operator describe their business process in a 10–20 minute conversation with an AI agent, and then it:
1. Builds a structured **blueprint** of how the work *should* happen.
2. **Watches** real-world events against that blueprint.
3. Surfaces **leakage** — the dollar cost of every gap between plan and reality, projected over 3 years.

Think: *Celonis for the person who just lost their job and started a cleaning business.*

---

## 2. Why it exists

Enterprise process tools (Celonis $13B, SAP Signavio, IBM BPM) cost $100K–$300K+ per year and need IT teams to configure. They reverse-engineer process from ERP logs that small operators don't have.

Nobody built process intelligence for the operator who *is* the IT department, the ops team, and the buyer.

**One-line problem statement:**
> "I know my process takes too long and costs too much. I don't know exactly where or how much."

emgram makes that gap visible — in dollars — before it becomes a cash flow crisis.

---

## 3. Users

| Role | Description |
|---|---|
| **Operator (primary)** | Solo entrepreneur, small team lead, displaced worker running their own service business. Not technical. Won't read a manual. Buys and uses the product. |
| **Agent team (secondary)** | AI agents that build maps, watch execution, and surface leakage on the operator's behalf. |
| **Reviewer** | Teammate or advisor reviewing which parts of a map are confirmed vs. AI-drafted vs. open. |

**Job-to-be-done:** *Help me capture how my business should run, watch how it actually runs, and tell me — in dollars — where it's leaking money.*

---

## 4. The 3 core mechanisms

### A. Blueprint — the Journey Map
A grid of **stages × lenses** representing one business process.
- **Stage** = column = one discrete step (has a `stage_goal` and `primary_actor_lens`).
- **Lens** = row = one actor's perspective across all stages.
- **Cell** = intersection = content + duration + actor fields for that step × actor.
- Maps are built through **AI conversation**, not forms.

Map levels:
- **L1 Architecture** — executive overview of a domain.
- **L2 Actor Journey** — one actor's end-to-end process.
- **L3 Atomic** — one actor, one task. Required for leakage math and runtime.

### B. Watcher — the Runtime Engine
External systems POST events via webhook. For each event, the engine runs 4 conformance checks against the published `automation_snapshot`:

| Check | Pass condition |
|---|---|
| `sequence_ok` | Event arrived at the correct stage in the correct order |
| `duration_ok` | `actual_duration ≤ planned_duration` |
| `goal_met` | `completion_signal == stage_goal` |
| `constraints_ok` | Payload satisfies the actor's standing constraints |

Every deviation is logged. Nothing is silently skipped.

### C. Signal — Leakage Math
```
leakage_per_event = time_over × cost_rate
annual_leakage    = leakage_per_event × measurement_frequency × leakage_ratio
cost_of_inaction  = annual_leakage × 3
```
The 3-year cost of inaction is the close. It converts a process observation into a business case.

---

## 5. Key vocabulary (use exactly these terms)

| Term | Means |
|---|---|
| **Blueprint** | Journey map — the operational contract |
| **Watcher** | Runtime conformance engine |
| **Signal / Leakage** | Dollar cost of deviations |
| **Journey Architecture** | Workspace grouping related maps (L1→L2→L3) |
| **Automation Snapshot** | Immutable compiled version of a published map |
| **external_ref_id** | ID threading all events for one journey instance (one job, one case) |
| **completion_signal** | String an external system sends to prove a stage is done |
| **measurement_frequency** | How many times/year this journey runs — the compounding multiplier |
| **stage_goal** | Exit condition / definition of done for a stage |
| **cost_rate_value / unit** | Actor's labor cost: `per_minute | per_hour | per_day | per_week | per_event` |

Borrowed Celonis terms (use freely): *conformance checking, process deviation, revenue leakage, digital twin, as-is vs. to-be.*

---

## 6. How emgram differs

| | Legacy BPM | Process Mining (Celonis) | **emgram** |
|---|---|---|---|
| Who can use it | IT developers | Enterprise data teams | Any operator |
| Builds blueprint | Code (BPMN/XML) | Mined from ERP logs | AI conversation |
| Works with no existing systems | ❌ | ❌ | ✅ |
| Forward-looking | ❌ | ❌ | ✅ |
| Leakage in dollars | ❌ | ❌ | ✅ |
| Entry price | $100K+ | $300K+ | Accessible |

**Category difference:** Celonis reverse-engineers process from logs. emgram defines the process first, then watches whether reality follows.

---

## 7. North Star

> **Time from "I just started a business" to "I know exactly where I'm losing money."**
> Target: **under 20 minutes**, no IT, no prior documentation.

---

## 8. What emgram is NOT

- Not a BPMN modeler. No swimlanes, no XML.
- Not a CRM, ERP, or ticketing system.
- Not a dashboard tool — leakage is the output, not a chart library.
- Not enterprise-first. Solo operator first; enterprise is downstream.
- Not retrospective-only — the blueprint is forward-looking and prescriptive.

---

## 9. Design test for every decision

> *"Does this help someone who just lost their job run their operation better?"*

If a feature, term, or interaction fails that test, it doesn't ship.
