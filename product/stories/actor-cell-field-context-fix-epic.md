# Epic: Actor Cell Field Context Fix — Agent Key Naming Reliability

**Date:** 2026-04-22
**Related:** `product/bug-fixes/ai-agent-actor-cell-fields-not-populating.md`
**Related:** `product/wholistic/actor-cell-fields-agent-context.md` (Gap 1 + Gap 3)

---

## Goal

The AI chat agent confirms it has populated structured actor cell fields but nothing appears in
the UI. Root cause: the context injected into the agent shows human-readable field labels with
no key hint, and the `update_actor_cell_fields` tool instructions only example customer keys.
The agent guesses the wrong key name, the write silently succeeds with junk keys, and the UI
shows empty fields.

This epic fixes the two fastest-path gaps: runtime key hints in context injection (Gap 1) and
point-of-use key reference in the tool instructions (Gap 3).

---

## Affected Actor Types

`customer`, `internal`, `engineering`, `ai_agent`, `handoff`, `vendor`, `financial`

Metrics is already correct — it uses `[key: field_key]` inline. All other types need to be
brought to the same standard.

---

## Stories

### US-ACFC-01 — Add `[key: xxx]` hints to context injection for all non-metrics actor types

**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

**Problem:** Every field emitted in the `## Cell Actor Fields — Current State` context block
for non-metrics actor types shows only the human label, e.g.:

```
Fields still to complete:
- Trigger Event
- Upstream Actor
```

The metrics block already emits the correct format:
```
- CSAT Score (1-10) [key: csat_score]
- Completion Rate % [key: completion_rate]
```

**Change:** For every actor type block (customer, internal, engineering, ai_agent, handoff,
vendor, financial), update both the **filled** and **empty** line concat statements to include
`[key: field_key]` after the label, matching the metrics pattern exactly.

Filled line format (currently):
```
|concat:"- Trigger Event: ":$fv_temp:"\n":""
```
Updated to:
```
|concat:"- Trigger Event [key: trigger_event]: ":$fv_temp:"\n":""
```

Empty line format (currently):
```
|concat:"- Trigger Event\n":""
```
Updated to:
```
|concat:"- Trigger Event [key: trigger_event]\n":""
```

Apply this change to every field across all 7 actor type blocks. See Fields Reference below
for the full label → key mapping per actor type.

**Acceptance Criteria:**
- Every field line in the injected context includes `[key: field_key]` whether filled or empty
- Metrics block is not modified (already correct)
- An agent receiving context for a handoff cell sees `- Trigger Event [key: trigger_event]`
  not `- Trigger Event`
- Existing actor types that were already partially correct (internal `handoff_dependencies`
  label at line ~1075) are also updated to include their key hint
- No change to the logic that selects filled vs. empty lines

---

### US-ACFC-02 — Add per-actor key table to `update_actor_cell_fields` tool instructions

**File:** `tools/12_update_actor_cell_fields.xs`

**Problem:** The tool's `instructions` block only shows a customer example:
```
{ emotions: "Anxious", entry_trigger: "Order confirmed" }
```
When the agent reads this tool at point-of-use for a handoff or vendor cell, it has no
reference for the valid keys on that actor type.

**Change:** Extend the instructions block to include a per-actor-type key reference table
after the existing input description. Add a warning that only listed keys are valid — do not
invent keys or use human-readable labels.

New section to append inside `instructions`:

```
Valid actor_fields keys by actor_type:
  customer:    entry_trigger, emotions, information_needs, decisions_required,
               friction_points, assumptions, acceptance_criteria, expected_output,
               channel_touchpoint
  internal:    task_objective, entry_trigger, tools_systems, information_needs,
               decisions_required, friction_points, assumptions, handoff_dependencies,
               success_criteria, output_deliverable, employee_constraints, pain_points
  engineering: system_service_owner, data_inputs, data_outputs,
               api_integration_dependencies, business_rules_logic, error_states_edge_cases,
               data_storage_requirements, security_permissions, performance_requirements,
               audit_logging_needs
  ai_agent:    ai_model_agent, input_data, decision_output, confidence_threshold,
               escalation_logic, training_data, retraining_frequency,
               bias_fairness_considerations, failure_scenarios, performance_metrics,
               model_owner, explainability_needs
  handoff:     trigger_event, upstream_actor, prerequisite_data, upstream_dependencies,
               handoff_output, handoff_format, handoff_timing, downstream_actor,
               validation_rules, failure_recovery, communication_method,
               data_retention_policy
  vendor:      vendor_name_type, role_at_step, engagement_trigger,
               contractual_obligations, information_needs, information_returned,
               integration_method, sla_performance_metrics, failure_scenario,
               escalation_path, data_privacy_compliance, vendor_constraints,
               cost_impact, dependency_on_internal
  financial:   cost_to_serve, revenue_at_risk, automation_savings, upsell_opportunity,
               revenue_leakage, cost_efficiency_note, breakeven_threshold,
               cac_contribution, clv_impact, priority_score
  metrics:     csat_score, completion_rate, drop_off_rate, avg_time_to_complete,
               error_rate, sla_compliance_rate, volume_frequency, stage_health

Do NOT invent keys. Do NOT use human-readable labels as keys (e.g. use
"trigger_event" not "Trigger Event"). Only the keys listed above are valid
for their respective actor types.
```

**Acceptance Criteria:**
- Tool instructions contain the per-actor key reference table
- All 8 actor types are listed with their exact snake_case keys
- The existing customer example `{ emotions: "Anxious", entry_trigger: "Order confirmed" }`
  is retained and the new table follows it
- Keys match exactly what is defined in `webapp/protype-2/src/types.ts` interfaces

---

## Fields Reference

### `handoff` (12 keys)
| Label | Key |
|---|---|
| Trigger Event | `trigger_event` |
| Upstream Actor | `upstream_actor` |
| Prerequisite Data | `prerequisite_data` |
| Upstream Dependencies | `upstream_dependencies` |
| Handoff Output | `handoff_output` |
| Handoff Format | `handoff_format` |
| Handoff Timing | `handoff_timing` |
| Downstream Actor | `downstream_actor` |
| Validation Rules | `validation_rules` |
| Failure Recovery | `failure_recovery` |
| Communication Method | `communication_method` |
| Data Retention Policy | `data_retention_policy` |

### `customer` (9 keys)
| Label | Key |
|---|---|
| Entry Point / Trigger | `entry_trigger` |
| Feelings / Emotions | `emotions` |
| Information Needs | `information_needs` |
| Decisions Required | `decisions_required` |
| Friction Points | `friction_points` |
| Assumptions | `assumptions` |
| Acceptance Criteria | `acceptance_criteria` |
| Expected Output | `expected_output` |
| Channel / Touchpoint | `channel_touchpoint` |

### `internal` (12 keys)
| Label | Key |
|---|---|
| Task Objective | `task_objective` |
| Entry Trigger | `entry_trigger` |
| Tools / Systems | `tools_systems` |
| Information Needs | `information_needs` |
| Decisions Required | `decisions_required` |
| Friction Points | `friction_points` |
| Assumptions | `assumptions` |
| Handoff Dependencies | `handoff_dependencies` |
| Success Criteria | `success_criteria` |
| Output / Deliverable | `output_deliverable` |
| Employee Constraints | `employee_constraints` |
| Pain Points | `pain_points` |

### `engineering` (10 keys)
| Label | Key |
|---|---|
| System / Service Owner | `system_service_owner` |
| Data Inputs | `data_inputs` |
| Data Outputs | `data_outputs` |
| API / Integration Dependencies | `api_integration_dependencies` |
| Business Rules / Logic | `business_rules_logic` |
| Error States / Edge Cases | `error_states_edge_cases` |
| Data Storage Requirements | `data_storage_requirements` |
| Security / Permissions | `security_permissions` |
| Performance Requirements | `performance_requirements` |
| Audit / Logging Needs | `audit_logging_needs` |

### `ai_agent` (12 keys)
| Label | Key |
|---|---|
| AI Model / Agent | `ai_model_agent` |
| Input Data | `input_data` |
| Decision / Output | `decision_output` |
| Confidence Threshold | `confidence_threshold` |
| Escalation Logic | `escalation_logic` |
| Training Data | `training_data` |
| Retraining Frequency | `retraining_frequency` |
| Bias / Fairness Considerations | `bias_fairness_considerations` |
| Failure Scenarios | `failure_scenarios` |
| Performance Metrics | `performance_metrics` |
| Model Owner | `model_owner` |
| Explainability Needs | `explainability_needs` |

### `vendor` (14 keys)
| Label | Key |
|---|---|
| Vendor Name / Type | `vendor_name_type` |
| Role at Step | `role_at_step` |
| Engagement Trigger | `engagement_trigger` |
| Contractual Obligations | `contractual_obligations` |
| Information Needs | `information_needs` |
| Information Returned | `information_returned` |
| Integration Method | `integration_method` |
| SLA / Performance Metrics | `sla_performance_metrics` |
| Failure Scenario | `failure_scenario` |
| Escalation Path | `escalation_path` |
| Data Privacy / Compliance | `data_privacy_compliance` |
| Vendor Constraints | `vendor_constraints` |
| Cost Impact | `cost_impact` |
| Dependency on Internal | `dependency_on_internal` |

### `financial` (10 keys)
| Label | Key |
|---|---|
| Cost to Serve | `cost_to_serve` |
| Revenue at Risk | `revenue_at_risk` |
| Automation Savings | `automation_savings` |
| Upsell Opportunity | `upsell_opportunity` |
| Revenue Leakage | `revenue_leakage` |
| Cost Efficiency Note | `cost_efficiency_note` |
| Breakeven Threshold | `breakeven_threshold` |
| CAC Contribution | `cac_contribution` |
| CLV Impact | `clv_impact` |
| Priority Score | `priority_score` |
