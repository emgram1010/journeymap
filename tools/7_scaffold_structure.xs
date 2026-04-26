// Applies a complete structural blueprint to a journey map in one call.
// Supports bulk rename, add, and remove operations for both stages and lenses.
// Replaces 6-8 individual mutate_structure calls at session start.
tool scaffold_structure {
  instructions = """
      Use this tool at the START of a build session to reshape the entire map structure in one call.
      Instead of calling mutate_structure 6-8 times for individual renames/adds/removes, collect
      ALL structural changes and apply them here.
    
      Input:
      - journey_map_id: The ID of the journey map
      - stage_operations: JSON array of { action, key?, label, position? }
        - action: 'rename' (requires key + label), 'add' (requires label), 'remove' (requires key)
      - lens_operations: JSON array of { action, key?, label, actor_type? }
        - action: 'rename' (requires key + label), 'add' (requires label), 'remove' (requires key)
        - actor_type (add only, optional): one of customer, internal, engineering, ai_agent, handoff, vendor, financial, metrics. When provided the lens is created with the matching template_key, role_prompt, and cells are pre-scaffolded with actor_fields.
    
      Operations execute in order: removes first, then renames, then adds.
      This ensures stable keys are preserved during renames and new items don't conflict.
    
      Response shape:
      {
        success: boolean,
        stages_renamed: int, stages_added: int, stages_removed: int,
        lenses_renamed: int, lenses_added: int, lenses_removed: int,
        cells_created: int, cells_deleted: int,
        final_stage_count: int, final_lens_count: int,
        errors: [ { action, key?, label?, error } ]
      }
    """

  input {
    // The ID of the journey map to restructure.
    int journey_map_id filters=min:1
  
    // Array of stage operations: [{ action, key?, label, position? }]
    json stage_operations?
  
    // Array of lens operations: [{ action, key?, label }]
    json lens_operations?
  
    // Optional: for tool trace logging (transparency layer).
    int conversation_id?
  
    text turn_id?
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    var $stages_renamed {
      value = 0
    }
  
    var $stages_added {
      value = 0
    }
  
    var $stages_removed {
      value = 0
    }
  
    var $lenses_renamed {
      value = 0
    }
  
    var $lenses_added {
      value = 0
    }
  
    var $lenses_removed {
      value = 0
    }
  
    var $cells_created {
      value = 0
    }
  
    var $cells_deleted {
      value = 0
    }
  
    var $errors {
      value = []
    }
  
    // ── Process stage operations ──
    conditional {
      if ($input.stage_operations != null) {
        // Pass 1: removes
        foreach ($input.stage_operations) {
          each as $op {
            conditional {
              if ($op.action == "remove") {
                db.query journey_stage {
                  where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $op.key
                  return = {type: "single"}
                } as $target_stage
              
                conditional {
                  if ($target_stage != null) {
                    api.call "journey_stage/remove/{journey_stage_id}" verb=DELETE {
                      api_group = "journey-map"
                      input = {journey_stage_id: $target_stage.id}
                    } as $remove_result
                  
                    var.update $stages_removed {
                      value = $stages_removed + 1
                    }
                  
                    var.update $cells_deleted {
                      value = $cells_deleted + $remove_result.deleted_cell_count
                    }
                  }
                
                  else {
                    array.push $errors {
                      value = {
                        action: "remove_stage"
                        key   : $op.key
                        error : "Stage not found"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      
        // Pass 2: renames
        foreach ($input.stage_operations) {
          each as $op {
            conditional {
              if ($op.action == "rename") {
                db.query journey_stage {
                  where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $op.key
                  return = {type: "single"}
                } as $rename_target
              
                conditional {
                  if ($rename_target != null) {
                    api.call "journey_stage/rename/{journey_stage_id}" verb=PATCH {
                      api_group = "journey-map"
                      input = {journey_stage_id: $rename_target.id, label: $op.label}
                    } as $rename_result
                  
                    var.update $stages_renamed {
                      value = $stages_renamed + 1
                    }
                  }
                
                  else {
                    array.push $errors {
                      value = {
                        action: "rename_stage"
                        key   : $op.key
                        label : $op.label
                        error : "Stage not found"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      
        // Pass 3: adds
        foreach ($input.stage_operations) {
          each as $op {
            conditional {
              if ($op.action == "add") {
                api.call "journey_stage/add/{journey_map_id}" verb=POST {
                  api_group = "journey-map"
                  input = {journey_map_id: $input.journey_map_id, label: $op.label}
                } as $add_result
              
                var.update $stages_added {
                  value = $stages_added + 1
                }
              
                var.update $cells_created {
                  value = $cells_created + ($add_result.cells|count)
                }
              }
            }
          }
        }
      }
    }
  
    // ── Process lens operations ──
    conditional {
      if ($input.lens_operations != null) {
        // Pass 1: removes
        foreach ($input.lens_operations) {
          each as $op {
            conditional {
              if ($op.action == "remove") {
                db.query journey_lens {
                  where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $op.key
                  return = {type: "single"}
                } as $target_lens
              
                conditional {
                  if ($target_lens != null) {
                    api.call "journey_lens/remove/{journey_lens_id}" verb=DELETE {
                      api_group = "journey-map"
                      input = {journey_lens_id: $target_lens.id}
                    } as $remove_lens_result
                  
                    var.update $lenses_removed {
                      value = $lenses_removed + 1
                    }
                  
                    var.update $cells_deleted {
                      value = $cells_deleted + $remove_lens_result.deleted_cell_count
                    }
                  }
                
                  else {
                    array.push $errors {
                      value = {
                        action: "remove_lens"
                        key   : $op.key
                        error : "Lens not found"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      
        // Pass 2: renames
        foreach ($input.lens_operations) {
          each as $op {
            conditional {
              if ($op.action == "rename") {
                db.query journey_lens {
                  where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $op.key
                  return = {type: "single"}
                } as $rename_lens_target
              
                conditional {
                  if ($rename_lens_target != null) {
                    api.call "journey_lens/rename/{journey_lens_id}" verb=PATCH {
                      api_group = "journey-map"
                      input = {
                        journey_lens_id: $rename_lens_target.id
                        label          : $op.label
                      }
                    } as $rename_lens_result
                  
                    var.update $lenses_renamed {
                      value = $lenses_renamed + 1
                    }
                  }
                
                  else {
                    array.push $errors {
                      value = {
                        action: "rename_lens"
                        key   : $op.key
                        label : $op.label
                        error : "Lens not found"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      
        // Pass 3: adds
        // Use direct DB ops — internal api.call does not forward the user auth
        // context, so the auth-protected journey_lens/add endpoint would reject it.
        foreach ($input.lens_operations) {
          each as $op {
            conditional {
              if ($op.action == "add") {
                db.query journey_lens {
                  where = $db.journey_lens.journey_map == $input.journey_map_id
                  sort = {display_order: "desc"}
                  return = {type: "list"}
                } as $lenses_before_add
              
                db.query journey_stage {
                  where = $db.journey_stage.journey_map == $input.journey_map_id
                  sort = {display_order: "asc"}
                  return = {type: "list"}
                } as $stages_for_scaffold
              
                var $sc_new_lens_order {
                  value = 1
                }
              
                conditional {
                  if (($lenses_before_add|count) > 0) {
                    var.update $sc_new_lens_order {
                      value = $lenses_before_add
                        |first
                        |get:"display_order"
                        |add:1
                    }
                  }
                }
              
                var $sc_new_lens_key {
                  value = "lens-%d"|sprintf:$sc_new_lens_order
                }
              
                // ── Actor template defaults ──
                var $sc_template_key {
                  value = null
                }
              
                var $sc_role_prompt {
                  value = null
                }
              
                var $sc_actor_fields_scaffold {
                  value = null
                }
              
                conditional {
                  if ($op.actor_type == "customer") {
                    var.update $sc_template_key {
                      value = "customer-v1"
                    }
                  
                    var.update $sc_role_prompt {
                      value = "You are capturing the customer perspective at each stage of this journey. For each stage focus on: Entry Trigger (what brought the customer here), Emotions (how the customer feels), Information Needs (what the customer needs to know), Decisions Required (choices the customer must make), Friction Points (what could cause hesitation or abandonment), Assumptions (what the customer believes that may be wrong), Acceptance Criteria (what success looks like for the customer), Expected Output (what the customer expects after this step), and Channel/Touchpoint (how or where this step happens). Be specific. Use the customer language. Avoid internal jargon."
                    }
                  
                    var.update $sc_actor_fields_scaffold {
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
                  if ($op.actor_type == "internal") {
                    var.update $sc_template_key {
                      value = "internal-v1"
                    }
                  
                    var.update $sc_role_prompt {
                      value = "You are capturing the internal employee perspective at each stage of this journey. For each stage focus on: Task / Objective (what they are responsible for at this step), Entry Point / Trigger (what initiates their involvement), Tools & Systems Used (what platforms or devices they rely on), Information Needs (what data or context they need), Decisions Required (judgment calls they must make), Friction Points (what slows them down or causes errors), Assumptions Being Made (what they believe that may cause issues if wrong), Handoff Dependencies (what they need from a previous step or person), Success Criteria (what completing this step correctly looks like), Output / Deliverable (what they produce or pass forward), Employee Constraints (limitations affecting how they perform), and Pain Points (recurring frustrations or gaps). Be specific. Use operational language. Focus on process gaps and friction."
                    }
                  
                    var.update $sc_actor_fields_scaffold {
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
                  if ($op.actor_type == "engineering") {
                    var.update $sc_template_key {
                      value = "engineering-v1"
                    }
                  
                    var.update $sc_role_prompt {
                      value = "You are capturing the engineering and technical perspective at each stage of this journey. For each stage focus on: System / Service Owner (what system or service is responsible for this step), Data Inputs (what data is required to initiate or complete this step), Data Outputs (what data is produced or updated when this step completes), API / Integration Dependencies (what external or internal services need to be called), Business Rules / Logic (what conditions or rules govern how this step behaves), Error States / Edge Cases (what can go wrong technically and how it should be handled), Data Storage Requirements (what needs to be saved, where, and for how long), Security & Permissions (who or what system is allowed to access or modify this step), Performance Requirements (how fast or reliable this step needs to be), and Audit / Logging Needs (what events need to be tracked for compliance or debugging). Be precise. Use technical language. Reference system names, SLAs, and data contracts where relevant."
                    }
                  
                    var.update $sc_actor_fields_scaffold {
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
                  if ($op.actor_type == "ai_agent") {
                    var.update $sc_template_key {
                      value = "ai-agent-v1"
                    }
                  
                    var.update $sc_role_prompt {
                      value = "You are capturing the AI model or automated agent perspective at each stage of this journey. For each stage focus on: AI Model / Agent (what specific AI model or agent is responsible), Input Data (what data the AI consumes), Decision / Output (what the AI decides or generates), Confidence Threshold (what certainty level is needed before acting independently), Escalation Logic (when and to whom the AI hands off to a human), Training Data (what historical data was used to train this model), Retraining Frequency (how often the model gets updated), Bias & Fairness Considerations (what potential biases could be introduced), Failure Scenarios (what can go wrong and what the fallback is), Performance Metrics (how effectiveness is measured), Model Owner (who is responsible for maintaining this AI), and Explainability Needs (whether users need to understand why the AI made this decision). Be precise. Reference model names, confidence scores, and SLAs where relevant."
                    }
                  
                    var.update $sc_actor_fields_scaffold {
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
                  if ($op.actor_type == "handoff") {
                    var.update $sc_template_key {
                      value = "handoff-v1"
                    }
                  
                    var.update $sc_role_prompt {
                      value = "You are capturing the system handoff and dependency perspective at each stage of this journey. For each stage focus on: Trigger Event (what initiates this step), Upstream Actor (who initiates this handoff), Prerequisite Data (what data must be present), Upstream Dependencies (what must be completed before this step), Handoff Output (what is passed forward), Handoff Format (how information is transferred), Handoff Timing (when the handoff occurs), Downstream Actor (who receives the handoff), Validation Rules (what conditions define a successful handoff), Failure Recovery (what happens if the handoff fails), Communication Method (how the downstream actor is notified), and Data Retention Policy (how long handoff data is stored and where). Focus on the connective tissue between steps and identify gaps in the handoff chain."
                    }
                  
                    var.update $sc_actor_fields_scaffold {
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
                  if ($op.actor_type == "vendor") {
                    var.update $sc_template_key {
                      value = "vendor-v1"
                    }
                  
                    var.update $sc_role_prompt {
                      value = "You are capturing the third-party vendor perspective at each stage of this journey. For each stage focus on: Vendor Name / Type (who this third party is and what category they fall under), Role at This Step (what specific function this vendor performs), Engagement Trigger (what event activates this vendor), Contractual Obligations (agreed service levels this vendor must meet), Information Needs (what data must be shared with this vendor), Information They Return (data or confirmation the vendor sends back), Integration Method (how this vendor connects to your system), SLA / Performance Metrics (how this vendor's performance is measured), Failure Scenario (what happens if this vendor fails to perform), Escalation Path (who owns the relationship and resolves issues), Data Privacy & Compliance (data governance rules for what is shared with this vendor), Vendor Constraints (limitations the vendor operates under), Cost Impact (financial implication of this vendor's involvement), and Dependency on Internal Actors (what internal teams must complete before this vendor can begin). Be specific. Reference vendor names, SLA thresholds, and integration types where relevant."
                    }
                  
                    var.update $sc_actor_fields_scaffold {
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
                  if ($op.actor_type == "financial") {
                    var.update $sc_template_key {
                      value = "financial-v1"
                    }
                  
                    var.update $sc_role_prompt {
                      value = "You are capturing the financial intelligence perspective at each stage of this journey. For each stage focus on: Cost to Serve (estimated cost per interaction, transaction, or touchpoint at this stage), Revenue at Risk (revenue lost or threatened if this stage has friction or fails), Automation Savings (cost savings achievable if manual steps at this stage are automated), Upsell / Cross-sell Opportunity (revenue opportunity from upsell or cross-sell actions available at this stage), Revenue Leakage (value lost due to drop-off, abandonment, errors, or rework at this stage), Cost Efficiency Note (key observation about cost drivers, waste, or inefficiency at this stage), Breakeven Threshold (minimum improvement required to justify the cost of fixing this stage), CAC Contribution (how this stage contributes to or inflates customer acquisition cost), CLV Impact (how this stage positively or negatively affects long-term customer lifetime value), and Financial Priority Score (relative investment priority based on combined cost and revenue impact). Be specific. Use dollar figures, percentages, and time horizons where possible. Reference upstream friction from other lenses as the root cause of financial impact."
                    }
                  
                    var.update $sc_actor_fields_scaffold {
                      value = {}
                        |set:"cost_to_serve":null
                        |set:"revenue_at_risk":null
                        |set:"automation_savings":null
                        |set:"upsell_opportunity":null
                        |set:"revenue_leakage":null
                        |set:"cost_efficiency_note":null
                        |set:"breakeven_threshold":null
                        |set:"cac_contribution":null
                        |set:"clv_impact":null
                        |set:"priority_score":null
                    }
                  }
                }
              
                conditional {
                  if ($op.actor_type == "metrics") {
                    var.update $sc_template_key {
                      value = "metrics-v1"
                    }
                  
                    var.update $sc_role_prompt {
                      value = "You are capturing operational metrics at each stage of this journey. For each stage focus on: CSAT Score (customer satisfaction score 1-10 at this stage), Completion Rate (% of users who successfully complete this stage), Drop-off Rate (% who abandon or fail at this stage), Avg Time to Complete (average duration of this stage in minutes or hours), Error Rate (% of interactions at this stage that result in an error or failure), SLA Compliance Rate (% of interactions that meet defined SLA targets), Volume / Frequency (number of interactions or transactions at this stage per period), and Stage Health Score (composite 1-10 health score derived from all other metrics — weight CSAT and completion rate most heavily). Be specific. Use percentages, counts, and time units. Infer from qualitative actor content when direct data is unavailable."
                    }
                  
                    var.update $sc_actor_fields_scaffold {
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
              
                db.add journey_lens {
                  data = {
                    created_at   : "now"
                    updated_at   : "now"
                    journey_map  : $input.journey_map_id
                    key          : $sc_new_lens_key
                    label        : $op.label
                    display_order: $sc_new_lens_order
                    actor_type   : $op.actor_type
                    template_key : $sc_template_key
                    role_prompt  : $sc_role_prompt
                  }
                } as $sc_added_lens
              
                var $sc_cells_for_lens {
                  value = 0
                }
              
                foreach ($stages_for_scaffold) {
                  each as $sc_stg {
                    db.add journey_cell {
                      data = {
                        created_at  : "now"
                        updated_at  : "now"
                        journey_map : $input.journey_map_id
                        stage       : $sc_stg.id
                        lens        : $sc_added_lens.id
                        content     : ""
                        status      : "open"
                        is_locked   : false
                        actor_fields: $sc_actor_fields_scaffold
                      }
                    } as $sc_new_cell
                  
                    var.update $sc_cells_for_lens {
                      value = $sc_cells_for_lens + 1
                    }
                  }
                }
              
                var.update $lenses_added {
                  value = $lenses_added + 1
                }
              
                var.update $cells_created {
                  value = $cells_created + $sc_cells_for_lens
                }
              }
            }
          }
        }
      }
    }
  
    // ── Final counts ──
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $final_stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $final_lenses
  
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $map_touch
  
    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "scaffold_structure"
            tool_category : "structure"
            input_summary : $stages_renamed ~ " renamed, " ~ $stages_added ~ " added, " ~ $stages_removed ~ " removed stages"
            output_summary: ($final_stages|count) ~ " stages, " ~ ($final_lenses|count) ~ " lenses final"
          }
        } as $tool_log
      }
    }
  }

  response = {
    success          : true
    stages_renamed   : $stages_renamed
    stages_added     : $stages_added
    stages_removed   : $stages_removed
    lenses_renamed   : $lenses_renamed
    lenses_added     : $lenses_added
    lenses_removed   : $lenses_removed
    cells_created    : $cells_created
    cells_deleted    : $cells_deleted
    final_stage_count: $final_stages|count
    final_lens_count : $final_lenses|count
    stages           : $final_stages
    lenses           : $final_lenses
    errors           : $errors
  }
}