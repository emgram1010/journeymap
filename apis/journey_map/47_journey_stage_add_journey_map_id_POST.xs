// Add a journey stage and scaffold matching cells for all lenses in the map.
//
// ORD-1 (US-ORD-1-01): the key and display_order come from
// journey/next_stage_key, the one place a stage key is minted. They used to
// be computed here as "s" + (max display_order + 1), which ties a key to a
// position and collides once anything renumbers display_order.
//
// ORD-1 (US-ORD-1-04): optional `after_stage_id` inserts the new column at
// a position instead of the end (0 = first). Omit it and the call behaves
// exactly as before.
query "journey_stage/add/{journey_map_id}" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text label? filters=trim
    text stage_goal? filters=trim
    text primary_actor_lens? filters=trim

    // ORD-1: insert after this stage id; 0 = insert first; omit = append.
    int after_stage_id?
  }

  stack {
    var $cells {
      value = []
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
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $existing_lenses
  
    precondition (($existing_lenses|count) > 0) {
      error_type = "inputerror"
      error = "Journey map must include at least one lens before adding a stage"
    }
  
    // ORD-1 (US-ORD-1-04) — optional insert position.
    // after_stage_id omitted -> append (exactly the old behaviour);
    // 0 -> insert first; a stage id -> insert directly after that stage.
    // An omitted optional int arrives as 0, which is ALSO the legitimate
    // "insert first" value, so presence is read from the raw body, not
    // from $input (CLAUDE.md). This is a POST, so there is a body to read.
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $after_stage_id {
      value = -1
    }

    conditional {
      if ($raw_input|has:"after_stage_id") {
        var.update $after_stage_id {
          value = ($raw_input|get:"after_stage_id":0)|to_int
        }
      }
    }

    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.id == $after_stage_id
      return = {type: "count"}
    } as $anchor_found

    var $anchor_bad {
      value = ($after_stage_id > 0) && ($anchor_found == 0)
    }

    conditional {
      if ($anchor_bad) {
        function.run "ops/log_event" {
          input = {
            feature    : "ORD-1"
            step       : "insert_stage"
            outcome    : "rejected"
            severity   : "info"
            user_id    : $auth.id
            account_id : $journey_map.account_id
            entity_type: "journey_map"
            entity_id  : $input.journey_map_id
            error_code : "E-ORD-002"
            message    : "Insert refused: the stage to insert after is not in this map."
          }
        } as $_anchor_logged
      }
    }

    precondition ($anchor_bad == false) {
      error_type = "inputerror"
      error = "The column you tried to insert next to isn't in this map any more, so nothing was added. Refresh and try again. (E-ORD-002)"
    }

    function.run "journey/next_stage_key" {
      input = {journey_map_id: $input.journey_map_id}
    } as $mint
  
    var $next_stage_order {
      value = $mint.display_order
    }
  
    var $stage_label {
      value = "Stage %d"|sprintf:$next_stage_order
    }

    // An inserted column would otherwise be called "Stage <append position>",
    // which is a lie the moment it is placed somewhere else.
    conditional {
      if ($after_stage_id >= 0) {
        var.update $stage_label {
          value = "New stage"
        }
      }
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
      value = $mint.key
    }
  
    db.add journey_stage {
      enforce_hidden_fields = false
      data = {
        created_at        : "now"
        updated_at        : "now"
        journey_map       : $input.journey_map_id
        key               : $stage_key
        label             : $stage_label
        display_order     : $next_stage_order
        stage_goal        : $input.stage_goal
        primary_actor_lens: $input.primary_actor_lens
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
          enforce_hidden_fields = false
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
  
    // ORD-1 (US-ORD-1-04) — place the new stage. It was appended above (key
    // and order from the shared mint); now splice it in after the anchor and
    // let journey/apply_stage_order — the one place stage order is
    // written — renumber the map 1..n. Every condition in the loop reads only
    // the loop item or values set before the loop (CLAUDE.md).
    conditional {
      if ($after_stage_id >= 0) {
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id
          sort = {display_order: "asc", id: "asc"}
          return = {type: "list"}
        } as $ordered_rows

        var $placed_ids {
          value = []
        }

        conditional {
          if ($after_stage_id == 0) {
            array.push $placed_ids {
              value = $journey_stage.id
            }
          }
        }

        foreach ($ordered_rows) {
          each as $or {
            conditional {
              if ($or.id != $journey_stage.id) {
                array.push $placed_ids {
                  value = $or.id
                }

                conditional {
                  if ($or.id == $after_stage_id) {
                    array.push $placed_ids {
                      value = $journey_stage.id
                    }
                  }
                }
              }
            }
          }
        }

        function.run "journey/apply_stage_order" {
          input = {
            journey_map_id: $input.journey_map_id
            stage_ids     : $placed_ids
            user_id       : $auth.id
            account_id    : $journey_map.account_id
            step          : "insert_stage"
          }
        } as $placed
      }
    }

    db.get journey_stage {
      field_name = "id"
      field_value = $journey_stage.id
    } as $placed_row

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
    stage                 : $placed_row
    cells                 : $cells
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}