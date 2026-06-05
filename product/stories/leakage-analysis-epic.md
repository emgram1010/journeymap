# Leakage Analysis — Epic PRD

**Status:** Planning
**Goal:** Extend the Journey Map data model with the structured fields required to identify,
quantify, and compound operational waste (leakage) — enabling AI-driven prospect discovery
and scenario-based cost-of-inaction analysis at the atomic stage level.

---

## Why This Exists

Journey maps today are excellent at documenting process. They are not yet capable of
**calculating cost**. To sell an intelligent layer to a prospect, you need to be able to answer:

> *"How much is this process costing you per month — and what does that become over 3 years
> if nothing changes?"*

That answer requires structured numeric fields — time, rate, frequency — none of which
currently have a formal home in the data model. They are stored ad-hoc in `actor_fields`
open JSON, meaning two AI sessions can use different key names for the same concept,
and no server-side math is possible.

This epic formalizes the leakage data model, inspired by 15 years of enterprise logistics
intelligence (Telogis/Verizon Connect) and adapted for any industry.

**Two leakage numbers matter. Both are required to close:**
```
Labor leakage formula:
  stage_cost_per_event = time_duration_value × cost_rate_value
  annual_leakage       = stage_cost_per_event × measurement_frequency × leakage_ratio
  3yr_cost_of_inaction = annual_leakage × 3

Revenue at risk formula (the close number for SMBs):
  revenue_at_risk      = measurement_frequency × miss_rate × average_deal_value
  3yr_revenue_gap      = revenue_at_risk × 3
```

---

## 🚨 Blueprint Immutability Rule

> **The journey map and its cells are the blueprint. They describe what SHOULD happen.
> They must never be mutated by execution results.**

Actuals from execution are stored in the execution layer and displayed as an overlay.
The blueprint is the anchor — not a record of what occurred. This is the same design
principle Telogis used: the `route` object was never overwritten by actual GPS data.
The `route_response` was a separate overlay. The plan stayed clean.

**`stage_goal` is the planned benchmark.** When `actual_duration` exceeds the threshold
implied by `stage_goal`, that gap is the leakage signal. The `stage_goal` is not just
documentation — it is the exit condition every actual is measured against.

---

## The Three-Ring Architecture

Every field in this epic belongs to exactly one ring. Rings build on each other in order.

```
Ring 1 — Blueprint (already exists ✅)
  stage_goal          → the planned exit condition; the benchmark for actuals
  primary_actor_lens  → who is planned to own this stage
  persona_description → who this actor is — role, background, context
  primary_goal        → what the actor is supposed to achieve
  standing_constraints→ known limits that constrain the actor's capacity
  cell content        → the planned activity description

Ring 2 — Measurement (this epic 🔴)
  measurement_frequency    → how often the blueprint runs per year
  measurement_period_label → human label for the cadence ("per inquiry", "per job")
  cost_rate_value + unit   → what this actor's time costs per unit
  time_duration_value + unit → planned time the actor spends at this stage
  average_deal_value       → what a successful outcome is worth in revenue
  conversion_rate          → % of engaged prospects that convert
  miss_rate                → % of events that go unanswered or mishandled

Ring 3 — Actuals (phased 🟢)
  planned_duration    → discovery input: what the prospect says should happen
  actual_duration     → discovery input: what the prospect says actually happens
  execution_cell_record → Phase 2: automated per-run recording per cell
```

Ring 1 is immutable. Ring 2 is the numeric engine. Ring 3 is the truth layer.
The gap between Ring 1/2 (plan) and Ring 3 (actual) IS the leakage.

---

## Priority Stack

```
🔴 CRITICAL  Epic-LA-1  Leakage Measurement Fields (journey settings)
🔴 CRITICAL  Epic-LA-2  Actor Cost Rate Fields (actor identity)
🔴 CRITICAL  Epic-LA-3  Cell Time Duration Fields (cell / actor_fields)
🟡 HIGH      Epic-LA-4  Map Level Taxonomy (L1 / L2 / L3 enforcement)
🟡 HIGH      Epic-LA-5  Leakage Math API (server-side compounding)
🟡 HIGH      Epic-LA-7  Revenue at Risk Fields (the SMB close number)
🟢 MEDIUM    Epic-LA-6a Plan vs Actual — Discovery Inputs (Phase 1)
🟢 LOW       Epic-LA-6b Plan vs Actual — Execution Overlay (Phase 2)
```

---

## Epic LA-1 — Leakage Measurement Fields
**Without measurement frequency, the annual and 3-year numbers cannot be calculated.**

### Context
`measurement_frequency` is the compounding multiplier — it converts a per-event cost into
an annual number. A driver servicing 1,327 jobs/month yields a completely different leakage
story than a party rental owner taking 12 calls/week. These fields must be formal journey
settings, not free-text workarounds.

### US-LA-01-01 — Add `measurement_frequency` to journey_map schema
**Layer:** Backend — `tables/6_journey_map.xs`
**Change:** Add `int measurement_frequency?` — how many times per year this process runs
**Example:** 15,924 (1,327 jobs/month × 12)

### US-LA-01-02 — Add `measurement_period_label` to journey_map schema
**Layer:** Backend — `tables/6_journey_map.xs`
**Change:** Add `text measurement_period_label?` — human label for the period
**Example:** "per job", "per shift", "per call", "per week"

### US-LA-01-03 — Expose fields in journey settings PATCH endpoint
**Layer:** Backend — `apis/journey_map/journey_map_settings_journey_map_id_PATCH.xs`
**Change:** Accept `measurement_frequency` and `measurement_period_label` as optional inputs

### US-LA-01-04 — Expose fields via `update_journey_settings` MCP tool
**Layer:** `tools/14_update_journey_settings.xs`
**Change:** Add both fields to input schema and write path

**Acceptance Criteria — Epic LA-1:**
- Both fields writable via PATCH and MCP tool
- Returned in journey map load bundle
- Nullable — existing maps unaffected

---

## Epic LA-2 — Actor Cost Rate Fields
**The cost of a stage cannot be calculated without knowing the actor's rate.**

### Context
`cost_rate_value` and `cost_rate_unit` are currently dumped into `actor_fields` open JSON
with no enforced key name. Two AI sessions building maps for the same domain may store this
as `cost_per_hour`, `hourly_rate`, or `rate_value` — making aggregation impossible.
Formalizing these as actor identity fields (on `journey_lens`) ensures every actor has a
canonical rate the math engine can rely on.

### US-LA-02-01 — Add `cost_rate_value` to journey_lens schema
**Layer:** Backend — `tables/8_journey_lens.xs`
**Change:** Add `decimal cost_rate_value?`
**Example:** 30.00

### US-LA-02-02 — Add `cost_rate_unit` to journey_lens schema
**Layer:** Backend — `tables/8_journey_lens.xs`
**Change:** Add `enum cost_rate_unit? { values: ["per_minute","per_hour","per_day","per_week","per_event"] }`

### US-LA-02-03 — Expose fields in actor identity PATCH endpoint
**Layer:** `apis/journey_map/63_journey_lens_actor_fields_journey_lens_id_PATCH.xs`

### US-LA-02-04 — Expose fields via `update_actor_identity` MCP tool
**Layer:** `tools/13_update_actor_identity.xs`

**Acceptance Criteria — Epic LA-2:**
- Both fields writable per lens (per actor)
- Returned in lens object inside load bundle
- `cost_rate_unit` rejects values outside the enum

---

## Epic LA-3 — Cell Time Duration Fields
**Without stage-level time duration, there is no cost per event.**

### Context
`time_duration_value` and `time_duration_unit` are the per-stage time cost — equivalent to
Telogis `time_on_site`. Currently stored in open JSON under ad-hoc keys. Formalizing these
as first-class cell fields enables server-side cost calculation and consistent AI writes.

### US-LA-03-01 — Add `time_duration_value` to journey_cell schema
**Layer:** Backend — `tables/9_journey_cell.xs`
**Change:** Add `decimal time_duration_value?`

### US-LA-03-02 — Add `time_duration_unit` to journey_cell schema
**Layer:** Backend — `tables/9_journey_cell.xs`
**Change:** Add `enum time_duration_unit? { values: ["minutes","hours","days","weeks"] }`

### US-LA-03-03 — Expose fields in cell update endpoints and fill_cells MCP tool
**Layer:** `tools/51_fill_cells.xs`, `tools/3_update_cell.xs`

**Acceptance Criteria — Epic LA-3:**
- Time duration writable per cell (actor × stage)
- Returned in cell object inside load bundle
- Null on existing cells — no breaking change

---

## Epic LA-4 — Map Level Taxonomy
**Without a formal L1/L2/L3 label, AI cannot enforce guard rails or filter by depth.**

### Context
The Intelligence Layer skill defines three map levels: Architecture (L1), Actor Journey (L2),
and Atomic Stage (L3). Only L3 maps yield leakage insights. Currently this is tracked via
the free-text `journey_scope` field, making it unsearchable and unenforced.

### US-LA-04-01 — Add `map_level` enum to journey_map schema
**Layer:** Backend — `tables/6_journey_map.xs`
**Change:** Add `enum map_level? { values: ["architecture","actor-journey","atomic"] }`

### US-LA-04-02 — Add `parent_map_id` FK to journey_map schema
**Layer:** Backend — `tables/6_journey_map.xs`
**Change:** Add `int parent_map_id? { table = "journey_map" }` — points to the L1 or L2 map this drills down from

### US-LA-04-03 — Expose both fields in create and settings endpoints
**Layer:** `apis/journey_map/journey_map/create_draft_POST.xs`,
`apis/journey_map/journey_map_settings_journey_map_id_PATCH.xs`

### US-LA-04-04 — Expose `map_level` in `list_maps` and `search_maps` filter
**Layer:** `tools/54_list_maps.xs`, `tools/57_search_maps.xs`

**Acceptance Criteria — Epic LA-4:**
- `map_level` filterable in list and search
- `parent_map_id` returned in map bundle
- AI enforces L3 requirement before running leakage interview

---

## Epic LA-5 — Leakage Math API
**The 3-year number is the close. The server should calculate it, not the AI.**

### Context
Compounding leakage math (monthly → annual → 3yr) is currently performed manually by the
AI agent using cell data it reads from `get_map`. This is fragile, slow, and inconsistent.
A dedicated endpoint that reads formal fields and returns the calculation is more reliable
and enables frontend display without AI involvement.

### US-LA-05-01 — Leakage calculation endpoint
**New file:** `apis/journey_map/journey_map_id/leakage_GET.xs`
**Input:** `journey_map_id`
**Logic:** For each cell where `time_duration_value` and actor `cost_rate_value` are set:
```
stage_cost    = time_duration_value × cost_rate_value (normalized to per-hour)
annual_cost   = stage_cost × measurement_frequency
monthly_cost  = annual_cost ÷ 12
3yr_coi       = annual_cost × 3
```
**Output:**
```json
{
  "per_event": 80.00,
  "monthly": 1386.67,
  "annual": 16640.00,
  "3yr_cost_of_inaction": 49920.00,
  "by_stage": [{ "stage_key", "stage_label", "cost_per_event", "annual_cost" }],
  "leakage_cells": [{ "stage_key", "lens_key", "metric_label", "flag" }]
}
```

### US-LA-05-02 — Expose leakage endpoint via MCP tool
**New file or addition to** `mcp_servers/journey_map.xs`
**Tool name:** `calculate_leakage`
**Input:** `journey_map_id`

**Acceptance Criteria — Epic LA-5:**
- Returns correct math when all required fields are present
- Returns partial result with `incomplete_cells[]` when fields are missing
- MCP tool callable by AI in one step — no manual multiplication needed

---

## Epic LA-6a — Plan vs Actual: Discovery Inputs (Phase 1)
**Jesse tells you what actually happens. You record it next to what should happen.**

### Context
In Phase 1 (AI-assisted prospect discovery), there is no automated execution layer.
The prospect verbally tells you the gap: "I plan to respond in 5 minutes but it usually
takes 20–30." Both numbers are captured as discovery inputs directly on the cell.
This is the fastest path to generating a leakage number during a live prospect conversation.

The `stage_goal` (already on `journey_stage`) is the planned benchmark. The `actual_duration`
is what the prospect confesses. The gap between them, multiplied by `cost_rate_value` and
`measurement_frequency`, is the leakage cost.

### US-LA-06a-01 — Add `planned_duration` to journey_cell
**Layer:** Backend — `tables/9_journey_cell.xs`
**Change:** `decimal planned_duration?` — what the blueprint says this stage should take
**Note:** Often matches `time_duration_value` — but may differ if the plan was aspirational

### US-LA-06a-02 — Add `actual_duration` to journey_cell
**Layer:** Backend — `tables/9_journey_cell.xs`
**Change:** `decimal actual_duration?` — what the prospect says actually happens today
**Source:** Discovery interview input — written by AI agent, not by execution system

### US-LA-06a-03 — Expose fields via fill_cells and update_cell MCP tools
**Layer:** `tools/51_fill_cells.xs`, `tools/3_update_cell.xs`

### US-LA-06a-04 — Include gap calculation in leakage endpoint (LA-5)
**Layer:** `apis/journey_map/journey_map_id/leakage_GET.xs`
**Change:** When `actual_duration` is present, compute and return:
```
duration_gap         = actual_duration - planned_duration
gap_cost_per_event   = duration_gap × cost_rate_value (normalized to per-minute)
gap_annual_cost      = gap_cost_per_event × measurement_frequency
```

**Acceptance Criteria — Epic LA-6a:**
- Both fields writable on any cell via MCP tools
- Null by default — no breaking change to existing maps
- Gap cost surfaced in leakage endpoint response when both values present

---

## Epic LA-6b — Plan vs Actual: Execution Overlay (Phase 2)
**The system records what actually happened per run, per cell.**

### Context
Phase 2 is the automated version of Phase 1. Instead of Jesse telling you the actual,
the system records it every time the journey executes. This enables trend analysis,
pattern detection, and root cause identification across N instances.

The blueprint (`journey_map` + `journey_cell`) remains completely immutable.
Actuals live in a separate `execution_cell_record` table, linked to `workflow_execution`.
This mirrors the Telogis pattern: the planned route never changed; the actual was a
separate overlay (`route_response`) attached to the execution record.

**Do not implement until Epic LA-1 through LA-6a are complete.**

### US-LA-06b-01 — Create `execution_cell_record` table
**Layer:** New table — `tables/execution_cell_record.xs`
**Fields:**
```
id                  int (PK)
workflow_execution_id int (FK → workflow_execution)
journey_cell_id     int (FK → journey_cell)
actual_duration     decimal
actual_value        decimal
deviation_flag      enum { "on-target", "leakage", "overperformed" }
recorded_at         datetime
```

### US-LA-06b-02 — Write execution_cell_record on stage completion
**Layer:** `apis/journey_map/journey_map_id/invoke_POST.xs` (Epic IL-3)
**Change:** On each stage completion, write one `execution_cell_record` per actor cell

### US-LA-06b-03 — Aggregate actuals in leakage endpoint
**Layer:** `apis/journey_map/journey_map_id/leakage_GET.xs`
**Change:** When execution records exist, replace discovery actuals with aggregated actuals
and return `data_source: "execution"` vs `"discovery"` in response

**Acceptance Criteria — Epic LA-6b:**
- Blueprint never mutated by execution
- Each workflow_execution produces one execution_cell_record per actor cell per stage
- Leakage endpoint uses execution actuals when available, discovery actuals as fallback

---

## Epic LA-7 — Revenue at Risk Fields
**The labor cost is context. The lost revenue is the close.**

### Context
For SMB prospects like Jesse, the leakage story that creates urgency is not what they're
spending on their own time — it's the revenue they will never see because of a broken process.

Jesse example:
```
average_deal_value  = $350
miss_rate           = 40% (inquiries that go unanswered or too slow)
measurement_freq    = 1,040 inquiries/year
revenue_at_risk     = 1,040 × 40% × $350 = $145,600/yr
3yr_revenue_gap     = $145,600 × 3 = $436,800
```

The labor leakage ($7,620/yr) opens the conversation. The $436,800 revenue gap closes it.
Without these fields, the system can only produce the smaller, less compelling number.

### US-LA-07-01 — Add `average_deal_value` to journey_map schema
**Layer:** Backend — `tables/6_journey_map.xs`
**Change:** `decimal average_deal_value?` — average revenue value of one successfully closed event
**Example:** 350.00 (one party rental booking)

### US-LA-07-02 — Add `conversion_rate` to journey_map schema
**Layer:** Backend — `tables/6_journey_map.xs`
**Change:** `decimal conversion_rate?` — % of engaged/reached prospects that convert (0.0–1.0)
**Example:** 0.35 (35% of inquiries Jesse responds to become bookings)

### US-LA-07-03 — Add `miss_rate` to journey_map schema
**Layer:** Backend — `tables/6_journey_map.xs`
**Change:** `decimal miss_rate?` — % of events that go unanswered, delayed, or mishandled (0.0–1.0)
**Example:** 0.40 (40% of inquiries get no same-day response)
**Note:** Can also be captured as a `flag: "leakage"` metric in `actor_fields.metrics[]` at the cell level
for stage-specific miss rates. The map-level `miss_rate` is the aggregate for the close number.

### US-LA-07-04 — Expose fields via journey settings PATCH endpoint and MCP tool
**Layer:** `apis/journey_map/journey_map_settings_journey_map_id_PATCH.xs`,
`tools/14_update_journey_settings.xs`

### US-LA-07-05 — Include revenue at risk in leakage calculation endpoint
**Layer:** `apis/journey_map/journey_map_id/leakage_GET.xs`
**Change:** When `average_deal_value` + `miss_rate` + `measurement_frequency` are all present:
```
revenue_at_risk  = measurement_frequency × miss_rate × average_deal_value
3yr_revenue_gap  = revenue_at_risk × 3
```
Add to response:
```json
{
  "revenue_at_risk_annual": 145600.00,
  "3yr_revenue_gap": 436800.00,
  "data_inputs": {
    "average_deal_value": 350.00,
    "miss_rate": 0.40,
    "measurement_frequency": 1040
  }
}
```

**Acceptance Criteria — Epic LA-7:**
- All three fields writable via PATCH and MCP tool
- Returned in journey map load bundle
- Revenue at risk block included in leakage endpoint when inputs are present
- Omitted gracefully when any input is missing — no partial math surfaced

---

## Build Order

```
── Phase 1: Enable Labor Leakage Math ──────────────────────────────
US-LA-01-01,02   measurement_frequency + period_label schema
US-LA-01-03,04   expose via PATCH + MCP
US-LA-02-01,02   cost_rate_value + unit on lens schema
US-LA-02-03,04   expose via PATCH + MCP
US-LA-03-01,02   time_duration_value + unit on cell schema
US-LA-03-03      expose via fill_cells MCP
US-LA-04-01,02   map_level enum + parent_map_id schema
US-LA-04-03,04   expose in create, settings, list, search
US-LA-05-01      leakage calculation endpoint (labor math)
US-LA-05-02      leakage MCP tool

── Phase 1b: Enable Revenue Leakage Math ───────────────────────────
US-LA-07-01,02,03  average_deal_value + conversion_rate + miss_rate schema
US-LA-07-04        expose via PATCH + MCP
US-LA-07-05        add revenue block to leakage endpoint

── Phase 1c: Discovery Plan vs Actual ──────────────────────────────
US-LA-06a-01,02  planned_duration + actual_duration on cell schema
US-LA-06a-03     expose via MCP tools
US-LA-06a-04     gap cost in leakage endpoint

── Phase 2: Automated Execution Overlay ────────────────────────────
US-LA-06b-01     execution_cell_record table
US-LA-06b-02     write records on stage completion
US-LA-06b-03     aggregate actuals in leakage endpoint
```
