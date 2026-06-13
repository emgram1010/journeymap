# Scenario Leakage Comparison — Epic

**Status:** Ready for Development
**Goal:** Make the baseline → clone → tweak → compare loop produce meaningful financial
deltas so an operator can quantify the dollar impact of a process improvement before committing to it.

---

## Background & Why This Exists

Emgram supports L3 Atomic journey maps with leakage math — it can calculate what a broken
process costs per event, monthly, annually, and over 3 years. The scenario system lets users
clone a map, modify it, and compare the two side-by-side.

**The problem:** these two systems don't connect. Running `clone_scenario` today produces a
map with blank cost fields (durations and cost rates are not copied). `compare_scenarios`
only compares cell confirmation % ("journey health") — it has no cost math. The net result
is that a scenario comparison produces no financial delta — the most important number for
a client presentation is absent.

**What this epic fixes:**
1. Clone copies all numeric/cost fields so leakage math works on the clone immediately
2. Clone copies map-level leakage settings (`map_level`, `measurement_frequency`, etc.)
3. `calculate_leakage` uses `actual_duration` (real-world time) when present, falling back
   to `time_duration_value` (blueprint time)
4. `compare_scenarios` runs leakage math on both maps and returns a cost delta

---

## System Architecture — What Already Exists

Read these files before writing any code:

| File | What it is |
|---|---|
| `tables/6_journey_map.xs` | Journey map schema — includes `map_level`, `measurement_frequency`, `measurement_period_label`, `average_deal_value`, `miss_rate`, `conversion_rate` |
| `tables/8_journey_lens.xs` | Lens schema — includes `cost_rate_value`, `cost_rate_unit` |
| `tables/9_journey_cell.xs` | Cell schema — includes `time_duration_value`, `time_duration_unit`, `planned_duration`, `actual_duration` |
| `tools/76_calculate_leakage.xs` | MCP tool — leakage math. Uses `time_duration_value` + `cost_rate_value`. Returns `per_event`, `monthly`, `annual`, `cost_of_inaction_3yr`, `by_stage[]`, `incomplete_cells[]` |
| `tools/67_clone_scenario.xs` | MCP tool — deep-clones map+stages+lenses+cells. Currently does NOT copy numeric fields. |
| `apis/journey_map/126_journey_architecture_journey_architecture_id_scenarios_clone_POST.xs` | HTTP API for clone — same gap |
| `tools/68_compare_scenarios.xs` | MCP tool — compares cell health only. No leakage math. |

### Tool file conventions
Every MCP tool lives in TWO places and both must be kept in sync:
- **Canonical:** `ai/tool/{name}.xs`
- **Numbered copy:** `tools/{N}_{name}.xs`

The MCP server registrations live in:
- `mcp_servers/journey_map.xs` (primary — tool count must be updated in instructions string)
- `ai/mcp_server/journey_map.xs` (secondary — keep in sync)

### Leakage formula (current)
```
stage_cost = time_duration_hours × cost_rate_value   (normalized by unit)
total_per_event = sum of all stage costs
annual = total_per_event × measurement_frequency
cost_of_inaction_3yr = annual × 3
revenue_at_risk_annual = measurement_frequency × average_deal_value × miss_rate × conversion_rate
```
`actual_duration` and `planned_duration` exist on the cell but are currently ignored.

---

## Status

| Story | Status |
|---|---|
| SC-1 — Clone copies cell numeric fields | ❌ Missing |
| SC-2 — Clone copies lens cost rate fields | ❌ Missing |
| SC-3 — Clone copies map-level leakage settings | ❌ Missing |
| SC-4 — `calculate_leakage` uses `actual_duration` | ❌ Missing |
| SC-5 — `compare_scenarios` adds leakage cost delta | ❌ Missing |

---

## SC-1 — Clone copies cell numeric fields

**Files to update:**
- `tools/67_clone_scenario.xs`
- `ai/tool/clone_scenario.xs`
- `apis/journey_map/126_journey_architecture_journey_architecture_id_scenarios_clone_POST.xs`

**Change:** In the `db.add journey_cell` block inside the cell-clone loop, add the four
numeric fields that are currently omitted:

```
time_duration_value : $cell.time_duration_value
time_duration_unit  : $cell.time_duration_unit
planned_duration    : $cell.planned_duration
actual_duration     : $cell.actual_duration
```

These sit alongside the already-copied fields: `content`, `status`, `actor_fields`,
`change_source`, `is_locked`.

**Acceptance Criteria:**
- Cloned cells have identical `time_duration_value`, `time_duration_unit`, `planned_duration`,
  `actual_duration` as their source cells
- Null source values remain null on clone (no coercion to 0)
- `is_locked` still reset to `false` on all cloned cells (existing behaviour preserved)

---

## SC-2 — Clone copies lens cost rate fields

**Files to update:** same 3 files as SC-1

**Change:** In the `db.add journey_lens` block inside the lens-clone loop, add:

```
cost_rate_value: $lens.cost_rate_value
cost_rate_unit : $lens.cost_rate_unit
```

These sit alongside the already-copied fields: `key`, `label`, `description`, `display_order`,
`actor_type`, `template_key`, `role_prompt`, `persona_description`, `primary_goal`,
`standing_constraints`.

**Acceptance Criteria:**
- Cloned lenses have identical `cost_rate_value` and `cost_rate_unit` as source lenses
- Null values remain null

---

## SC-3 — Clone copies map-level leakage settings

**Files to update:** same 3 files as SC-1

**Change:** The new map `db.add journey_map` block currently hard-codes `status: "draft"` and
leaves all other fields null ("clean slate"). Update it to copy the leakage-critical fields:

```
map_level                : $source.map_level
measurement_frequency    : $source.measurement_frequency
measurement_period_label : $source.measurement_period_label
average_deal_value       : $source.average_deal_value
miss_rate                : $source.miss_rate
conversion_rate          : $source.conversion_rate
```

These must be read from the source map before the `db.add journey_map` call. Add a
`db.get journey_map` (field `id` = `source_map_id`) as `$source` near the top of the stack,
after the ownership precondition.

Non-leakage settings (`primary_actor`, `journey_scope`, `start_point`, etc.) should remain
null on the clone — the scenario is a process variant, not a copy of the narrative.

**Acceptance Criteria:**
- Cloned map has same `map_level` as source — `calculate_leakage` precondition passes
- `measurement_frequency`, `average_deal_value`, `miss_rate`, `conversion_rate` copied
- Narrative settings fields (`primary_actor`, `journey_scope`, etc.) remain null
- `cloned_from_map_id` still set correctly (existing behaviour)

---

## SC-4 — `calculate_leakage` uses `actual_duration` when present

**Files to update:**
- `tools/76_calculate_leakage.xs`
- `ai/tool/calculate_leakage.xs`

**Change:** In the per-cell cost calculation, replace the direct use of
`$cell.time_duration_value` with a resolved value that prefers `actual_duration`:

```
// Resolve effective duration — actual beats blueprint
var $effective_duration {
  value = $cell.actual_duration
}

conditional {
  if ($cell.actual_duration == null) {
    var.update $effective_duration {
      value = $cell.time_duration_value
    }
  }
}
```

Then use `$effective_duration` everywhere `$cell.time_duration_value` is currently used
(including the null-check that gates the cost calculation and the `$incomplete` push).

The `time_duration_unit` field is shared between `time_duration_value` and `actual_duration`
(they use the same unit — this is by design). No unit field changes needed.

**Response change:** Add `used_actual_duration: true/false` per incomplete cell entry
so the caller knows which duration was used. Also add a map-level flag:

```
used_actual_duration_count: {int}   ← how many cells used actual_duration vs time_duration_value
```

**Acceptance Criteria:**
- When `actual_duration` is set, it is used for cost math instead of `time_duration_value`
- When `actual_duration` is null, falls back to `time_duration_value` (no behaviour change)
- When both are null, cell is still added to `incomplete_cells[]`
- `used_actual_duration_count` returned in response

---

## SC-5 — `compare_scenarios` adds leakage cost delta

**Files to update:**
- `tools/68_compare_scenarios.xs`
- `ai/tool/compare_scenarios.xs`

**Change:** After building the health scorecard for each map (existing logic), add inline
leakage math for each map. Do NOT call `calculate_leakage` as a sub-tool call — replicate
the math inline (same pattern as the existing tool) to avoid dependency issues.

For each map (A and B):
1. Load the map record to get `measurement_frequency`, `average_deal_value`, `miss_rate`,
   `conversion_rate`
2. Load lenses to get `cost_rate_value` / `cost_rate_unit` per lens
3. For each cell: resolve effective duration (`actual_duration ?? time_duration_value`),
   compute cell cost using same formula as `calculate_leakage`
4. Sum to `total_per_event`, compute `annual` and `cost_of_inaction_3yr`
5. Compute `revenue_at_risk_annual` if `average_deal_value` + `miss_rate` are non-null

**Updated response shape:**

```json
{
  "map_a": {
    "id": 42,
    "title": "Baseline",
    "journey_health": 81,
    "total_cells": 20,
    "confirmed_cells": 16,
    "leakage": {
      "per_event": 80.00,
      "annual": 127392,
      "cost_of_inaction_3yr": 382176,
      "revenue_at_risk_annual": 145600,
      "incomplete_cell_count": 2
    },
    "stage_breakdown": [{ "stage_key": "s1", "stage_label": "Intake", "stage_health": 100 }]
  },
  "map_b": { ... },
  "delta": {
    "journey_health": 12,
    "annual_cost": -28000,
    "cost_of_inaction_3yr": -84000,
    "revenue_at_risk_annual": -32000
  }
}
```

`delta` values = map_b minus map_a (negative = improvement, positive = regression).
`leakage` is null when `map_level != 'atomic'` or no cells have duration data.

**Updated instructions string:**
> Compare the health scorecard and leakage cost of two scenarios side-by-side. Returns journey
> health, per-event cost, annual cost, 3-year cost of inaction, and revenue at risk for both
> maps plus a delta. Negative delta = improvement. null leakage means the map is not L3 atomic
> or has no duration data — never infer a winner when one side is null.

**Acceptance Criteria:**
- `delta` block present in every response (values null when leakage unavailable on either side)
- `leakage` null (not 0) when map is not atomic or has no duration data
- Negative delta correctly signals improvement
- Existing journey health comparison unchanged
- `incomplete_cell_count` surfaced so caller knows if numbers are partial

---

## Build Order

```
SC-3   Clone map settings     ← do first; unblocks leakage on clones
SC-1   Clone cell numerics    ← do alongside SC-3 (same files)
SC-2   Clone lens cost rates  ← do alongside SC-3 (same files)
SC-4   calculate_leakage fix  ← independent; can run in parallel
SC-5   compare_scenarios      ← depends on SC-4 formula being stable
```

SC-1, SC-2, SC-3 touch the same 3 files — execute them in a single edit pass.

---

## Complete File Change List

| File | Change |
|---|---|
| `tools/67_clone_scenario.xs` | SC-1 + SC-2 + SC-3 |
| `ai/tool/clone_scenario.xs` | SC-1 + SC-2 + SC-3 (mirror) |
| `apis/journey_map/126_journey_architecture_journey_architecture_id_scenarios_clone_POST.xs` | SC-1 + SC-2 + SC-3 (HTTP API) |
| `tools/76_calculate_leakage.xs` | SC-4 |
| `ai/tool/calculate_leakage.xs` | SC-4 (mirror) |
| `tools/68_compare_scenarios.xs` | SC-5 |
| `ai/tool/compare_scenarios.xs` | SC-5 (mirror) |

No DB schema changes required — all fields already exist.
No new MCP tools — existing tools are updated in place.
No frontend changes — the UI Leakage panel already calls `calculate_leakage` per map;
`compare_scenarios` delta will surface in the AI chat response.

---

## Non-Goals

- Cell-level diff view between two scenarios (needs lineage logic — deferred)
- Comparing more than 2 scenarios in one call
- Auto-applying compare insights back to a map
- UI panel for side-by-side leakage comparison (deferred — AI chat surfaces the delta)
