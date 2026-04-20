// Add a journey stage and scaffold matching cells for all lenses in the map.
query "journey_stage/add/{journey_map_id}" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text label? filters=trim
  }

  stack {
    var $cells {
      value = []
    }
  
    var $next_stage_order {
      value = 1
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "desc"}
      return = {type: "list"}
    } as $existing_stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $existing_lenses
  
    precondition (($existing_lenses|count) > 0) {
      error_type = "inputerror"
      error = "Journey map must include at least one lens before adding a stage"
    }
  
    conditional {
      if (($existing_stages|count) > 0) {
        var.update $next_stage_order {
          value = $existing_stages
            |first
            |get:"display_order"
            |add:1
        }
      }
    }
  
    var $stage_label {
      value = "Stage %d"|sprintf:$next_stage_order
    }
  
    conditional {
      if ($input.label != null) {
        precondition ($input.label != "") {
          error_type = "inputerror"
          error = "Stage label is required"
        }
      
        var.update $stage_label {
          value = $input.label
        }
      }
    }
  
    var $stage_key {
      value = "s%d"|sprintf:$next_stage_order
    }
  
    db.add journey_stage {
      data = {
        created_at   : "now"
        updated_at   : "now"
        journey_map  : $input.journey_map_id
        key          : $stage_key
        label        : $stage_label
        display_order: $next_stage_order
      }
    } as $journey_stage
  
    foreach ($existing_lenses) {
      each as $lens {
        // Derive actor_fields scaffold from the lens's template_key
        var $cell_actor_fields_scaffold {
          value = null
        }
      
        conditional {
          if ($lens.template_key == "customer-v1") {
            var.update $cell_actor_fields_scaffold {
              value = {}
                |set:"entry_trigger":null
                |set:"emotions":null
                |set:"information_needs":null
                |set:"decisions_required":null
                |set:"friction_points":null
                |set:"assumptions":null
                |set:"acceptance_criteria":null
                |set:"expected_output":null
                |set:"channel_touchpoint":null
            }
          }
        }
      
        conditional {
          if ($lens.template_key == "internal-v1") {
            var.update $cell_actor_fields_scaffold {
              value = {}
                |set:"task_objective":null
                |set:"entry_trigger":null
                |set:"tools_systems":null
                |set:"information_needs":null
                |set:"decisions_required":null
                |set:"friction_points":null
                |set:"assumptions":null
                |set:"handoff_dependencies":null
                |set:"success_criteria":null
                |set:"output_deliverable":null
                |set:"employee_constraints":null
                |set:"pain_points":null
            }
          }
        }
      
        conditional {
          if ($lens.template_key == "engineering-v1") {
            var.update $cell_actor_fields_scaffold {
              value = {}
                |set:"system_service_owner":null
                |set:"data_inputs":null
                |set:"data_outputs":null
                |set:"api_integration_dependencies":null
                |set:"business_rules_logic":null
                |set:"error_states_edge_cases":null
                |set:"data_storage_requirements":null
                |set:"security_permissions":null
                |set:"performance_requirements":null
                |set:"audit_logging_needs":null
            }
          }
        }
      
        conditional {
          if ($lens.template_key == "ai-agent-v1") {
            var.update $cell_actor_fields_scaffold {
              value = {}
                |set:"ai_model_agent":null
                |set:"input_data":null
                |set:"decision_output":null
                |set:"confidence_threshold":null
                |set:"escalation_logic":null
                |set:"training_data":null
                |set:"retraining_frequency":null
                |set:"bias_fairness_considerations":null
                |set:"failure_scenarios":null
                |set:"performance_metrics":null
                |set:"model_owner":null
                |set:"explainability_needs":null
            }
          }
        }
      
        conditional {
          if ($lens.template_key == "handoff-v1") {
            var.update $cell_actor_fields_scaffold {
              value = {}
                |set:"trigger_event":null
                |set:"upstream_actor":null
                |set:"prerequisite_data":null
                |set:"upstream_dependencies":null
                |set:"handoff_output":null
                |set:"handoff_format":null
                |set:"handoff_timing":null
                |set:"downstream_actor":null
                |set:"validation_rules":null
                |set:"failure_recovery":null
                |set:"communication_method":null
                |set:"data_retention_policy":null
            }
          }
        }
      
        conditional {
          if ($lens.template_key == "vendor-v1") {
            var.update $cell_actor_fields_scaffold {
              value = {}
                |set:"vendor_name_type":null
                |set:"role_at_step":null
                |set:"engagement_trigger":null
                |set:"contractual_obligations":null
                |set:"information_needs":null
                |set:"information_returned":null
                |set:"integration_method":null
                |set:"sla_performance_metrics":null
                |set:"failure_scenario":null
                |set:"escalation_path":null
                |set:"data_privacy_compliance":null
                |set:"vendor_constraints":null
                |set:"cost_impact":null
                |set:"dependency_on_internal":null
            }
          }
        }
      
        conditional {
          if ($lens.template_key == "metrics-v1") {
            var.update $cell_actor_fields_scaffold {
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
      
        db.add journey_cell {
          data = {
            created_at  : "now"
            updated_at  : "now"
            journey_map : $input.journey_map_id
            stage       : $journey_stage.id
            lens        : $lens.id
            content     : ""
            status      : "open"
            is_locked   : false
            actor_fields: $cell_actor_fields_scaffold
          }
        } as $cell
      
        array.push $cells {
          value = $cell
        }
      }
    }
  
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch_patch
  
    precondition ($journey_map_touch_patch != null) {
      error = "Failed to update journey map"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map_touch
  }

  response = {
    stage                 : $journey_stage
    cells                 : $cells
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}