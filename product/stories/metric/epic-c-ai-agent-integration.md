# Epic C — AI Agent Integration

**Goal:** Make the chat AI aware of the metrics actor, able to infer metric values from sibling qualitative actor cells, and proactively offer to score stages after bulk fills. Depends on Epic A.

---

## ⚙️ Staff Engineer Review

### SE-C1 — Formula operator precedence bug in agent prompt
The stage health formula in the original prompt is wrong:
```
(csat/10 * 0.35) + ... + ((100-error)/100 * 0.10) * 10
```
The `* 10` only applies to the last term. Correct formula:
```
((csat/10 * 0.35) + (completion/100 * 0.35) + ((100-dropoff)/100 * 0.20) + ((100-error)/100 * 0.10)) * 10
```
**Resolution:** Fix the parentheses in US-MET-09. Add a worked example to the prompt so the AI can verify its calculation.

### SE-C2 — No overwrite protection for user-set values
If a user enters a real `csat_score: 9.5` from actual survey data and then asks the AI to "update metrics", the AI will overwrite the real value with its inference. This is a data integrity issue — real data is more valuable than AI inference.

**Resolution:** Add rule to agent prompt: "When calling `update_actor_cell_fields` on a metrics cell, skip any field that already has a non-null value UNLESS the user explicitly asks to recalculate or override." The `infer_stage_metrics` tool should also return an `already_set` flag per field.

### SE-C3 — Token load from reading all actor cell content
`get_slice` for a stage with 6 actor rows × 12 fields each = significant token consumption per inference call. With a large journey (10 stages), this could hit context limits.

**Resolution:** The `infer_stage_metrics` tool (MET-10) should be designed to fetch only the specific fields needed per actor type — not all fields of all cells. Targeted query: Customer(`emotions`, `friction_points`), Internal(`success_criteria`, `pain_points`), AI Agent(`failure_scenarios`, `confidence_threshold`). Return summary strings, not raw field dumps.

### SE-C4 — Race condition during bulk AI fills
If the AI is writing cells to Customer and Internal rows simultaneously, and the `infer_stage_metrics` tool reads those cells mid-write, it reads stale content and produces incorrect metrics.

**Resolution:** `infer_stage_metrics` must always read from committed DB state — only call it AFTER all sibling actor cell writes complete, never concurrently. Add to agent prompt: "Always complete all other actor cell writes for a stage before calling `infer_stage_metrics`."

### SE-C5 — Auto-offer guard: metrics row may not exist
US-MET-11 offers to calculate metrics after 3+ actor row fills. If no metrics lens exists in the map, the offer is misleading — clicking yes would fail silently.

**Resolution:** Add guard: only offer if `lenses.some(l => l.actorType === 'metrics')` is true. Otherwise skip the offer entirely.

---

## US-MET-08 — Inject metrics fields into AI agent context
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

- Add metrics field block gated on `$cell_actor_type == "metrics"`
- Follow the existing `$fv_temp` + paired `conditional` pattern used for all other actor types
- Inject all 8 fields with their current values (or "empty" if null)
- Include threshold hints inline so the AI knows what values are healthy vs. concerning:

```
## Cell Actor Fields — Current State (metrics)
Healthy thresholds: csat_score ≥ 8.0 | completion_rate ≥ 90% | drop_off_rate ≤ 10% | error_rate ≤ 5%

Fields to complete:
- CSAT Score (1–10) [key: csat_score]
- Completion Rate % [key: completion_rate]
- Drop-off Rate % [key: drop_off_rate]
- Avg Time to Complete (min) [key: avg_time_to_complete]
- Error Rate % [key: error_rate]
- SLA Compliance Rate % [key: sla_compliance_rate]
- Volume / Frequency [key: volume_frequency]
- Stage Health Score (1–10) [key: stage_health]
```

- This also applies the context injection key-label fix from the holistic plan

---

## US-MET-09 — Update agent system prompt with metrics field keys and inference rules
**File:** `agents/2_journey_map_assistant.xs`

**Add to `## Actor field key reference` section:**
```
**metrics:** csat_score, completion_rate, drop_off_rate, avg_time_to_complete,
  error_rate, sla_compliance_rate, volume_frequency, stage_health
```

**Add new `## Metrics actor inference rules` section:**
```
## Metrics actor inference rules

When filling a metrics actor cell, DO NOT guess — infer from sibling actor cells
at the SAME stage by calling get_slice first, then reading their actor_fields content.

Inference sources per metric:
- csat_score        ← Customer: emotions, friction_points
                       (heavy negative sentiment = 5–6, mild friction = 7–8, positive = 8–9)
- completion_rate   ← Internal: success_criteria, handoff_dependencies
                       (gaps or missing deps = lower rate)
- drop_off_rate     ← Customer: friction_points, decisions_required
                       (more friction sources = higher drop-off)
- error_rate        ← AI Agent: failure_scenarios, confidence_threshold
                       Engineering: error_states_edge_cases
- sla_compliance_rate ← Internal: employee_constraints
                         Engineering: performance_requirements
- avg_time_to_complete ← Internal: pain_points; AI Agent: escalation_logic
- stage_health      ← Calculate (note: multiply the ENTIRE sum by 10, not just the last term):
                       ((csat/10 * 0.35) + (completion/100 * 0.35)
                       + ((100-dropoff)/100 * 0.20) + ((100-error)/100 * 0.10)) * 10
                       Example: csat=8, completion=90, dropoff=10, error=3
                       = ((0.8*0.35)+(0.9*0.35)+(0.9*0.20)+(0.97*0.10))*10 = 8.67

Rules:
- Always call infer_stage_metrics AFTER all sibling actor cell writes are complete — never concurrently (SE-C4)
- Pass numeric values (not strings) to update_actor_cell_fields for all keys except volume_frequency
- Skip writing any field that already has a non-null value unless user explicitly asks to override (SE-C2)
- Calculate stage_health from inferred values and include it in the same update_actor_cell_fields call
- Also call update_cell with a plain-language summary of the stage health assessment
```

---

## US-MET-10 — Add `infer_stage_metrics` agent tool
**File:** New — `tools/13_infer_stage_metrics.xs` + registration in agent tool list

**Purpose:** Dedicated tool that reads all non-metrics actor cells at a given stage and returns structured inference suggestions. The agent uses this before writing to any metrics cell.

**Tool behavior:**
- Input: `stage_id` (required), `journey_map_id` (required)
- Fetches only the fields needed per actor type — NOT a full cell dump (see SE-C3):
  - Customer: `emotions`, `friction_points`, `decisions_required`
  - Internal: `success_criteria`, `handoff_dependencies`, `pain_points`, `employee_constraints`
  - AI Agent: `failure_scenarios`, `confidence_threshold`, `escalation_logic`
  - Engineering: `error_states_edge_cases`, `performance_requirements`
- Returns `already_set: true` per field if the metrics cell already has a non-null value (see SE-C2)
- Returns: structured object with suggested metric values and the source reasoning per field:
  ```json
  {
    "stage_id": 42,
    "stage_label": "Delivery Day Execution",
    "suggestions": {
      "csat_score":       { "value": 8.8, "already_set": false, "source": "Customer emotions: positive, friction low" },
      "completion_rate":  { "value": 92,  "already_set": false, "source": "Internal: clear success criteria, no dependency gaps" },
      "drop_off_rate":    { "value": 8,   "already_set": true,  "source": "Skipped — user value exists" },
      "error_rate":       { "value": 3.1, "already_set": false, "source": "AI Agent: confidence threshold defined, few failure scenarios" },
      "stage_health":     { "value": 9.0, "already_set": false, "source": "Calculated from above" }
    }
  }
  ```
- Tool instructions: "Use this BEFORE writing to any metrics cell. Only write fields where `already_set` is false. Do not estimate metrics without calling this tool first."

---

## US-MET-11 — Agent auto-offers metrics inference after bulk stage fills
**File:** `agents/2_journey_map_assistant.xs`

Add rule to system prompt:

```
## Metrics inference offer rule

After writing cells to 3 or more different actor rows at the same stage in a single session:
- Only offer if the map contains a metrics lens row (check map state for actorType = "metrics")
- Automatically append to your reply: "Would you like me to calculate the
  Metrics score for [stage name]? I can infer CSAT, completion rate, and
  stage health from the content I just wrote."
- If the user says yes: first confirm all actor cell writes are complete, then call
  infer_stage_metrics, then update_actor_cell_fields with only the non-already_set fields.
- Do not offer if no metrics row exists — SE-C5.
```

---

## Cross-Actor Inference Map

| Metric | Source Actor | Source Fields |
|---|---|---|
| `csat_score` | Customer | `emotions`, `friction_points` |
| `completion_rate` | Internal | `success_criteria`, `handoff_dependencies` |
| `drop_off_rate` | Customer | `friction_points`, `decisions_required` |
| `error_rate` | AI Agent + Engineering | `failure_scenarios`, `confidence_threshold`, `error_states_edge_cases` |
| `sla_compliance_rate` | Internal + Engineering | `employee_constraints`, `performance_requirements` |
| `avg_time_to_complete` | Internal + AI Agent | `pain_points`, `escalation_logic` |
| `stage_health` | Metrics (self) | Weighted composite of above |
