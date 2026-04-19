# Bug Fix — AI Agent Actor Cell Fields Not Populating

**Date:** 2026-04-18
**File changed:** `agents/2_journey_map_assistant.xs`
**Branch:** ai-agent

---

## Symptom

When asking the chatbot to populate cell fields for an `ai_agent` actor lens row, the agent
confirms it has written the fields but nothing appears in the structured actor fields on the cell.

---

## Root Cause

The agent's system prompt never listed the exact snake_case field key names for the `ai_agent`
actor type. The examples given in the prompt (`emotions`, `entry_trigger`, `task_objective`)
are customer/internal keys only.

When the agent called `update_actor_cell_fields`, it either:
- Used the human-readable label as the key (e.g. `"AI Model / Agent"` instead of `"ai_model_agent"`)
- Fell back to `update_cell` which writes the content/Notes field only

Both cases result in structured fields appearing empty in the UI.

The context injection in `52_journey_map_journey_map_id_ai_message_POST.xs` also only injects
human-readable labels (e.g. `"- AI Model / Agent"`) with no key hint, reinforcing the confusion.

---

## Fix Applied

Added a `## Actor field key reference` section to the system prompt in
`agents/2_journey_map_assistant.xs`, directly after `## Structured actor field rules`.

The section lists the exact snake_case keys for every actor type:
`ai_agent`, `customer`, `internal`, `engineering`, `handoff`, `vendor`, `financial`.

Includes an explicit instruction: *"Do NOT invent keys or use human-readable labels as keys."*

---

## Actor Field Keys Reference (all types)

| Actor Type | Keys |
|---|---|
| `ai_agent` | `ai_model_agent`, `input_data`, `decision_output`, `confidence_threshold`, `escalation_logic`, `training_data`, `retraining_frequency`, `bias_fairness_considerations`, `failure_scenarios`, `performance_metrics`, `model_owner`, `explainability_needs` |
| `customer` | `entry_trigger`, `emotions`, `information_needs`, `decisions_required`, `friction_points`, `assumptions`, `acceptance_criteria`, `expected_output`, `channel_touchpoint` |
| `internal` | `task_objective`, `entry_trigger`, `tools_systems`, `information_needs`, `decisions_required`, `friction_points`, `assumptions`, `handoff_dependencies`, `success_criteria`, `output_deliverable`, `employee_constraints`, `pain_points` |
| `engineering` | `system_service_owner`, `data_inputs`, `data_outputs`, `api_integration_dependencies`, `business_rules_logic`, `error_states_edge_cases`, `data_storage_requirements`, `security_permissions`, `performance_requirements`, `audit_logging_needs` |
| `handoff` | `trigger_event`, `upstream_actor`, `prerequisite_data`, `upstream_dependencies`, `handoff_output`, `handoff_format`, `handoff_timing`, `downstream_actor`, `validation_rules`, `failure_recovery`, `communication_method`, `data_retention_policy` |
| `vendor` | `vendor_name_type`, `role_at_step`, `engagement_trigger`, `contractual_obligations`, `information_needs`, `information_returned`, `integration_method`, `sla_performance_metrics`, `failure_scenario`, `escalation_path`, `data_privacy_compliance`, `vendor_constraints`, `cost_impact`, `dependency_on_internal` |
| `financial` | `cost_to_serve`, `revenue_at_risk`, `automation_savings`, `upsell_opportunity`, `revenue_leakage`, `cost_efficiency_note`, `breakeven_threshold`, `cac_contribution`, `clv_impact`, `priority_score` |

---

## Notes

- This same key-naming failure could affect any actor type, not just `ai_agent`.
  The fix covers all types as a precaution.
- See `product/wholistic/actor-cell-fields-agent-context.md` for the full holistic fix plan.
