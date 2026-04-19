# Epic: Metrics Actor — Journey Performance Scorecard

**Goal:** Add a `metrics` actor type that captures operational KPIs at each stage (CSAT, completion rate, drop-off, error rate, stage health). Metrics cells are populated by the AI inferring from existing qualitative actor cells — no manual data entry required. Stage health scores roll up to a floating journey-level widget that turns green/red in real-time as the map is modified, giving PMs a directional signal while building.

---

## Brainstorm Context

- Metrics actor is the **outcome layer** — it measures the result of what Customer, Internal, AI Agent, Financial, and Engineering actors describe
- Financial actor owns **financial quantitative** (cost, revenue) — Metrics actor owns **operational quantitative** (CSAT, completion, error rate)
- Top 3 PM metrics: `stage_health` (prioritization), `csat_score` (customer signal), `completion_rate` (where the journey breaks)
- AI infers metrics from qualitative fields — user corrects via chat if they have real data
- Floating widget shows 3 metrics with delta tracking (green = improving, red = degrading)

---

## Epic A — Metrics Actor Foundation

### US-MET-01 — Update `ActorType` and add `MetricsActorFields` to types.ts
**File:** `webapp/protype-2/src/types.ts`
- Add `'metrics'` to the `ActorType` union
- Add `MetricsActorFields` interface with typed numeric fields:
  - `csat_score?: number | null` — 1–10
  - `completion_rate?: number | null` — 0–100 (%)
  - `drop_off_rate?: number | null` — 0–100 (%)
  - `avg_time_to_complete?: number | null` — minutes
  - `error_rate?: number | null` — 0–100 (%)
  - `sla_compliance_rate?: number | null` — 0–100 (%)
  - `volume_frequency?: string | null` — free text (e.g. "~300 interactions/day")
  - `stage_health?: number | null` — 1–10, auto-calculated composite
- Update `ActorFields` union to include `MetricsActorFields`
- Note: `MetricsActorFields` intentionally uses `number | null` — first typed actor fields in the system

### US-MET-02 — Update Financial actor types to support numeric monetary values
**File:** `webapp/protype-2/src/types.ts`
- Add `FinancialActorNumericFields` interface alongside existing `FinancialActorFields`:
  - `cost_to_serve_value?: number | null` — USD numeric
  - `revenue_at_risk_value?: number | null` — USD numeric
  - `automation_savings_value?: number | null` — USD numeric
  - `revenue_leakage_value?: number | null` — USD numeric
- Existing string fields stay unchanged — numeric fields are additive paired values
- Update `ActorFields` union to include `FinancialActorNumericFields`
- Purpose: enables rollup math (sum across stages) for journey P&L widget

### US-MET-03 — Add `metrics` template to constants.ts
**File:** `webapp/protype-2/src/constants.ts`
- Add `metrics` entry to `ACTOR_TEMPLATES` array
- `actorType: 'metrics'`, `templateKey: 'metrics-v1'`
- `label: 'Metrics'`, `icon: '📊'`
- `description`: "Operational KPIs — CSAT, completion rate, drop-off, error rate, and stage health score at each stage. AI-inferred from qualitative actor content."
- 8 `CellFieldDef` entries:

| Key | Label | Placeholder |
|---|---|---|
| `csat_score` | CSAT Score (1–10) | e.g. 7.4 |
| `completion_rate` | Completion Rate (%) | e.g. 89 |
| `drop_off_rate` | Drop-off Rate (%) | e.g. 11 |
| `avg_time_to_complete` | Avg Time to Complete (min) | e.g. 4 |
| `error_rate` | Error Rate (%) | e.g. 3.2 |
| `sla_compliance_rate` | SLA Compliance Rate (%) | e.g. 91 |
| `volume_frequency` | Volume / Frequency | e.g. ~300 interactions/day |
| `stage_health` | Stage Health Score (1–10) | Auto-calculated — or override |

- `cellFieldScaffold`: all 8 keys set to `null`
- `rolePrompt`: instructs AI to infer numeric values from Customer friction_points/emotions, Internal pain_points/success_criteria, AI Agent failure_scenarios/confidence_threshold, Financial revenue_leakage, and Engineering error_states_edge_cases at the same stage

### US-MET-04 — Add `metrics` to add-lens API enum and scaffold block
**File:** `apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs`
- Add `"metrics"` to the `actor_type` enum values list
- Add scaffold block following the existing conditional pattern:
  ```
  conditional {
    if ($input.actor_type == "metrics") {
      var.update $effective_template_key { value = "metrics-v1" }
      var.update $actor_fields_scaffold {
        value = {}
          |set:"csat_score":null
          |set:"completion_rate":null
          |set:"drop_off_rate":null
          |set:"avg_time_to_complete":null
          |set:"error_rate":null
          |set:"sla_compliance_rate":null
          |set:"volume_frequency":null
          |set:"stage_health":null
      }
    }
  }
  ```
- No DB schema change needed — `actor_fields` is already a JSON column

### US-MET-05 — Add `metrics` to DB actor_type enum
**File:** Xano DB — `journey_lens.actor_type` enum
- Add `"metrics"` to the enum values
- No other schema changes required

---

## Epic B — Metrics Cell Display

### US-MET-06 — Metrics cell matrix display (scorecard chip layout)
**File:** `webapp/protype-2/src/App.tsx` (or cell renderer component)
- When a cell belongs to a `metrics` actor row, render a special compact scorecard layout instead of plain text
- Display format inside the matrix cell:
  ```
  Stage Health  7.4  🟡
  CSAT          8.1  🟢   Completion  89%  🟡
  Drop-off     11%  🔴   Error rate  3.2%  🟢
  ```
- Color thresholds:
  - `stage_health`: ≥ 8 = 🟢, 6–7.9 = 🟡, < 6 = 🔴
  - `csat_score`: ≥ 8 = 🟢, 6–7.9 = 🟡, < 6 = 🔴
  - `completion_rate`: ≥ 90% = 🟢, 75–89% = 🟡, < 75% = 🔴
  - `drop_off_rate`: ≤ 10% = 🟢, 11–20% = 🟡, > 20% = 🔴
  - `error_rate`: ≤ 5% = 🟢, 6–15% = 🟡, > 15% = 🔴
- Stage health is auto-calculated as weighted average: `(csat_score/10 * 0.35) + (completion_rate/100 * 0.35) + ((100 - drop_off_rate)/100 * 0.20) + ((100 - error_rate)/100 * 0.10)` × 10
- If `stage_health` is explicitly set by user, use that value — otherwise show calculated
- Fall back to plain text content if no metric fields are populated

### US-MET-07 — Metrics cell detail panel view
**File:** `webapp/protype-2/src/App.tsx` (Cell Detail Panel section)
- When cell detail panel opens for a metrics cell, render a structured metrics panel instead of the standard field list
- Show each metric as a labeled row with:
  - Current value (large, bold)
  - Color indicator based on threshold
  - Target/benchmark value (configurable, defaults shown)
  - Below/above threshold label
- Stage Health Score shown prominently at top as a gauge or large composite number
- "AI Infer from Actors" button — triggers cross-actor inference for this cell's stage
- Editable inline — user can override any value

---

## Epic C — AI Agent Integration

### US-MET-08 — Inject metrics fields into AI agent context
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
- Add metrics field block gated on `$cell_actor_type == "metrics"`
- Follow the `$fv_temp` + paired `conditional` pattern used for other actor types
- 8 fields with labels and current values (or "empty" if null)
- Include threshold hints in the context so AI knows what values are healthy vs. concerning

### US-MET-09 — Update agent system prompt with metrics actor field keys and inference rules
**File:** `agents/2_journey_map_assistant.xs`
- Add `metrics` to the `## Actor field key reference` section:
  ```
  **metrics:** csat_score, completion_rate, drop_off_rate, avg_time_to_complete,
    error_rate, sla_compliance_rate, volume_frequency, stage_health
  ```
- Add `## Metrics actor inference rules` section:
  ```
  When filling a metrics actor cell, infer values from other actor cells at the SAME stage:
  - csat_score       ← Customer: emotions, friction_points (negative sentiment = lower score)
  - completion_rate  ← Internal: success_criteria, handoff_dependencies (gaps = lower rate)
  - drop_off_rate    ← Customer: friction_points, decisions_required (more friction = higher drop-off)
  - error_rate       ← AI Agent: failure_scenarios, confidence_threshold; Engineering: error_states_edge_cases
  - sla_compliance   ← Internal: employee_constraints; Engineering: performance_requirements
  - stage_health     ← Weighted composite — calculate from other metrics; range 1–10
  Always call get_slice to read sibling actor cells at the target stage before writing metrics.
  Use update_actor_cell_fields with numeric values (not strings) for all metric keys except volume_frequency.
  ```

### US-MET-10 — Add `infer_stage_metrics` agent tool
**File:** New tool — `tools/13_infer_stage_metrics.xs` + agent tool registration
- Tool reads all non-metrics actor cells at a given `stage_id`
- Analyzes qualitative content from Customer, Internal, AI Agent, Financial, Engineering cells
- Returns suggested numeric values for all 8 metrics fields with confidence notes
- Agent then calls `update_actor_cell_fields` to write the inferred values to the metrics cell
- Tool instructions: "Use this when the user asks to populate, infer, or analyze metrics for a stage. Always call this before update_actor_cell_fields on a metrics cell."

### US-MET-11 — Update agent to auto-trigger metrics inference after bulk cell fills
**File:** `agents/2_journey_map_assistant.xs`
- Add rule: when the agent has just filled cells across multiple actor rows for a stage, automatically offer to infer metrics for that stage
- Trigger phrase in system prompt: "After completing cells for 3 or more actor rows at the same stage, suggest to the user: 'Would you like me to calculate the metrics score for [stage name]?'"

---

## Epic D — Floating Journey Health Widget

### US-MET-12 — Journey Health Widget component
**File:** `webapp/protype-2/src/App.tsx` (or new `JourneyHealthWidget.tsx`)
- Floating, draggable widget anchored top-right of the journey matrix by default
- Collapsed state (default): single line showing Journey Health Score + color + delta arrow
  ```
  📊 Journey Health  7.4  ▲ +0.6  🟢
  ```
- Expanded state (hover or click):
  ```
  📊 Journey Health    7.4  ▲ +0.6  🟢
     Revenue at Risk  $94K  ▼ -$18K 🟢
     Critical Stages    2   ▼ -2    🟢
  ```
- Click expanded → opens full scorecard side panel (stage-by-stage breakdown)
- Widget is draggable — position persists in localStorage per map
- Collapsible via X button — restores via toolbar button

### US-MET-13 — Journey scorecard rollup API endpoint
**File:** New API — `apis/journey_map/XX_journey_map_journey_map_id_scorecard_GET.xs`
- `GET /journey_map/{journey_map_id}/scorecard`
- Reads all metrics cells for the map → averages `stage_health` → Journey Health Score
- Reads all financial cells → sums `revenue_at_risk_value` → Revenue at Risk total
- Counts stages where `stage_health < 6` → Critical Stages count
- Returns:
  ```json
  {
    "journey_health": 7.4,
    "revenue_at_risk": 94000,
    "critical_stages": 2,
    "stage_breakdown": [
      { "stage_label": "Order & Inventory Lock", "stage_health": 7.8, "csat": 8.1 },
      ...
    ]
  }
  ```

### US-MET-14 — Widget delta tracking (session-level baseline)
**File:** `webapp/protype-2/src/App.tsx`
- On map load, fetch scorecard and store as `sessionBaseline` in component state
- After every cell save (any actor type), re-fetch scorecard
- Display delta vs. baseline: `▲ +0.6` (green) or `▼ -0.4` (red) or `—` (no change)
- Delta resets when user refreshes or navigates away
- Color logic:
  - Journey Health ↑ = 🟢, ↓ = 🔴
  - Revenue at Risk ↓ = 🟢 (less risk), ↑ = 🔴
  - Critical Stages ↓ = 🟢, ↑ = 🔴

---

## Fields Reference — Metrics Actor

| # | Key | Type | Label | Healthy Threshold |
|---|---|---|---|---|
| 1 | `csat_score` | number 1–10 | CSAT Score | ≥ 8.0 |
| 2 | `completion_rate` | number % | Completion Rate | ≥ 90% |
| 3 | `drop_off_rate` | number % | Drop-off Rate | ≤ 10% |
| 4 | `avg_time_to_complete` | number (min) | Avg Time to Complete | context-dependent |
| 5 | `error_rate` | number % | Error Rate | ≤ 5% |
| 6 | `sla_compliance_rate` | number % | SLA Compliance Rate | ≥ 90% |
| 7 | `volume_frequency` | string | Volume / Frequency | n/a |
| 8 | `stage_health` | number 1–10 | Stage Health Score | ≥ 8.0 |

---

## Cross-Actor Inference Map

| Metric field | Source actor | Source fields read |
|---|---|---|
| `csat_score` | Customer | `emotions`, `friction_points` |
| `completion_rate` | Internal | `success_criteria`, `handoff_dependencies` |
| `drop_off_rate` | Customer | `friction_points`, `decisions_required` |
| `error_rate` | AI Agent + Engineering | `failure_scenarios`, `confidence_threshold`, `error_states_edge_cases` |
| `sla_compliance_rate` | Internal + Engineering | `employee_constraints`, `performance_requirements` |
| `avg_time_to_complete` | Internal + AI Agent | `pain_points`, `escalation_logic` |
| `stage_health` | Metrics (self) | Weighted composite of above |

---

## Build Sequence

| Phase | Stories | Outcome |
|---|---|---|
| **MVP** | MET-01 → MET-05 | Metrics actor exists, can be added to map, AI can write to it |
| **Display** | MET-06 → MET-07 | Matrix cells and detail panel show scorecard format with color coding |
| **AI Integration** | MET-08 → MET-11 | AI infers metrics from sibling actor cells automatically |
| **Widget** | MET-12 → MET-14 | Floating health widget with real-time delta tracking |

---

## Notes

- `metrics` actor type is the first in the system to use `number | null` typed fields — all others are `string | null`. The `ActorFields` union and any JSON handling must accommodate this.
- Financial numeric fields (MET-02) are additive — existing string fields unchanged. No migration needed.
- Stage health auto-calculation happens on the frontend — no backend formula needed. User can override.
- Widget scorecard endpoint only has data when at least one metrics cell is populated. Widget shows "No metrics data yet" empty state otherwise.
- See `product/wholistic/actor-cell-fields-agent-context.md` for related context injection improvements that benefit this feature.
