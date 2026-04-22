// Writes structured actor_fields into a single cell identified by stage_key + lens_key.
// Skips locked and confirmed cells. Supports partial updates — only provided keys are merged.
tool update_actor_cell_fields {
  instructions = """
      Use this tool to write one or more structured actor fields into a specific cell.
      Actor fields are the template-specific sub-fields (e.g. emotions, entry_trigger,
      task_objective, trigger_event) that belong to the actor type assigned to the row.
    
      Identify the cell by stage_key + lens_key. Do NOT pass cell IDs.
    
      Pass only the fields you have information for — existing values in other keys are preserved.
      The cell will be skipped if it is locked (is_locked=true) or has status 'confirmed'.
    
      Input:
      - journey_map_id: The ID of the journey map
      - stage_key: The key of the target stage (e.g. 'awareness', 'delivery')
      - lens_key: The key of the target lens (e.g. 'customer', 'driver')
      - actor_fields: A JSON object with the fields to set, e.g. { emotions: "Anxious", entry_trigger: "Order confirmed" }
      - conversation_id: (optional) for tool trace logging
      - turn_id: (optional) for tool trace logging
    
      Valid actor_fields keys by actor_type — use ONLY these exact snake_case keys.
      Do NOT invent keys. Do NOT use human-readable labels as keys.
    
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
    
      Response shape:
      {
        applied: true/false,
        cell: { id, stage_key, lens_key, actor_fields, status, is_locked },
        skip_reason: null | 'locked' | 'confirmed' | 'not_found'
      }
    """

  input {
    int journey_map_id filters=min:1
    int conversation_id?
    text turn_id?
    text stage_key filters=trim
    text lens_key filters=trim
    json actor_fields
  }

  stack {
    // Resolve stage
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.stage_key
      return = {type: "single"}
    } as $stage
  
    // Resolve lens
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.lens_key
      return = {type: "single"}
    } as $lens
  
    var $result {
      value = {applied: false, cell: null, skip_reason: "not_found"}
    }
  
    conditional {
      if ($stage != null && $lens != null) {
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $lens.id
          return = {type: "single"}
        } as $cell
      
        conditional {
          if ($cell == null) {
            var.update $result {
              value = {applied: false, cell: null, skip_reason: "not_found"}
            }
          }
        }
      
        conditional {
          if ($cell != null && $cell.is_locked) {
            var.update $result {
              value = {
                applied    : false
                cell       : {id: $cell.id, stage_key: $input.stage_key, lens_key: $input.lens_key, actor_fields: $cell.actor_fields, status: $cell.status, is_locked: $cell.is_locked}
                skip_reason: "locked"
              }
            }
          }
        }
      
        conditional {
          if ($cell != null && $cell.is_locked == false && $cell.status == "confirmed") {
            var.update $result {
              value = {
                applied    : false
                cell       : {id: $cell.id, stage_key: $input.stage_key, lens_key: $input.lens_key, actor_fields: $cell.actor_fields, status: $cell.status, is_locked: $cell.is_locked}
                skip_reason: "confirmed"
              }
            }
          }
        }
      
        conditional {
          if ($cell != null && $cell.is_locked == false && $cell.status != "confirmed") {
            // Merge: start from existing actor_fields, overlay incoming keys
            var $merged_fields {
              value = $cell.actor_fields
            }
          
            conditional {
              if ($merged_fields == null) {
                var.update $merged_fields {
                  value = {}
                }
              }
            }
          
            // Overlay each incoming key onto merged_fields
            var $incoming_keys {
              value = $input.actor_fields|keys
            }
          
            foreach ($incoming_keys) {
              each as $fk {
                var $fv {
                  value = $input.actor_fields|get:$fk
                }
              
                var.update $merged_fields {
                  value = $merged_fields|set:$fk:$fv
                }
              }
            }
          
            db.patch journey_cell {
              field_name = "id"
              field_value = $cell.id
              data = {
                actor_fields   : $merged_fields
                status         : "draft"
                change_source  : "ai"
                updated_at     : "now"
                last_updated_at: "now"
              }
            } as $updated_cell
          
            var.update $result {
              value = {
                applied    : true
                cell       : {id: $updated_cell.id, stage_key: $input.stage_key, lens_key: $input.lens_key, actor_fields: $updated_cell.actor_fields, status: $updated_cell.status, is_locked: $updated_cell.is_locked}
                skip_reason: null
              }
            }
          }
        }
      }
    }
  
    // Tool trace logging
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "update_actor_cell_fields"
            tool_category : "write"
            input_summary : $input.stage_key ~ " × " ~ $input.lens_key
            output_summary: $result.applied ? "Applied actor fields" : "Skipped: " ~ $result.skip_reason
          }
        } as $tool_log
      }
    }
  }

  response = $result
}