// Returns the one canonical template for an actor type: its template_key,
// its role prompt, and the actor_fields scaffold for a new cell.
//
// ORD-2 US-ORD-2-01. Before this function the same ~250 lines were copied
// into journey_lens/add (49), journey_stage/add (47), ai/tool/mutate_structure
// and ai/tool/scaffold_structure, and the copies had drifted: mutate_structure
// had no financial or metrics template at all, scaffold_structure carried a
// shorter metrics prompt, and endpoint 47 was missing financial-v1 entirely,
// so adding a column to a map with a financial row scaffolded that cell with
// no actor_fields. Endpoint 49 was the most complete and most exercised copy,
// so its text is the canonical text reproduced here.
//
// Accepts either actor_type (what a caller creating a row knows) or
// template_key (what a caller reading an existing row knows), so every path
// resolves to the same answer.
//
// An empty actor_type is legitimate: a plain row with no actor type gets an
// empty template. An unrecognised one is refused with E-ORD-004.
function "journey/actor_template" {
  input {
    // One of: customer, internal, engineering, ai_agent, handoff, vendor,
    // financial, metrics. Empty means a plain row with no actor template.
    text actor_type? filters=trim|lower

    // Alternative to actor_type: resolve from an existing row's template_key.
    text template_key? filters=trim|lower
  }

  stack {
    var $type {
      value = $input.actor_type
    }

    // Resolve the actor type from a template_key when only the key is known.
    // Both conditions read inputs only, never a variable written in a loop.
    conditional {
      if ($input.actor_type == "" && $input.template_key == "customer-v1") {
        var.update $type {
          value = "customer"
        }
      }
    }

    conditional {
      if ($input.actor_type == "" && $input.template_key == "internal-v1") {
        var.update $type {
          value = "internal"
        }
      }
    }

    conditional {
      if ($input.actor_type == "" && $input.template_key == "engineering-v1") {
        var.update $type {
          value = "engineering"
        }
      }
    }

    conditional {
      if ($input.actor_type == "" && $input.template_key == "ai-agent-v1") {
        var.update $type {
          value = "ai_agent"
        }
      }
    }

    conditional {
      if ($input.actor_type == "" && $input.template_key == "handoff-v1") {
        var.update $type {
          value = "handoff"
        }
      }
    }

    conditional {
      if ($input.actor_type == "" && $input.template_key == "vendor-v1") {
        var.update $type {
          value = "vendor"
        }
      }
    }

    conditional {
      if ($input.actor_type == "" && $input.template_key == "financial-v1") {
        var.update $type {
          value = "financial"
        }
      }
    }

    conditional {
      if ($input.actor_type == "" && $input.template_key == "metrics-v1") {
        var.update $type {
          value = "metrics"
        }
      }
    }

    var $resolved_key {
      value = ""
    }

    var $resolved_prompt {
      value = ""
    }

    var $resolved_fields {
      value = {}
    }

    var $matched {
      value = false
    }

    conditional {
      if ($type == "customer") {
        var.update $resolved_key {
          value = "customer-v1"
        }

        var.update $resolved_prompt {
          value = "You are capturing the customer perspective at each stage of this journey. For each stage focus on: Entry Trigger (what brought the customer here), Emotions (how the customer feels), Information Needs (what the customer needs to know), Decisions Required (choices the customer must make), Friction Points (what could cause hesitation or abandonment), Assumptions (what the customer believes that may be wrong), Acceptance Criteria (what success looks like for the customer), Expected Output (what the customer expects after this step), and Channel/Touchpoint (how or where this step happens). Be specific. Use the customer language. Avoid internal jargon."
        }

        var.update $resolved_fields {
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

        var.update $matched {
          value = true
        }
      }
    }

    conditional {
      if ($type == "internal") {
        var.update $resolved_key {
          value = "internal-v1"
        }

        var.update $resolved_prompt {
          value = "You are capturing the internal employee perspective at each stage of this journey. For each stage focus on: Task / Objective (what they are responsible for at this step), Entry Point / Trigger (what initiates their involvement), Tools & Systems Used (what platforms or devices they rely on), Information Needs (what data or context they need), Decisions Required (judgment calls they must make), Friction Points (what slows them down or causes errors), Assumptions Being Made (what they believe that may cause issues if wrong), Handoff Dependencies (what they need from a previous step or person), Success Criteria (what completing this step correctly looks like), Output / Deliverable (what they produce or pass forward), Employee Constraints (limitations affecting how they perform), and Pain Points (recurring frustrations or gaps). Be specific. Use operational language. Focus on process gaps and friction."
        }

        var.update $resolved_fields {
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

        var.update $matched {
          value = true
        }
      }
    }

    conditional {
      if ($type == "engineering") {
        var.update $resolved_key {
          value = "engineering-v1"
        }

        var.update $resolved_prompt {
          value = "You are capturing the engineering and technical perspective at each stage of this journey. For each stage focus on: System / Service Owner (what system or service is responsible for this step), Data Inputs (what data is required to initiate or complete this step), Data Outputs (what data is produced or updated when this step completes), API / Integration Dependencies (what external or internal services need to be called), Business Rules / Logic (what conditions or rules govern how this step behaves), Error States / Edge Cases (what can go wrong technically and how it should be handled), Data Storage Requirements (what needs to be saved, where, and for how long), Security & Permissions (who or what system is allowed to access or modify this step), Performance Requirements (how fast or reliable this step needs to be), and Audit / Logging Needs (what events need to be tracked for compliance or debugging). Be precise. Use technical language. Reference system names, SLAs, and data contracts where relevant."
        }

        var.update $resolved_fields {
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

        var.update $matched {
          value = true
        }
      }
    }

    conditional {
      if ($type == "ai_agent") {
        var.update $resolved_key {
          value = "ai-agent-v1"
        }

        var.update $resolved_prompt {
          value = "You are capturing the AI model or automated agent perspective at each stage of this journey. For each stage focus on: AI Model / Agent (what specific AI model or agent is responsible), Input Data (what data the AI consumes), Decision / Output (what the AI decides or generates), Confidence Threshold (what certainty level is needed before acting independently), Escalation Logic (when and to whom the AI hands off to a human), Training Data (what historical data was used to train this model), Retraining Frequency (how often the model gets updated), Bias & Fairness Considerations (what potential biases could be introduced), Failure Scenarios (what can go wrong and what the fallback is), Performance Metrics (how effectiveness is measured), Model Owner (who is responsible for maintaining this AI), and Explainability Needs (whether users need to understand why the AI made this decision). Be precise. Reference model names, confidence scores, and SLAs where relevant."
        }

        var.update $resolved_fields {
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

        var.update $matched {
          value = true
        }
      }
    }

    conditional {
      if ($type == "handoff") {
        var.update $resolved_key {
          value = "handoff-v1"
        }

        var.update $resolved_prompt {
          value = "You are capturing the system handoff and dependency perspective at each stage of this journey. For each stage focus on: Trigger Event (what initiates this step), Upstream Actor (who initiates this handoff), Prerequisite Data (what data must be present), Upstream Dependencies (what must be completed before this step), Handoff Output (what is passed forward), Handoff Format (how information is transferred), Handoff Timing (when the handoff occurs), Downstream Actor (who receives the handoff), Validation Rules (what conditions define a successful handoff), Failure Recovery (what happens if the handoff fails), Communication Method (how the downstream actor is notified), and Data Retention Policy (how long handoff data is stored and where). Focus on the connective tissue between steps and identify gaps in the handoff chain."
        }

        var.update $resolved_fields {
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

        var.update $matched {
          value = true
        }
      }
    }

    conditional {
      if ($type == "vendor") {
        var.update $resolved_key {
          value = "vendor-v1"
        }

        var.update $resolved_prompt {
          value = "You are capturing the third-party vendor perspective at each stage of this journey. For each stage focus on: Vendor Name / Type (who this third party is and what category they fall under), Role at This Step (what specific function this vendor performs), Engagement Trigger (what event activates this vendor), Contractual Obligations (agreed service levels this vendor must meet), Information Needs (what data must be shared with this vendor), Information They Return (data or confirmation the vendor sends back), Integration Method (how this vendor connects to your system), SLA / Performance Metrics (how this vendor's performance is measured), Failure Scenario (what happens if this vendor fails to perform), Escalation Path (who owns the relationship and resolves issues), Data Privacy & Compliance (data governance rules for what is shared with this vendor), Vendor Constraints (limitations the vendor operates under), Cost Impact (financial implication of this vendor's involvement), and Dependency on Internal Actors (what internal teams must complete before this vendor can begin). Be specific. Reference vendor names, SLA thresholds, and integration types where relevant."
        }

        var.update $resolved_fields {
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

        var.update $matched {
          value = true
        }
      }
    }

    conditional {
      if ($type == "financial") {
        var.update $resolved_key {
          value = "financial-v1"
        }

        var.update $resolved_prompt {
          value = "You are capturing the financial intelligence perspective at each stage of this journey. For each stage focus on: Cost to Serve (estimated cost per interaction, transaction, or touchpoint at this stage), Revenue at Risk (revenue lost or threatened if this stage has friction or fails), Automation Savings (cost savings achievable if manual steps at this stage are automated), Upsell / Cross-sell Opportunity (revenue opportunity from upsell or cross-sell actions available at this stage), Revenue Leakage (value lost due to drop-off, abandonment, errors, or rework at this stage), Cost Efficiency Note (key observation about cost drivers, waste, or inefficiency at this stage), Breakeven Threshold (minimum improvement required to justify the cost of fixing this stage), CAC Contribution (how this stage contributes to or inflates customer acquisition cost), CLV Impact (how this stage positively or negatively affects long-term customer lifetime value), and Financial Priority Score (relative investment priority based on combined cost and revenue impact). Be specific. Use dollar figures, percentages, and time horizons where possible. Reference upstream friction from other lenses as the root cause of financial impact."
        }

        var.update $resolved_fields {
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

        var.update $matched {
          value = true
        }
      }
    }

    conditional {
      if ($type == "metrics") {
        var.update $resolved_key {
          value = "metrics-v1"
        }

        var.update $resolved_prompt {
          value = "You are capturing the operational metrics perspective at each stage of this journey. Infer numeric values from the qualitative content already written in sibling actor rows at the same stage. For each stage focus on: CSAT Score (1-10, inferred from Customer emotions and friction points), Completion Rate % (inferred from Internal success criteria and handoff dependencies), Drop-off Rate % (inferred from Customer friction points and decisions required), Avg Time to Complete in minutes (inferred from Internal pain points and AI Agent escalation logic), Error Rate % (inferred from AI Agent failure scenarios and Engineering error states), SLA Compliance Rate % (inferred from Internal employee constraints and Engineering performance requirements), Volume / Frequency (free text description of interaction volume), and Stage Health Score (1-10, calculated as: ((csat_score/10 * 0.35) + (completion_rate/100 * 0.35) + ((100-drop_off_rate)/100 * 0.20) + ((100-error_rate)/100 * 0.10)) * 10). Always call get_slice before inferring. Pass numeric values not strings for all fields except volume_frequency. Skip any field that already has a non-null value unless user explicitly asks to recalculate."
        }

        var.update $resolved_fields {
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

        var.update $matched {
          value = true
        }
      }
    }

    // ITEM-1 (US-ITEM-1-06, audit finding T-1) — the Items row has no
    // actor_type (it is "", not one of the 11 enum values above), so it
    // can only be reached by template_key, never by the $type branches.
    // Checked directly against $input.template_key rather than through
    // $type/$matched's actor_type-keyed resolution above. Without this,
    // a stage added after the Items row existed (insert_stage, add_stage,
    // scaffold_map) gave its Items cell an EMPTY actor_fields instead of
    // the {scales_with: "per_order", lines: []} default every other
    // Items cell is created with.
    conditional {
      if ($input.template_key == "items-v1") {
        var.update $resolved_key {
          value = "items-v1"
        }

        var.update $resolved_fields {
          value = {}
            |set:"scales_with":"per_order"
            |set:"lines":[]
        }

        var.update $matched {
          value = true
        }
      }
    }

    // An empty type is a plain row and is allowed. Anything else that did not
    // match is a caller mistake — almost always the AI inventing an actor type.
    precondition ($type == "" || $matched == true) {
      error_type = "inputerror"
      error = "That actor type is not one I know. Valid types are customer, internal, engineering, ai_agent, handoff, vendor, financial and metrics. (E-ORD-004)"
    }

  }

  response = {
    actor_type  : $type
    template_key: $resolved_key
    role_prompt : $resolved_prompt
    actor_fields: $resolved_fields
    matched     : $matched
  }
}
