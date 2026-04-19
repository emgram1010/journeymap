// Add a journey lens and scaffold matching cells for all stages in the map.
// v7: added financial 10-field scaffold block
query "journey_lens/add/{journey_map_id}" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text label? filters=trim
  
    // Actor identity fields
    enum actor_type? {
      values = [
        "customer"
        "internal"
        "engineering"
        "handoff"
        "vendor"
        "financial"
        "operations"
        "ai_agent"
        "dev"
        "custom"
        "metrics"
      ]
    
    }
  
    text template_key? filters=trim
    text role_prompt? filters=trim
    text persona_description? filters=trim
    text primary_goal? filters=trim
    text standing_constraints? filters=trim
  }

  stack {
    var $cells {
      value = []
    }
  
    var $next_lens_order {
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
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "desc"}
      return = {type: "list"}
    } as $existing_lenses
  
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $existing_stages
  
    precondition (($existing_stages|count) > 0) {
      error_type = "inputerror"
      error = "Journey map must include at least one stage before adding a lens"
    }
  
    conditional {
      if (($existing_lenses|count) > 0) {
        var.update $next_lens_order {
          value = $existing_lenses
            |first
            |get:"display_order"
            |add:1
        }
      }
    }
  
    var $lens_label {
      value = "New Lens %d"|sprintf:$next_lens_order
    }
  
    conditional {
      if ($input.label != null) {
        precondition ($input.label != "") {
          error_type = "inputerror"
          error = "Lens label is required"
        }
      
        var.update $lens_label {
          value = $input.label
        }
      }
    }
  
    var $lens_key {
      value = "lens-%d"|sprintf:$next_lens_order
    }
  
    // ── Actor template defaults ──
    var $effective_template_key {
      value = $input.template_key
    }
  
    var $effective_role_prompt {
      value = $input.role_prompt
    }
  
    var $actor_fields_scaffold {
      value = null
    }
  
    conditional {
      if ($input.actor_type == "customer") {
        conditional {
          if ($effective_template_key == null || $effective_template_key == "") {
            var.update $effective_template_key {
              value = "customer-v1"
            }
          }
        }
      
        conditional {
          if ($effective_role_prompt == null || $effective_role_prompt == "") {
            var.update $effective_role_prompt {
              value = "You are capturing the customer perspective at each stage of this journey. For each stage focus on: Entry Trigger (what brought the customer here), Emotions (how the customer feels), Information Needs (what the customer needs to know), Decisions Required (choices the customer must make), Friction Points (what could cause hesitation or abandonment), Assumptions (what the customer believes that may be wrong), Acceptance Criteria (what success looks like for the customer), Expected Output (what the customer expects after this step), and Channel/Touchpoint (how or where this step happens). Be specific. Use the customer language. Avoid internal jargon."
            }
          }
        }
      
        var.update $actor_fields_scaffold {
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
        conditional {
          if ($effective_template_key == null || $effective_template_key == "") {
            var.update $effective_template_key {
              value = "internal-v1"
            }
          }
        }
      
        conditional {
          if ($effective_role_prompt == null || $effective_role_prompt == "") {
            var.update $effective_role_prompt {
              value = "You are capturing the internal employee perspective at each stage of this journey. For each stage focus on: Task / Objective (what they are responsible for at this step), Entry Point / Trigger (what initiates their involvement), Tools & Systems Used (what platforms or devices they rely on), Information Needs (what data or context they need), Decisions Required (judgment calls they must make), Friction Points (what slows them down or causes errors), Assumptions Being Made (what they believe that may cause issues if wrong), Handoff Dependencies (what they need from a previous step or person), Success Criteria (what completing this step correctly looks like), Output / Deliverable (what they produce or pass forward), Employee Constraints (limitations affecting how they perform), and Pain Points (recurring frustrations or gaps). Be specific. Use operational language. Focus on process gaps and friction."
            }
          }
        }
      
        var.update $actor_fields_scaffold {
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
        conditional {
          if ($effective_template_key == null || $effective_template_key == "") {
            var.update $effective_template_key {
              value = "engineering-v1"
            }
          }
        }
      
        conditional {
          if ($effective_role_prompt == null || $effective_role_prompt == "") {
            var.update $effective_role_prompt {
              value = "You are capturing the engineering and technical perspective at each stage of this journey. For each stage focus on: System / Service Owner (what system or service is responsible for this step), Data Inputs (what data is required to initiate or complete this step), Data Outputs (what data is produced or updated when this step completes), API / Integration Dependencies (what external or internal services need to be called), Business Rules / Logic (what conditions or rules govern how this step behaves), Error States / Edge Cases (what can go wrong technically and how it should be handled), Data Storage Requirements (what needs to be saved, where, and for how long), Security & Permissions (who or what system is allowed to access or modify this step), Performance Requirements (how fast or reliable this step needs to be), and Audit / Logging Needs (what events need to be tracked for compliance or debugging). Be precise. Use technical language. Reference system names, SLAs, and data contracts where relevant."
            }
          }
        }
      
        var.update $actor_fields_scaffold {
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
        conditional {
          if ($effective_template_key == null || $effective_template_key == "") {
            var.update $effective_template_key {
              value = "ai-agent-v1"
            }
          }
        }
      
        conditional {
          if ($effective_role_prompt == null || $effective_role_prompt == "") {
            var.update $effective_role_prompt {
              value = "You are capturing the AI model or automated agent perspective at each stage of this journey. For each stage focus on: AI Model / Agent (what specific AI model or agent is responsible), Input Data (what data the AI consumes), Decision / Output (what the AI decides or generates), Confidence Threshold (what certainty level is needed before acting independently), Escalation Logic (when and to whom the AI hands off to a human), Training Data (what historical data was used to train this model), Retraining Frequency (how often the model gets updated), Bias & Fairness Considerations (what potential biases could be introduced), Failure Scenarios (what can go wrong and what the fallback is), Performance Metrics (how effectiveness is measured), Model Owner (who is responsible for maintaining this AI), and Explainability Needs (whether users need to understand why the AI made this decision). Be precise. Reference model names, confidence scores, and SLAs where relevant."
            }
          }
        }
      
        var.update $actor_fields_scaffold {
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
        conditional {
          if ($effective_template_key == null || $effective_template_key == "") {
            var.update $effective_template_key {
              value = "handoff-v1"
            }
          }
        }
      
        conditional {
          if ($effective_role_prompt == null || $effective_role_prompt == "") {
            var.update $effective_role_prompt {
              value = "You are capturing the system handoff and dependency perspective at each stage of this journey. For each stage focus on: Trigger Event (what initiates this step), Upstream Actor (who initiates this handoff), Prerequisite Data (what data must be present), Upstream Dependencies (what must be completed before this step), Handoff Output (what is passed forward), Handoff Format (how information is transferred), Handoff Timing (when the handoff occurs), Downstream Actor (who receives the handoff), Validation Rules (what conditions define a successful handoff), Failure Recovery (what happens if the handoff fails), Communication Method (how the downstream actor is notified), and Data Retention Policy (how long handoff data is stored and where). Focus on the connective tissue between steps and identify gaps in the handoff chain."
            }
          }
        }
      
        var.update $actor_fields_scaffold {
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
        conditional {
          if ($effective_template_key == null || $effective_template_key == "") {
            var.update $effective_template_key {
              value = "vendor-v1"
            }
          }
        }
      
        conditional {
          if ($effective_role_prompt == null || $effective_role_prompt == "") {
            var.update $effective_role_prompt {
              value = "You are capturing the third-party vendor perspective at each stage of this journey. For each stage focus on: Vendor Name / Type (who this third party is and what category they fall under), Role at This Step (what specific function this vendor performs), Engagement Trigger (what event activates this vendor), Contractual Obligations (agreed service levels this vendor must meet), Information Needs (what data must be shared with this vendor), Information They Return (data or confirmation the vendor sends back), Integration Method (how this vendor connects to your system), SLA / Performance Metrics (how this vendor's performance is measured), Failure Scenario (what happens if this vendor fails to perform), Escalation Path (who owns the relationship and resolves issues), Data Privacy & Compliance (data governance rules for what is shared with this vendor), Vendor Constraints (limitations the vendor operates under), Cost Impact (financial implication of this vendor's involvement), and Dependency on Internal Actors (what internal teams must complete before this vendor can begin). Be specific. Reference vendor names, SLA thresholds, and integration types where relevant."
            }
          }
        }
      
        var.update $actor_fields_scaffold {
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
      if ($input.actor_type == "financial") {
        conditional {
          if ($effective_template_key == null || $effective_template_key == "") {
            var.update $effective_template_key {
              value = "financial-v1"
            }
          }
        }
      
        conditional {
          if ($effective_role_prompt == null || $effective_role_prompt == "") {
            var.update $effective_role_prompt {
              value = "You are capturing the financial intelligence perspective at each stage of this journey. For each stage focus on: Cost to Serve (estimated cost per interaction, transaction, or touchpoint at this stage), Revenue at Risk (revenue lost or threatened if this stage has friction or fails), Automation Savings (cost savings achievable if manual steps at this stage are automated), Upsell / Cross-sell Opportunity (revenue opportunity from upsell or cross-sell actions available at this stage), Revenue Leakage (value lost due to drop-off, abandonment, errors, or rework at this stage), Cost Efficiency Note (key observation about cost drivers, waste, or inefficiency at this stage), Breakeven Threshold (minimum improvement required to justify the cost of fixing this stage), CAC Contribution (how this stage contributes to or inflates customer acquisition cost), CLV Impact (how this stage positively or negatively affects long-term customer lifetime value), and Financial Priority Score (relative investment priority based on combined cost and revenue impact). Be specific. Use dollar figures, percentages, and time horizons where possible. Reference upstream friction from other lenses as the root cause of financial impact."
            }
          }
        }
      
        var.update $actor_fields_scaffold {
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
      if ($input.actor_type == "metrics") {
        conditional {
          if ($effective_template_key == null || $effective_template_key == "") {
            var.update $effective_template_key {
              value = "metrics-v1"
            }
          }
        }
      
        conditional {
          if ($effective_role_prompt == null || $effective_role_prompt == "") {
            var.update $effective_role_prompt {
              value = "You are capturing the operational metrics perspective at each stage of this journey. Infer numeric values from the qualitative content already written in sibling actor rows at the same stage. For each stage focus on: CSAT Score (1-10, inferred from Customer emotions and friction points), Completion Rate % (inferred from Internal success criteria and handoff dependencies), Drop-off Rate % (inferred from Customer friction points and decisions required), Avg Time to Complete in minutes (inferred from Internal pain points and AI Agent escalation logic), Error Rate % (inferred from AI Agent failure scenarios and Engineering error states), SLA Compliance Rate % (inferred from Internal employee constraints and Engineering performance requirements), Volume / Frequency (free text description of interaction volume), and Stage Health Score (1-10, calculated as: ((csat_score/10 * 0.35) + (completion_rate/100 * 0.35) + ((100-drop_off_rate)/100 * 0.20) + ((100-error_rate)/100 * 0.10)) * 10). Always call get_slice before inferring. Pass numeric values not strings for all fields except volume_frequency. Skip any field that already has a non-null value unless user explicitly asks to recalculate."
            }
          }
        }
      
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
  
    db.add journey_lens {
      data = {
        created_at          : "now"
        updated_at          : "now"
        journey_map         : $input.journey_map_id
        key                 : $lens_key
        label               : $lens_label
        display_order       : $next_lens_order
        actor_type          : $input.actor_type
        template_key        : $effective_template_key
        role_prompt         : $effective_role_prompt
        persona_description : $input.persona_description
        primary_goal        : $input.primary_goal
        standing_constraints: $input.standing_constraints
      }
    } as $journey_lens
  
    foreach ($existing_stages) {
      each as $stage {
        db.add journey_cell {
          data = {
            created_at  : "now"
            updated_at  : "now"
            journey_map : $input.journey_map_id
            stage       : $stage.id
            lens        : $journey_lens.id
            content     : ""
            status      : "open"
            is_locked   : false
            actor_fields: $actor_fields_scaffold
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
    } as $journey_map_touch
  }

  response = {
    lens                  : $journey_lens
    cells                 : $cells
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}