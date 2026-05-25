# AI Agent — Anti-Journey Default Lens Set & Metrics Scaffold

**Epic goal:** When the AI agent builds an anti-journey (or any map-level build), it must scaffold the correct default lens set including Metrics and Financial rows with proper templates. Currently `metrics` is missing from `scaffold_structure`'s actor_type enum so the agent cannot create a templated metrics lens via that tool, and the agent prompt has no prescribed default lens set for anti-journey builds — leaving lens selection entirely to LLM inference.

---

## Root Cause (confirmed via live map inspection)

Map "Last-Mile: Delivered but Not Received" (ID 109) was built with:
- ✅ Customer, Driver, Support Agent, Fraud Investigation (actor lenses — correct)
- ✅ Top Pain Point, Key Variable, Cascade Risk, Systems (structural lenses — no actor_type, correct)
- ❌ No Metrics lens
- ❌ No Financial lens

Two causes:
1. `scaffold_structure` tool instructions list `actor_type` values as: `customer, internal, engineering, ai_agent, handoff, vendor, financial` — **`metrics` is absent**. Agent cannot create a properly templated metrics row via scaffold_structure.
2. Agent system prompt Build Sequence Phase 2 says "include all known lens rows" — no explicit default set prescribed. Agent infers from user request text and misses Metrics and Financial every time.

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Where to add metrics support | `scaffold_structure.xs` tool instructions + scaffold block | Mirrors how all other actor types are handled |
| 2 | Default lens set scope | Anti-journey AND all map-level builds | Metrics and Financial are universally useful; not anti-journey-specific |
| 3 | Structural vs actor lens clarity | Add classification table to agent prompt | Agent needs to know which lens types get actor_type and which don't |
| 4 | Enforcement | Prompt instruction — not hard-coded | Keeps agent flexible for edge cases while setting clear defaults |

---

## Vocabulary

| Term | Definition |
|---|---|
| **Structural lens** | A lens with no actor_type (e.g. Description, Top Pain Point, Cascade Risk) — displays free text content |
| **Actor lens** | A lens with a non-empty actor_type — scaffolded with actor_fields template, filled via update_actor_cell_fields |
| **Default lens set** | The minimum set of lenses the agent must include in every map-level build |

---

## User Stories

### US-AJS-01 — Add `metrics` scaffold block to `scaffold_structure` tool
**File:** `tools/7_scaffold_structure.xs`

Two changes:
1. Update tool instructions line to add `metrics` to the actor_type enum description
2. Add `metrics` conditional scaffold block (after the `financial` block) with:
   - `template_key: "metrics-v1"`
   - `role_prompt`: metrics-focused prompt covering CSAT, completion rate, drop-off, error rate, stage health
   - `actor_fields` scaffold: `csat_score`, `completion_rate`, `drop_off_rate`, `avg_time_to_complete`, `error_rate`, `sla_compliance_rate`, `volume_frequency`, `stage_health`

**Acceptance criteria:**
- `scaffold_structure` with `actor_type: "metrics"` creates a lens with `template_key: "metrics-v1"` and all 8 actor_fields pre-scaffolded as null
- Existing actor_type scaffold blocks (customer, internal, financial, etc.) unchanged

---

### US-AJS-02 — Add default lens set instruction to agent system prompt
**File:** `agents/2_journey_map_assistant.xs`

Add a `## Default lens set` section before Phase 2 in the Build Sequence Order that prescribes the minimum lenses for every map-level build.

**Lens classification table to add:**

| Lens type | actor_type | Template | Notes |
|---|---|---|---|
| Description | (none) | none | Always first — all other lenses depend on it |
| Customer | customer | customer-v1 | Primary actor experiencing the journey |
| Internal actor rows | internal | internal-v1 | One row per internal role involved |
| Metrics | metrics | metrics-v1 | Always include — AI infers from qualitative content |
| Financial | financial | financial-v1 | Always include — AI infers cost/revenue impact |
| Top Pain Point | (none) | none | Structural — free text content |
| Key Variable | (none) | none | Structural — free text content |
| Cascade Risk | (none) | none | Structural — free text content |
| Systems | (none) | none | Structural — free text content |

Rule to add: "Always include a Metrics row (`actor_type: metrics`) and a Financial row (`actor_type: financial`) in every map-level build via scaffold_structure. Never omit these regardless of whether the user mentioned them."

**Acceptance criteria:**
- Agent includes Metrics and Financial lens in scaffold_structure call on every map-level build
- Agent uses `actor_type: "metrics"` and `actor_type: "financial"` (not bare label-only adds)

---

### US-AJS-03 — Add structural vs actor lens classification rule to agent prompt
**File:** `agents/2_journey_map_assistant.xs`

Add a short rule so the agent never assigns `actor_type` to structural lenses:

"Structural lenses (Top Pain Point, Key Variable, Cascade Risk, Systems, Description, Notifications, Escalation Trigger) must be created WITHOUT actor_type. Do NOT pass actor_type on these lenses — doing so will apply the wrong template and scaffold incorrect actor_fields."

**Acceptance criteria:**
- Agent creates Top Pain Point, Key Variable, Cascade Risk, Systems without actor_type
- Agent creates Metrics and Financial WITH the correct actor_type
