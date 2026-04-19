// Adds, removes, or renames stages and lenses in a journey map.
// Delegates to the existing journey-map API endpoints for scaffolding and cleanup.
// Adds, removes, or renames stages and lenses in a journey map.
tool mutate_structure {
  instructions = """
      Use this tool to reshape the journey map structure when the user describes a workflow
      that doesn't fit the current template.
    
      Supported actions:
      - add_stage: Adds a new stage (column) and scaffolds cells for all existing lenses.
      - remove_stage: Removes a stage and cascades cell deletion. Must keep at least 1 stage.
      - rename_stage: Updates only the display label of a stage. The key remains stable.
      - add_lens: Adds a new lens (row) and scaffolds cells for all existing stages.
      - remove_lens: Removes a lens and cascades cell deletion. Must keep at least 1 lens.
      - rename_lens: Updates only the display label of a lens. The key remains stable.
      - reorder_stages: Reorders stages by providing all stage keys in the desired order. No cell content is lost.
      - reorder_lenses: Reorders lenses by providing all lens keys in the desired order. No cell content is lost.
    
      Input:
      - journey_map_id: The ID of the journey map
      - action: One of add_stage, remove_stage, rename_stage, add_lens, remove_lens, rename_lens, reorder_stages, reorder_lenses
      - label: Required for add_* and rename_* actions. The display label.
      - target_key: Required for remove_* and rename_* actions. The key of the stage/lens to target.
      - keys_in_order: Required for reorder_* actions. JSON array of all keys in the desired display order.
      - actor_type (add_lens only, optional): one of customer, internal, engineering, ai_agent, handoff, vendor. When provided the lens is created with the matching template_key, role_prompt, and cells are pre-scaffolded with actor_fields.
    
      Response shape:
      {
        action: string,
        success: boolean,
        result: { ... action-specific result ... },
        error: null | string
      }
    """

  input {
    // The ID of the journey map to modify.
    int journey_map_id filters=min:1
  
    // Optional: for tool trace logging (transparency layer).
    int conversation_id?
  
    text turn_id?
  
    // The structural action: add_stage, remove_stage, rename_stage, add_lens, remove_lens, rename_lens, reorder_stages, reorder_lenses.
    text action filters=trim
  
    // The display label for add or rename actions.
    text label? filters=trim
  
    // The key of the stage or lens to remove or rename.
    text target_key? filters=trim
  
    // Ordered array of keys for reorder_stages / reorder_lenses.
    json keys_in_order?
  
    // Actor type for add_lens action (optional): customer, internal, engineering, ai_agent, handoff, vendor.
    text actor_type? filters=trim
  }

  stack {
    var $result {
      value = {
        action : $input.action
        success: false
        result : null
        error  : null
      }
    }
  
    conditional {
      if ($input.action == "add_stage") {
        precondition ($input.label != null && $input.label != "") {
          error_type = "inputerror"
          error = "label is required for add_stage"
        }
      
        api.call "journey_stage/add/{journey_map_id}" verb=POST {
          api_group = "journey-map"
          input = {
            journey_map_id: $input.journey_map_id
            label         : $input.label
          }
        } as $add_stage_result
      
        var.update $result {
          value = {
            action : "add_stage"
            success: true
            result : $add_stage_result
            error  : null
          }
        }
      }
    
      elseif ($input.action == "remove_stage") {
        precondition ($input.target_key != null && $input.target_key != "") {
          error_type = "inputerror"
          error = "target_key is required for remove_stage"
        }
      
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.target_key
          return = {type: "single"}
        } as $target_stage
      
        precondition ($target_stage != null) {
          error_type = "notfound"
          error = "Stage not found with key: " + $input.target_key
        }
      
        api.call "journey_stage/remove/{journey_stage_id}" verb=DELETE {
          api_group = "journey-map"
          input = {journey_stage_id: $target_stage.id}
        } as $remove_stage_result
      
        var.update $result {
          value = {
            action : "remove_stage"
            success: true
            result : $remove_stage_result
            error  : null
          }
        }
      }
    
      elseif ($input.action == "rename_stage") {
        precondition ($input.target_key != null && $input.target_key != "") {
          error_type = "inputerror"
          error = "target_key is required for rename_stage"
        }
      
        precondition ($input.label != null && $input.label != "") {
          error_type = "inputerror"
          error = "label is required for rename_stage"
        }
      
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.target_key
          return = {type: "single"}
        } as $rename_stage_target
      
        precondition ($rename_stage_target != null) {
          error_type = "notfound"
          error = "Stage not found with key: " + $input.target_key
        }
      
        api.call "journey_stage/rename/{journey_stage_id}" verb=PATCH {
          api_group = "journey-map"
          input = {
            journey_stage_id: $rename_stage_target.id
            label           : $input.label
          }
        } as $rename_stage_result
      
        var.update $result {
          value = {
            action : "rename_stage"
            success: true
            result : $rename_stage_result
            error  : null
          }
        }
      }
    
      elseif ($input.action == "add_lens") {
        precondition ($input.label != null && $input.label != "") {
          error_type = "inputerror"
          error = "label is required for add_lens"
        }
      
        // Use direct DB ops — internal api.call does not forward the user auth
        // context, so the auth-protected journey_lens/add endpoint would reject it.
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id
          sort = {display_order: "desc"}
          return = {type: "list"}
        } as $lenses_for_order
      
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id
          sort = {display_order: "asc"}
          return = {type: "list"}
        } as $stages_for_cells
      
        var $new_lens_order {
          value = 1
        }
      
        conditional {
          if (($lenses_for_order|count) > 0) {
            var.update $new_lens_order {
              value = $lenses_for_order
                |first
                |get:"display_order"
                |add:1
            }
          }
        }
      
        var $new_lens_key {
          value = "lens-%d"|sprintf:$new_lens_order
        }
      
        // ── Actor template defaults ──
        var $ms_template_key {
          value = null
        }
      
        var $ms_role_prompt {
          value = null
        }
      
        var $ms_actor_fields_scaffold {
          value = null
        }
      
        conditional {
          if ($input.actor_type == "customer") {
            var.update $ms_template_key {
              value = "customer-v1"
            }
          
            var.update $ms_role_prompt {
              value = "You are capturing the customer perspective at each stage of this journey. For each stage focus on: Entry Trigger (what brought the customer here), Emotions (how the customer feels), Information Needs (what the customer needs to know), Decisions Required (choices the customer must make), Friction Points (what could cause hesitation or abandonment), Assumptions (what the customer believes that may be wrong), Acceptance Criteria (what success looks like for the customer), Expected Output (what the customer expects after this step), and Channel/Touchpoint (how or where this step happens). Be specific. Use the customer language. Avoid internal jargon."
            }
          
            var.update $ms_actor_fields_scaffold {
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
          if ($input.actor_type == "internal") {
            var.update $ms_template_key {
              value = "internal-v1"
            }
          
            var.update $ms_role_prompt {
              value = "You are capturing the internal employee perspective at each stage of this journey. For each stage focus on: Task / Objective (what they are responsible for at this step), Entry Point / Trigger (what initiates their involvement), Tools & Systems Used (what platforms or devices they rely on), Information Needs (what data or context they need), Decisions Required (judgment calls they must make), Friction Points (what slows them down or causes errors), Assumptions Being Made (what they believe that may cause issues if wrong), Handoff Dependencies (what they need from a previous step or person), Success Criteria (what completing this step correctly looks like), Output / Deliverable (what they produce or pass forward), Employee Constraints (limitations affecting how they perform), and Pain Points (recurring frustrations or gaps). Be specific. Use operational language. Focus on process gaps and friction."
            }
          
            var.update $ms_actor_fields_scaffold {
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
          if ($input.actor_type == "engineering") {
            var.update $ms_template_key {
              value = "engineering-v1"
            }
          
            var.update $ms_role_prompt {
              value = "You are capturing the engineering and technical perspective at each stage of this journey. For each stage focus on: System / Service Owner (what system or service is responsible for this step), Data Inputs (what data is required to initiate or complete this step), Data Outputs (what data is produced or updated when this step completes), API / Integration Dependencies (what external or internal services need to be called), Business Rules / Logic (what conditions or rules govern how this step behaves), Error States / Edge Cases (what can go wrong technically and how it should be handled), Data Storage Requirements (what needs to be saved, where, and for how long), Security & Permissions (who or what system is allowed to access or modify this step), Performance Requirements (how fast or reliable this step needs to be), and Audit / Logging Needs (what events need to be tracked for compliance or debugging). Be precise. Use technical language. Reference system names, SLAs, and data contracts where relevant."
            }
          
            var.update $ms_actor_fields_scaffold {
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
          if ($input.actor_type == "ai_agent") {
            var.update $ms_template_key {
              value = "ai-agent-v1"
            }
          
            var.update $ms_role_prompt {
              value = "You are capturing the AI model or automated agent perspective at each stage of this journey. For each stage focus on: AI Model / Agent (what specific AI model or agent is responsible), Input Data (what data the AI consumes), Decision / Output (what the AI decides or generates), Confidence Threshold (what certainty level is needed before acting independently), Escalation Logic (when and to whom the AI hands off to a human), Training Data (what historical data was used to train this model), Retraining Frequency (how often the model gets updated), Bias & Fairness Considerations (what potential biases could be introduced), Failure Scenarios (what can go wrong and what the fallback is), Performance Metrics (how effectiveness is measured), Model Owner (who is responsible for maintaining this AI), and Explainability Needs (whether users need to understand why the AI made this decision). Be precise. Reference model names, confidence scores, and SLAs where relevant."
            }
          
            var.update $ms_actor_fields_scaffold {
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
          if ($input.actor_type == "handoff") {
            var.update $ms_template_key {
              value = "handoff-v1"
            }
          
            var.update $ms_role_prompt {
              value = "You are capturing the system handoff and dependency perspective at each stage of this journey. For each stage focus on: Trigger Event (what initiates this step), Upstream Actor (who initiates this handoff), Prerequisite Data (what data must be present), Upstream Dependencies (what must be completed before this step), Handoff Output (what is passed forward), Handoff Format (how information is transferred), Handoff Timing (when the handoff occurs), Downstream Actor (who receives the handoff), Validation Rules (what conditions define a successful handoff), Failure Recovery (what happens if the handoff fails), Communication Method (how the downstream actor is notified), and Data Retention Policy (how long handoff data is stored and where). Focus on the connective tissue between steps and identify gaps in the handoff chain."
            }
          
            var.update $ms_actor_fields_scaffold {
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
          if ($input.actor_type == "vendor") {
            var.update $ms_template_key {
              value = "vendor-v1"
            }
          
            var.update $ms_role_prompt {
              value = "You are capturing the third-party vendor perspective at each stage of this journey. For each stage focus on: Vendor Name / Type (who this third party is and what category they fall under), Role at This Step (what specific function this vendor performs), Engagement Trigger (what event activates this vendor), Contractual Obligations (agreed service levels this vendor must meet), Information Needs (what data must be shared with this vendor), Information They Return (data or confirmation the vendor sends back), Integration Method (how this vendor connects to your system), SLA / Performance Metrics (how this vendor's performance is measured), Failure Scenario (what happens if this vendor fails to perform), Escalation Path (who owns the relationship and resolves issues), Data Privacy & Compliance (data governance rules for what is shared with this vendor), Vendor Constraints (limitations the vendor operates under), Cost Impact (financial implication of this vendor's involvement), and Dependency on Internal Actors (what internal teams must complete before this vendor can begin). Be specific. Reference vendor names, SLA thresholds, and integration types where relevant."
            }
          
            var.update $ms_actor_fields_scaffold {
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
      
        db.add journey_lens {
          data = {
            created_at   : "now"
            updated_at   : "now"
            journey_map  : $input.journey_map_id
            key          : $new_lens_key
            label        : $input.label
            display_order: $new_lens_order
            actor_type   : $input.actor_type
            template_key : $ms_template_key
            role_prompt  : $ms_role_prompt
          }
        } as $added_lens
      
        var $added_lens_cells {
          value = []
        }
      
        foreach ($stages_for_cells) {
          each as $stg {
            db.add journey_cell {
              data = {
                created_at  : "now"
                updated_at  : "now"
                journey_map : $input.journey_map_id
                stage       : $stg.id
                lens        : $added_lens.id
                content     : ""
                status      : "open"
                is_locked   : false
                actor_fields: $ms_actor_fields_scaffold
              }
            } as $scaffolded_cell
          
            array.push $added_lens_cells {
              value = $scaffolded_cell
            }
          }
        }
      
        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = {updated_at: "now", last_interaction_at: "now"}
        } as $map_touch_add_lens
      
        var.update $result {
          value = {
            action : "add_lens"
            success: true
            result : {lens: $added_lens, cells: $added_lens_cells}
            error  : null
          }
        }
      }
    
      elseif ($input.action == "remove_lens") {
        precondition ($input.target_key != null && $input.target_key != "") {
          error_type = "inputerror"
          error = "target_key is required for remove_lens"
        }
      
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.target_key
          return = {type: "single"}
        } as $target_lens
      
        precondition ($target_lens != null) {
          error_type = "notfound"
          error = "Lens not found with key: " + $input.target_key
        }
      
        api.call "journey_lens/remove/{journey_lens_id}" verb=DELETE {
          api_group = "journey-map"
          input = {journey_lens_id: $target_lens.id}
        } as $remove_lens_result
      
        var.update $result {
          value = {
            action : "remove_lens"
            success: true
            result : $remove_lens_result
            error  : null
          }
        }
      }
    
      elseif ($input.action == "rename_lens") {
        precondition ($input.target_key != null && $input.target_key != "") {
          error_type = "inputerror"
          error = "target_key is required for rename_lens"
        }
      
        precondition ($input.label != null && $input.label != "") {
          error_type = "inputerror"
          error = "label is required for rename_lens"
        }
      
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.target_key
          return = {type: "single"}
        } as $rename_lens_target
      
        precondition ($rename_lens_target != null) {
          error_type = "notfound"
          error = "Lens not found with key: " + $input.target_key
        }
      
        api.call "journey_lens/rename/{journey_lens_id}" verb=PATCH {
          api_group = "journey-map"
          input = {
            journey_lens_id: $rename_lens_target.id
            label          : $input.label
          }
        } as $rename_lens_result
      
        var.update $result {
          value = {
            action : "rename_lens"
            success: true
            result : $rename_lens_result
            error  : null
          }
        }
      }
    
      elseif ($input.action == "reorder_stages") {
        precondition ($input.keys_in_order != null) {
          error_type = "inputerror"
          error = "keys_in_order is required for reorder_stages"
        }
      
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id
          return = {type: "list"}
        } as $reorder_stages
      
        var $reorder_items {
          value = []
        }
      
        var $order_counter {
          value = 1
        }
      
        foreach ($input.keys_in_order) {
          each as $key {
            // Find the stage with this key
            var $found {
              value = null
            }
          
            foreach ($reorder_stages) {
              each as $rs {
                conditional {
                  if ($rs.key == $key) {
                    var.update $found {
                      value = $rs
                    }
                  }
                }
              }
            }
          
            conditional {
              if ($found != null) {
                db.patch journey_stage {
                  field_name = "id"
                  field_value = $found.id
                  data = {display_order: $order_counter, updated_at: "now"}
                } as $reordered_stage
              
                array.push $reorder_items {
                  value = {
                    key      : $found.key
                    label    : $found.label
                    old_order: $found.display_order
                    new_order: $order_counter
                  }
                }
              
                var.update $order_counter {
                  value = $order_counter + 1
                }
              }
            }
          }
        }
      
        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = {updated_at: "now", last_interaction_at: "now"}
        } as $reorder_map_touch
      
        var.update $result {
          value = {
            action : "reorder_stages"
            success: true
            result : {items: $reorder_items}
            error  : null
          }
        }
      }
    
      elseif ($input.action == "reorder_lenses") {
        precondition ($input.keys_in_order != null) {
          error_type = "inputerror"
          error = "keys_in_order is required for reorder_lenses"
        }
      
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id
          return = {type: "list"}
        } as $reorder_lenses
      
        var $reorder_lens_items {
          value = []
        }
      
        var $lens_order_counter {
          value = 1
        }
      
        foreach ($input.keys_in_order) {
          each as $key {
            var $found_lens {
              value = null
            }
          
            foreach ($reorder_lenses) {
              each as $rl {
                conditional {
                  if ($rl.key == $key) {
                    var.update $found_lens {
                      value = $rl
                    }
                  }
                }
              }
            }
          
            conditional {
              if ($found_lens != null) {
                db.patch journey_lens {
                  field_name = "id"
                  field_value = $found_lens.id
                  data = {display_order: $lens_order_counter, updated_at: "now"}
                } as $reordered_lens
              
                array.push $reorder_lens_items {
                  value = {
                    key      : $found_lens.key
                    label    : $found_lens.label
                    old_order: $found_lens.display_order
                    new_order: $lens_order_counter
                  }
                }
              
                var.update $lens_order_counter {
                  value = $lens_order_counter + 1
                }
              }
            }
          }
        }
      
        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = {updated_at: "now", last_interaction_at: "now"}
        } as $reorder_lens_map_touch
      
        var.update $result {
          value = {
            action : "reorder_lenses"
            success: true
            result : {items: $reorder_lens_items}
            error  : null
          }
        }
      }
    
      else {
        var.update $result {
          value = {
            action : $input.action
            success: false
            result : null
            error  : "Unknown action. Use: add_stage, remove_stage, rename_stage, add_lens, remove_lens, rename_lens, reorder_stages, reorder_lenses"
          }
        }
      }
    }
  
    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        var $ms_input_summary {
          value = $input.action
        }
      
        conditional {
          if ($input.label != null) {
            var.update $ms_input_summary {
              value = $ms_input_summary ~ ": " ~ $input.label
            }
          }
        }
      
        conditional {
          if ($input.target_key != null) {
            var.update $ms_input_summary {
              value = $ms_input_summary ~ " (key: " ~ $input.target_key ~ ")"
            }
          }
        }
      
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "mutate_structure"
            tool_category : "structure"
            input_summary : $ms_input_summary
            output_summary: $result.success ? "Success" : "Failed: " ~ $result.error
          }
        } as $tool_log
      }
    }
  }

  response = $result
}