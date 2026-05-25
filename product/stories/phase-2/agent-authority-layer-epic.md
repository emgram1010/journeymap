# Agent Authority Layer Epic

**Status:** Planning (Post-AB-4)
**Goal:** Prevent data manipulation collisions and decision authority conflicts between multiple AI agents operating within the same journey architecture — across maps, across workspaces, and across concurrent sessions.

---

## Context

As users convert more actors to AI agents and build out multi-agent architectures, collisions become inevitable. In a last-mile delivery example with a Route Planner Agent, Driver Agent, Manager Agent, and Customer Comms Agent all operating within one journey architecture:

- Two agents may try to write the same record simultaneously (**data ownership collision**)
- Two agents may reach conflicting decisions about the same event (**decision authority collision**)
- An exception may bounce between agents with no clear owner (**escalation loop collision**)

This epic defines the **Agent Authority Layer** — a system that enforces clear data ownership, decision scope, and escalation chains across all AI agents in a journey architecture, at both design time (in the map) and runtime (in the Automation Bridge).

### The 3 Collision Types

| Type | Description | Example |
|---|---|---|
| **Data Ownership** | Two agents write the same record concurrently | Route Planner + Driver both update stop sequence |
| **Decision Authority** | Two agents make conflicting decisions about the same event | Route Planner reschedules; Manager confirms original time to customer |
| **Escalation Loop** | Exception bounces between agents with no single owner | Driver escalates to Manager; Manager escalates back |

---

## Existing Architecture (Do Not Break)

- `journey_lens.actor_type: ai_agent` — the 12 fields already include `escalation_logic` and `decision_output`
- `journey_link` table — `link_type: exception | anti_journey | sub_journey` — models branching authority
- `handoff` actor type + handoff lens fields — `upstream_actor`, `downstream_actor`, `validation_rules` — already models transfer of authority
- `journey_architecture` — the container that scopes all maps and agents; cross-architecture links are blocked
- Orchestrator agent: `agents/6_journey_map_orchestrator.xs` — future runtime traffic controller

---

## Design Principle: The Map IS the Authority Contract

The journey map already contains most of what the authority layer needs:

- `decision_output` field → what this agent owns/produces
- `escalation_logic` field → when it relinquishes authority
- `handoff` lens rows → explicit transfer of ownership between actors
- `journey_link` edges → delegation graph (sub_journey = agent hands off to sub-process)

The Agent Authority Layer makes these **enforceable at runtime** rather than just documentary.

---

## Priority Stack

```
🟡 MED    Epic-AAL-1   Authority Boundary Definition (design-time)
🟡 MED    Epic-AAL-2   Collision Detection Rules
🔵 LOW    Epic-AAL-3   Runtime Authority Enforcement (Automation Bridge integration)
🔵 LOW    Epic-AAL-4   Cross-Workspace Agent Registry
```

---

## Epic AAL-1 — Authority Boundary Definition (Design Time)

### US-AAL-01 — `agent_authority` table

**Story:** As a system, I need a table that stores the explicit data ownership and decision authority rules for each AI agent lens within a journey architecture — so that the Automation Bridge can enforce them at runtime.

**Proposed table: `agent_authority`**

| Field | Type | Notes |
|---|---|---|
| `id` | int | Primary key |
| `journey_architecture` | int → `journey_architecture` | Scoped to architecture |
| `journey_lens` | int → `journey_lens` | The AI agent lens this rule applies to |
| `owned_fields` | json | List of data field names this agent is the sole writer of |
| `decision_scope` | text | Plain-language description of what this agent decides |
| `escalation_target_lens` | int → `journey_lens` | Which agent/human receives escalations |
| `max_autonomous_actions` | int | How many actions before human check-in required |
| `authority_level` | enum | `autonomous` / `advisory` / `escalate_always` |
| `created_at` | timestamp | Auto |

**Acceptance Criteria:**
- [ ] Table created with all fields above
- [ ] `(journey_architecture, journey_lens)` unique — one authority record per agent per architecture
- [ ] `escalation_target_lens` allows null (top-level agents escalate to human, not another agent)
- [ ] `authority_level` enum enforced

---

### US-AAL-02 — Auto-derive authority rules from existing 12 fields

**Story:** As a user, when I complete the 12 AI agent fields on a lens, I want the system to auto-derive a draft `agent_authority` record from `escalation_logic`, `decision_output`, and `confidence_threshold` — so I don't have to fill a second form.

**Derivation logic:**
- `owned_fields` ← inferred from `decision_output` content
- `decision_scope` ← copied from `decision_output`
- `escalation_target_lens` ← inferred from `escalation_logic` (match actor name to lens)
- `authority_level` ← derived from `confidence_threshold`: high threshold → `autonomous`; low → `advisory`

**Acceptance Criteria:**
- [ ] Draft authority record created/updated when `decision_output` or `escalation_logic` is saved
- [ ] Derivation is a suggestion — user can override any field
- [ ] If derivation cannot infer a field, it remains null (not guessed)

---

### US-AAL-03 — Authority Boundary View in Journey Map UI

**Story:** As a user, I want to see a read-only "Authority Map" view within a journey architecture that shows all AI agents, what they own, and how escalation flows between them — so I can spot conflicts before runtime.

**Display:** Directed graph overlay on the Architecture Dashboard
- Nodes: each `ai_agent` lens in the architecture
- Edges: escalation paths (from `escalation_target_lens`)
- Node color: `autonomous` = blue / `advisory` = yellow / `escalate_always` = orange
- Conflict indicators: red edge when two agents both claim `owned_fields` overlap

**Acceptance Criteria:**
- [ ] Authority graph renders for any architecture with 2+ `ai_agent` lenses
- [ ] Conflicting `owned_fields` between agents highlighted visually
- [ ] Clicking a node opens the `agent_authority` detail panel
- [ ] Graph is read-only — editing happens via lens detail panel

---

## Epic AAL-2 — Collision Detection Rules

### US-AAL-04 — Design-time conflict detector

**Story:** As a user, I want the system to warn me when two AI agents in the same architecture have overlapping `owned_fields` — so I can resolve authority conflicts before the agents are deployed.

**Trigger:** On save of any `agent_authority` record
**Logic:** Query all authority records for the same `journey_architecture`; compare `owned_fields` arrays for overlap

**Acceptance Criteria:**
- [ ] Warning surfaced in UI when `owned_fields` overlap detected between any two agents
- [ ] Warning shows which agents conflict and which fields overlap
- [ ] Does not block save — it is a warning, not an error (human decides)
- [ ] Warning dismissed when overlap is resolved

---

### US-AAL-05 — Escalation loop detector

**Story:** As a user, I want the system to detect circular escalation chains (Agent A escalates to Agent B, Agent B escalates back to Agent A) at design time and flag them.

**Logic:** Traverse `escalation_target_lens` chain for each agent; detect cycles using DFS
**Condition:** Any cycle of length ≥ 2 is flagged

**Acceptance Criteria:**
- [ ] Circular escalation chains flagged with a clear message identifying the agents in the loop
- [ ] Detector runs on save of any `agent_authority` record
- [ ] At least one agent in the architecture must have `escalation_target_lens = null` (human termination node)
- [ ] Warning if no human termination node exists

---

## Epic AAL-3 — Runtime Authority Enforcement (Automation Bridge Integration)

> **Dependency:** Requires Automation Bridge (Epic AB-4) to be in progress. This epic is a Phase 3 addition to AB-4, not a standalone build.

### US-AAL-06 — Authority check before agent write

**Story:** As the Automation Bridge runtime, before any AI agent writes a data field, I want to check the `agent_authority` table to confirm this agent owns that field — and reject or queue the write if it does not.

**Logic:**
1. Agent runtime action includes `{agent_lens_id, field_name, value}`
2. Look up `agent_authority` for `journey_lens == agent_lens_id`
3. If `field_name` not in `owned_fields` → reject with `403: authority_violation`
4. If another agent is currently writing the same field → queue write, retry after lock clears

**Acceptance Criteria:**
- [ ] Write blocked when agent does not own the field
- [ ] Write queued (not dropped) when field is locked by another agent
- [ ] Lock timeout after 30 seconds — release and retry
- [ ] Authority violations logged to `agent_turn_log` with `status: authority_violation`

---

### US-AAL-07 — Escalation enforcement at runtime

**Story:** As the Automation Bridge runtime, when an AI agent triggers its `escalation_logic` condition, I want the system to automatically route the exception to the correct `escalation_target_lens` and halt the originating agent — so escalation loops are impossible.

**Logic:**
1. Agent signals escalation (confidence below threshold OR explicit escalation flag)
2. Look up `escalation_target_lens` from `agent_authority`
3. If target is another agent → invoke that agent's sub-journey map via `invoke_map`
4. If target is null (human) → create human review task and pause agent
5. Originating agent is paused until escalation is resolved — cannot re-enter autonomous mode

**Acceptance Criteria:**
- [ ] Agent paused immediately on escalation signal
- [ ] Escalation routed to correct target (agent or human)
- [ ] Escalation loop impossible — agent cannot escalate to itself or to an agent that escalated to it
- [ ] Human tasks created for null-target escalations with full context

---

## Epic AAL-4 — Cross-Workspace Agent Registry

> **Status:** Future / Low Priority — relevant only when a single user operates multiple journey architectures with shared AI agents.

### US-AAL-08 — Agent registry across architectures

**Story:** As a user with multiple journey architectures (e.g. Last Mile Delivery + Returns Processing + Customer Onboarding), I want a registry that shows all AI agents across all architectures — so I can see scope overlaps and reuse agent specs.

**Note:** Cross-architecture authority enforcement is a non-goal for v1. This story is read-only registry only — no cross-architecture write authority in phase 2.

---

## Collision Prevention Summary

| Problem | Solution | Where |
|---|---|---|
| Data ownership collision | `agent_authority.owned_fields` + write-lock check | Runtime (AAL-3) |
| Decision authority collision | Design-time conflict detector on `owned_fields` | Design (AAL-2) |
| Escalation loop | Loop detector + runtime escalation halt | Both (AAL-2 + AAL-3) |
| No human in the loop | Require null-target node in escalation chain | Design (AAL-2) |
| Cross-workspace drift | Agent registry (read-only v1) | Design (AAL-4) |

---

## Relationship to Other Epics

| Epic | Relationship |
|---|---|
| Actor-to-AI-Agent Conversion (Phase 2) | Conversion wizard populates the fields that AAL derives authority records from |
| Link Map (Epic LM-1) | Sub-journey links define delegation scope — feeds AAL escalation graph |
| Automation Bridge (Epic AB-4) | AAL-3 runtime enforcement is a Phase 3 addition to AB-4 |
| Orchestrator Agent (`agents/6_journey_map_orchestrator.xs`) | The Orchestrator is the runtime caller of authority checks |

---

## Non-Goals

- Real-time conflict resolution UI (v1 is async — detect and warn, not auto-resolve)
- AI agents from different vendors (v1 assumes all agents run within the same Xano/Emgram architecture)
- Write-authority delegation (an agent cannot temporarily grant its authority to another agent in v1)
- Audit trail UI (authority violations are logged but UI is out of scope for v1)
