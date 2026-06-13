import type { ActorType, Stage, Lens } from './types';

// ── Actor Template Registry ──

export interface CellFieldDef {
  key: string;
  label: string;
  placeholder: string;
}

export interface ActorTemplate {
  actorType: ActorType;
  templateKey: string | null;
  label: string;
  description: string;
  icon: string;
  rolePrompt: string;
  /** Ordered field definitions for rendering in the Cell Detail Panel. */
  cellFields: CellFieldDef[];
  /** JSON scaffold derived from cellFields — written to each cell on row creation. */
  cellFieldScaffold: Record<string, null> | null;
  comingSoon?: boolean;
}

export const ACTOR_TEMPLATES: ActorTemplate[] = [
  {
    actorType: 'customer',
    templateKey: 'customer-v1',
    label: 'Customer',
    description: 'End customer experience — emotions, decisions, friction, and expectations at each stage.',
    icon: '👤',
    rolePrompt:
      'You are capturing the customer perspective at each stage of this journey. For each stage focus on: ' +
      'Entry Trigger (what brought the customer here), Emotions (how the customer feels), ' +
      'Information Needs (what the customer needs to know), Decisions Required (choices the customer must make), ' +
      'Friction Points (what could cause hesitation or abandonment), ' +
      'Assumptions (what the customer believes that may be wrong), ' +
      'Acceptance Criteria (what success looks like for the customer), ' +
      'Expected Output (what the customer expects after this step), ' +
      'and Channel/Touchpoint (how or where this step happens). ' +
      'Be specific. Use the customer language. Avoid internal jargon.',
    cellFields: [
      {key: 'entry_trigger',      label: 'Entry Point / Trigger',        placeholder: 'e.g. Saw an ad online, walked into a store'},
      {key: 'emotions',           label: 'Feelings / Emotions',           placeholder: 'e.g. Anxious about making the right choice'},
      {key: 'information_needs',  label: 'Information Needs',             placeholder: 'e.g. Is installation included? What are the dimensions?'},
      {key: 'decisions_required', label: 'Decisions Required',            placeholder: 'e.g. Delivery date, haul away old unit, payment method'},
      {key: 'friction_points',    label: 'Friction Points',               placeholder: 'e.g. Unclear fees, no real-time availability shown'},
      {key: 'assumptions',        label: 'Assumptions',                   placeholder: 'e.g. Assumes installation is included in the price'},
      {key: 'acceptance_criteria',label: 'Acceptance Criteria',           placeholder: 'e.g. Order confirmed, delivery date visible, cost clear'},
      {key: 'expected_output',    label: 'Expected Output / Confirmation', placeholder: 'e.g. Confirmation email with order number and next steps'},
      {key: 'channel_touchpoint', label: 'Channel / Touchpoint',          placeholder: 'e.g. Website, mobile app, in-store, call center'},
    ],
    cellFieldScaffold: {
      entry_trigger: null,
      emotions: null,
      information_needs: null,
      decisions_required: null,
      friction_points: null,
      assumptions: null,
      acceptance_criteria: null,
      expected_output: null,
      channel_touchpoint: null,
    },
  },
  {
    actorType: 'internal',
    templateKey: 'internal-v1',
    label: 'Internal Employee',
    description: 'Any internal employee role — tasks, tools, handoffs, constraints, and pain points at each stage.',
    icon: '🏢',
    rolePrompt:
      'You are capturing the internal employee perspective at each stage of this journey. For each stage focus on: ' +
      'Task / Objective (what they are responsible for at this step), ' +
      'Entry Point / Trigger (what initiates their involvement), ' +
      'Tools & Systems Used (what platforms or devices they rely on), ' +
      'Information Needs (what data or context they need), ' +
      'Decisions Required (judgment calls they must make), ' +
      'Friction Points (what slows them down or causes errors), ' +
      'Assumptions Being Made (what they believe that may cause issues if wrong), ' +
      'Handoff Dependencies (what they need from a previous step or person), ' +
      'Success Criteria (what completing this step correctly looks like), ' +
      'Output / Deliverable (what they produce or pass forward), ' +
      'Employee Constraints (limitations affecting how they perform), ' +
      'and Pain Points (recurring frustrations or gaps). ' +
      'Be specific. Use operational language. Focus on process gaps and friction.',
    cellFields: [
      {key: 'task_objective',        label: 'Task / Objective',          placeholder: 'e.g. Assign delivery stops to the correct driver'},
      {key: 'entry_trigger',         label: 'Entry Point / Trigger',     placeholder: 'e.g. Order appears in the system, shift starts'},
      {key: 'tools_systems',         label: 'Tools & Systems Used',      placeholder: 'e.g. Route planning software, handheld scanner, mobile app'},
      {key: 'information_needs',     label: 'Information Needs',         placeholder: 'e.g. Customer address, access notes, delivery time window'},
      {key: 'decisions_required',    label: 'Decisions Required',        placeholder: 'e.g. Re-sequence stops due to traffic, escalate a failed delivery'},
      {key: 'friction_points',       label: 'Friction Points',           placeholder: 'e.g. Incomplete customer info, system lag, last-minute order changes'},
      {key: 'assumptions',           label: 'Assumptions Being Made',    placeholder: 'e.g. Assumes customer will be home, assumes elevator is available'},
      {key: 'handoff_dependencies',  label: 'Handoff Dependencies',      placeholder: 'e.g. Confirmed order details from warehouse, updated manifest'},
      {key: 'success_criteria',      label: 'Success Criteria',          placeholder: 'e.g. Route optimized, driver notified, all stops accounted for'},
      {key: 'output_deliverable',    label: 'Output / Deliverable',      placeholder: 'e.g. Finalized route, updated delivery status, signed confirmation'},
      {key: 'employee_constraints',  label: 'Employee Constraints',      placeholder: 'e.g. Hours of service limits, vehicle capacity, coverage area'},
      {key: 'pain_points',           label: 'Pain Points',               placeholder: 'e.g. No real-time customer availability updates, manual data entry'},
    ],
    cellFieldScaffold: {
      task_objective:       null,
      entry_trigger:        null,
      tools_systems:        null,
      information_needs:    null,
      decisions_required:   null,
      friction_points:      null,
      assumptions:          null,
      handoff_dependencies: null,
      success_criteria:     null,
      output_deliverable:   null,
      employee_constraints: null,
      pain_points:          null,
    },
  },
  {
    actorType: 'handoff',
    templateKey: 'handoff-v1',
    label: 'System Handoff',
    description: 'Connective flow between steps and actors — triggers, upstream/downstream dependencies, handoff format, validation, and failure recovery.',
    icon: '🔀',
    rolePrompt:
      'You are capturing the system handoff and dependency perspective at each stage of this journey. For each stage focus on: ' +
      'Trigger Event (what event or action initiates this step and its handoff), ' +
      'Upstream Actor (who is responsible for the previous step and initiating this handoff), ' +
      'Prerequisite Data (what specific data must be present before this step can begin), ' +
      'Upstream Dependencies (what must be completed or confirmed in the previous step for this step to proceed), ' +
      'Handoff Output (what data, signal, or deliverable is being passed forward to the next step), ' +
      'Handoff Format (how the information is being transferred between actors or systems), ' +
      'Handoff Timing (when the handoff occurs relative to the completion of this step), ' +
      'Downstream Actor (who receives this handoff and is responsible for the next step), ' +
      'Validation Rules (what conditions must be met for the handoff to be considered successful), ' +
      'Failure Recovery (what happens if the handoff fails or data is missing), ' +
      'Communication Method (how the downstream actor is notified about this handoff), ' +
      'and Data Retention Policy (how long the handoff data is stored and where). ' +
      'Focus on the connective tissue between steps. Identify gaps in the handoff chain and missing dependencies.',
    cellFields: [
      {key: 'trigger_event',          label: 'Trigger Event',           placeholder: 'e.g. Order confirmed by customer, ready for route assignment'},
      {key: 'upstream_actor',         label: 'Upstream Actor',          placeholder: 'e.g. Customer completes order, route planner receives it'},
      {key: 'prerequisite_data',      label: 'Prerequisite Data',       placeholder: 'e.g. Complete customer address, delivery time window, product SKU'},
      {key: 'upstream_dependencies',  label: 'Upstream Dependencies',   placeholder: 'e.g. Payment processed, inventory verified, delivery zone confirmed'},
      {key: 'handoff_output',         label: 'Handoff Output',          placeholder: 'e.g. Optimized route, delivery manifest, driver assignment'},
      {key: 'handoff_format',         label: 'Handoff Format',          placeholder: 'e.g. API call, database update, notification push, manual email'},
      {key: 'handoff_timing',         label: 'Handoff Timing',          placeholder: 'e.g. Immediately upon completion, within 5 minutes, end of shift'},
      {key: 'downstream_actor',       label: 'Downstream Actor',        placeholder: 'e.g. Driver receives route, warehouse receives manifest'},
      {key: 'validation_rules',       label: 'Validation Rules',        placeholder: 'e.g. All required fields populated, data quality score above 90%'},
      {key: 'failure_recovery',       label: 'Failure Recovery',        placeholder: 'e.g. Escalate to supervisor, retry after 15 minutes, queue for manual review'},
      {key: 'communication_method',   label: 'Communication Method',    placeholder: 'e.g. Push notification, SMS, email, in-app alert'},
      {key: 'data_retention_policy',  label: 'Data Retention Policy',   placeholder: 'e.g. Stored in database for 90 days, archived logs retained 2 years'},
    ],
    cellFieldScaffold: {
      trigger_event:         null,
      upstream_actor:        null,
      prerequisite_data:     null,
      upstream_dependencies: null,
      handoff_output:        null,
      handoff_format:        null,
      handoff_timing:        null,
      downstream_actor:      null,
      validation_rules:      null,
      failure_recovery:      null,
      communication_method:  null,
      data_retention_policy: null,
    },
  },
  {
    actorType: 'vendor',
    templateKey: 'vendor-v1',
    label: 'Third-Party Vendor',
    description: 'External vendor or partner — engagement trigger, SLA obligations, integration method, failure scenarios, and cost impact at each stage.',
    icon: '🤝',
    rolePrompt:
      'You are capturing the third-party vendor perspective at each stage of this journey. For each stage focus on: ' +
      'Vendor Name / Type (who this third party is and what category they fall under — e.g. last mile carrier, payment processor, installation partner), ' +
      'Role at This Step (what specific function this vendor performs at this step), ' +
      'Engagement Trigger (what event or action activates this vendor at this step), ' +
      'Contractual Obligations (agreed upon service levels or commitments this vendor must meet), ' +
      'Information Needs (what data must be shared with this vendor for them to perform their role), ' +
      'Information They Return (data or confirmation the vendor sends back upon completion), ' +
      'Integration Method (how this vendor connects to your system — API, webhook, manual email, EDI, flat file), ' +
      'SLA / Performance Metrics (how this vendor\'s performance is measured at this step), ' +
      'Failure Scenario (what happens if this vendor fails to perform at this step), ' +
      'Escalation Path (who owns the relationship and resolves issues when the vendor fails), ' +
      'Data Privacy & Compliance (data governance rules that apply to what is shared with this vendor), ' +
      'Vendor Constraints (limitations the vendor operates under that affect this step — service hours, geographic coverage, capacity), ' +
      'Cost Impact (financial implication of this vendor\'s involvement at this step), ' +
      'and Dependency on Internal Actors (what internal teams must complete before this vendor can begin). ' +
      'Be specific. Reference vendor names, SLA thresholds, and integration types where relevant.',
    cellFields: [
      {key: 'vendor_name_type',        label: 'Vendor Name / Type',            placeholder: 'e.g. Last mile carrier, installation partner, payment processor'},
      {key: 'role_at_step',            label: 'Role at This Step',             placeholder: 'e.g. Delivers appliance, processes payment, verifies address'},
      {key: 'engagement_trigger',      label: 'Engagement Trigger',            placeholder: 'e.g. Order confirmed, driver dispatched, payment initiated'},
      {key: 'contractual_obligations', label: 'Contractual Obligations',       placeholder: 'e.g. Delivery within 4-hour window, 99.9% uptime, same-day confirmation'},
      {key: 'information_needs',       label: 'Information Needs',             placeholder: 'e.g. Customer address, delivery window, product dimensions, access notes'},
      {key: 'information_returned',    label: 'Information They Return',       placeholder: 'e.g. Delivery confirmation, signature capture, status update, invoice'},
      {key: 'integration_method',      label: 'Integration Method',            placeholder: 'e.g. REST API, webhook, manual email, EDI, flat file transfer'},
      {key: 'sla_performance_metrics', label: 'SLA / Performance Metrics',     placeholder: 'e.g. On-time delivery rate, error rate, response time under 2 hours'},
      {key: 'failure_scenario',        label: 'Failure Scenario',              placeholder: 'e.g. Escalate to backup carrier, notify customer, trigger exception journey'},
      {key: 'escalation_path',         label: 'Escalation Path',               placeholder: 'e.g. Vendor manager, operations director, customer support'},
      {key: 'data_privacy_compliance', label: 'Data Privacy & Compliance',     placeholder: 'e.g. PII handling, GDPR compliance, data retention limits'},
      {key: 'vendor_constraints',      label: 'Vendor Constraints',            placeholder: 'e.g. Service hours, geographic coverage, weight or size limits'},
      {key: 'cost_impact',             label: 'Cost Impact',                   placeholder: 'e.g. Per delivery fee, overage charges, penalty clauses for SLA breach'},
      {key: 'dependency_on_internal',  label: 'Dependency on Internal Actors', placeholder: 'e.g. Route must be finalized, manifest approved, payment cleared'},
    ],
    cellFieldScaffold: {
      vendor_name_type:        null,
      role_at_step:            null,
      engagement_trigger:      null,
      contractual_obligations: null,
      information_needs:       null,
      information_returned:    null,
      integration_method:      null,
      sla_performance_metrics: null,
      failure_scenario:        null,
      escalation_path:         null,
      data_privacy_compliance: null,
      vendor_constraints:      null,
      cost_impact:             null,
      dependency_on_internal:  null,
    },
  },
  {
    actorType: 'financial',
    templateKey: 'financial-v1',
    label: 'Financial Intelligence',
    description: 'Cost efficiency and revenue opportunity — cost-to-serve, revenue at risk, automation savings, upsell potential, and financial priority at each stage.',
    icon: '💰',
    rolePrompt:
      'You are capturing the financial intelligence perspective at each stage of this journey. For each stage focus on: ' +
      'Cost to Serve (estimated cost per interaction, transaction, or touchpoint at this stage), ' +
      'Revenue at Risk (revenue lost or threatened if this stage has friction or fails), ' +
      'Automation Savings (cost savings achievable if manual steps at this stage are automated), ' +
      'Upsell / Cross-sell Opportunity (revenue opportunity from upsell or cross-sell actions available at this stage), ' +
      'Revenue Leakage (value lost due to drop-off, abandonment, errors, or rework at this stage), ' +
      'Cost Efficiency Note (key observation about cost drivers, waste, or inefficiency at this stage), ' +
      'Breakeven Threshold (minimum improvement required to justify the cost of fixing this stage), ' +
      'CAC Contribution (how this stage contributes to or inflates customer acquisition cost), ' +
      'CLV Impact (how this stage positively or negatively affects long-term customer lifetime value), ' +
      'and Financial Priority Score (relative investment priority based on combined cost and revenue impact). ' +
      'Be specific. Use dollar figures, percentages, and time horizons where possible. ' +
      'Reference upstream friction from other lenses as the root cause of financial impact.',
    cellFields: [
      {key: 'cost_to_serve',       label: 'Cost to Serve',                    placeholder: 'e.g. $4.20 per checkout attempt (agent-assisted)'},
      {key: 'revenue_at_risk',     label: 'Revenue at Risk',                   placeholder: 'e.g. $18,400/mo lost to cart abandonment at this step'},
      {key: 'automation_savings',  label: 'Automation Savings',                placeholder: 'e.g. $3.10 saved per interaction with address auto-fill'},
      {key: 'upsell_opportunity',  label: 'Upsell / Cross-sell Opportunity',   placeholder: 'e.g. $6.50 avg order uplift if warranty upsell shown here'},
      {key: 'revenue_leakage',     label: 'Revenue Leakage',                   placeholder: 'e.g. 18% drop-off = $47K MRR lost monthly'},
      {key: 'cost_efficiency_note',label: 'Cost Efficiency Note',              placeholder: 'e.g. 68% of support contacts here are about shipping cost — FAQ would deflect most'},
      {key: 'breakeven_threshold', label: 'Breakeven Threshold',               placeholder: 'e.g. Fix must recover >$500/mo to cover sprint cost'},
      {key: 'cac_contribution',    label: 'CAC Contribution',                  placeholder: 'e.g. Retargeting spend at this step = $2.10 of $8.40 total CAC'},
      {key: 'clv_impact',          label: 'CLV Impact',                        placeholder: 'e.g. Slow refund at this step drives 12% churn within 90 days'},
      {key: 'priority_score',      label: 'Financial Priority Score',          placeholder: 'e.g. High — $7K/mo recoverable; estimated 2-sprint fix'},
    ],
    cellFieldScaffold: {
      cost_to_serve:        null,
      revenue_at_risk:      null,
      automation_savings:   null,
      upsell_opportunity:   null,
      revenue_leakage:      null,
      cost_efficiency_note: null,
      breakeven_threshold:  null,
      cac_contribution:     null,
      clv_impact:           null,
      priority_score:       null,
    },
  },
  {
    actorType: 'operations',
    templateKey: null,
    label: 'Operations',
    description: 'Internal operations team — responsibilities, handoffs, SLAs, and escalation paths.',
    icon: '⚙️',
    rolePrompt: '',
    cellFields: [],
    cellFieldScaffold: null,
    comingSoon: true,
  },
  {
    actorType: 'ai_agent',
    templateKey: 'ai-agent-v1',
    label: 'AI Agent',
    description: 'AI model or automated agent role — decisions, confidence, escalation, training, and performance at each stage.',
    icon: '🤖',
    rolePrompt:
      'You are capturing the AI model or automated agent perspective at each stage of this journey. For each stage focus on: ' +
      'AI Model / Agent (what specific AI model or agent is responsible for this step), ' +
      'Input Data (what data the AI consumes to make decisions or predictions), ' +
      'Decision / Output (what the AI decides, predicts, or generates at this step), ' +
      'Confidence Threshold (what level of certainty the AI needs before acting independently), ' +
      'Escalation Logic (when and to whom the AI hands off to a human), ' +
      'Training Data (what historical data was used to train this model), ' +
      'Retraining Frequency (how often the model gets updated with new data), ' +
      'Bias & Fairness Considerations (what potential biases the AI could introduce and how they are monitored), ' +
      'Failure Scenarios (what can go wrong with the AI and what the fallback behavior is), ' +
      'Performance Metrics (how the AI effectiveness is measured at this step), ' +
      'Model Owner (who is responsible for maintaining, monitoring, and improving this AI), ' +
      'and Explainability Needs (whether users or stakeholders need to understand why the AI made this decision). ' +
      'Be precise. Reference model names, confidence scores, and SLAs where relevant.',
    cellFields: [
      {key: 'ai_model_agent',               label: 'AI Model / Agent',                placeholder: 'e.g. Route optimization engine, delivery time predictor, chatbot'},
      {key: 'input_data',                   label: 'Input Data',                      placeholder: 'e.g. Order details, traffic patterns, historical delivery times'},
      {key: 'decision_output',              label: 'Decision / Output',               placeholder: 'e.g. Optimal route sequence, delivery window estimate'},
      {key: 'confidence_threshold',         label: 'Confidence Threshold',            placeholder: 'e.g. Route confidence must be above 85%, else escalate'},
      {key: 'escalation_logic',             label: 'Escalation Logic',                placeholder: 'e.g. If confidence below threshold, if unusual edge case detected'},
      {key: 'training_data',                label: 'Training Data',                   placeholder: 'e.g. 12 months of past delivery data, 50,000 successful routes'},
      {key: 'retraining_frequency',         label: 'Retraining Frequency',            placeholder: 'e.g. Weekly, monthly, or triggered by performance drift'},
      {key: 'bias_fairness_considerations', label: 'Bias & Fairness Considerations',  placeholder: 'e.g. Geographic bias favoring certain neighborhoods'},
      {key: 'failure_scenarios',            label: 'Failure Scenarios',               placeholder: 'e.g. Model downtime, poor prediction accuracy, data drift'},
      {key: 'performance_metrics',          label: 'Performance Metrics',             placeholder: 'e.g. Route time accuracy within ±10 minutes, customer satisfaction score'},
      {key: 'model_owner',                  label: 'Model Owner',                     placeholder: 'e.g. Data science team, ML ops engineer'},
      {key: 'explainability_needs',         label: 'Explainability Needs',            placeholder: 'e.g. Driver needs to understand why route was sequenced this way'},
    ],
    cellFieldScaffold: {
      ai_model_agent:               null,
      input_data:                   null,
      decision_output:              null,
      confidence_threshold:         null,
      escalation_logic:             null,
      training_data:                null,
      retraining_frequency:         null,
      bias_fairness_considerations: null,
      failure_scenarios:            null,
      performance_metrics:          null,
      model_owner:                  null,
      explainability_needs:         null,
    },
  },
  {
    actorType: 'engineering',
    templateKey: 'engineering-v1',
    label: 'Engineering',
    description: 'Technical perspective — systems, data flows, integrations, rules, error handling, and performance at each stage.',
    icon: '⚙️',
    rolePrompt:
      'You are capturing the engineering / technical perspective at each stage of this journey. For each stage focus on: ' +
      'System / Service Owner (what system or service is responsible for this step), ' +
      'Data Inputs (what data is required to initiate or complete this step), ' +
      'Data Outputs (what data is produced or updated when this step completes), ' +
      'API / Integration Dependencies (what external or internal services need to be called), ' +
      'Business Rules / Logic (what conditions or rules govern how this step behaves), ' +
      'Error States / Edge Cases (what can go wrong technically and how it should be handled), ' +
      'Data Storage Requirements (what needs to be saved, where, and for how long), ' +
      'Security & Permissions (who or what system is allowed to access or modify this step), ' +
      'Performance Requirements (how fast or reliable this step needs to be), ' +
      'and Audit / Logging Needs (what events need to be tracked for compliance or debugging). ' +
      'Be precise. Use technical language. Reference system names, SLAs, and data contracts where relevant.',
    cellFields: [
      {key: 'system_service_owner',        label: 'System / Service Owner',          placeholder: 'e.g. Order Management System, TMS, CRM'},
      {key: 'data_inputs',                 label: 'Data Inputs',                     placeholder: 'e.g. Customer ID, address, product SKU, time window'},
      {key: 'data_outputs',                label: 'Data Outputs',                    placeholder: 'e.g. Delivery status, route ID, confirmation timestamp'},
      {key: 'api_integration_dependencies',label: 'API / Integration Dependencies',  placeholder: 'e.g. Payment gateway, mapping API, notification service'},
      {key: 'business_rules_logic',        label: 'Business Rules / Logic',          placeholder: 'e.g. If delivery fails twice escalate to supervisor'},
      {key: 'error_states_edge_cases',     label: 'Error States / Edge Cases',       placeholder: 'e.g. Address not found, API timeout, duplicate order'},
      {key: 'data_storage_requirements',   label: 'Data Storage Requirements',       placeholder: 'e.g. Delivery confirmation stored for 90 days'},
      {key: 'security_permissions',        label: 'Security & Permissions',          placeholder: 'e.g. Driver can only see their own route'},
      {key: 'performance_requirements',    label: 'Performance Requirements',        placeholder: 'e.g. Notification must fire within 30 seconds of trigger'},
      {key: 'audit_logging_needs',         label: 'Audit / Logging Needs',           placeholder: 'e.g. Log every status change with timestamp and user ID'},
    ],
    cellFieldScaffold: {
      system_service_owner:         null,
      data_inputs:                  null,
      data_outputs:                 null,
      api_integration_dependencies: null,
      business_rules_logic:         null,
      error_states_edge_cases:      null,
      data_storage_requirements:    null,
      security_permissions:         null,
      performance_requirements:     null,
      audit_logging_needs:          null,
    },
  },
  {
    actorType: 'metrics',
    templateKey: 'metrics-v1',
    label: 'Metrics',
    description: 'Operational KPIs — CSAT, completion rate, drop-off, error rate, and stage health score at each stage. AI-inferred from qualitative actor content. No manual entry required.',
    icon: '📊',
    rolePrompt:
      'You are capturing the operational metrics perspective at each stage of this journey. ' +
      'Infer numeric values from the qualitative content already written in sibling actor rows at the same stage. ' +
      'For each stage focus on: ' +
      'CSAT Score (1–10, inferred from Customer emotions and friction points — heavy negative = 5–6, mild friction = 7–8, positive = 8–9+), ' +
      'Completion Rate % (inferred from Internal success criteria and handoff dependencies — gaps = lower rate), ' +
      'Drop-off Rate % (inferred from Customer friction points and decisions required — more friction = higher drop-off), ' +
      'Avg Time to Complete in minutes (inferred from Internal pain points and AI Agent escalation logic), ' +
      'Error Rate % (inferred from AI Agent failure scenarios and Engineering error states), ' +
      'SLA Compliance Rate % (inferred from Internal employee constraints and Engineering performance requirements), ' +
      'Volume / Frequency (free text description of interaction volume at this stage), ' +
      'and Stage Health Score (1–10, calculated as: ' +
      '((csat_score/10 * 0.35) + (completion_rate/100 * 0.35) + ((100-drop_off_rate)/100 * 0.20) + ((100-error_rate)/100 * 0.10)) * 10). ' +
      'Always call get_slice to read sibling actor cells before inferring. ' +
      'Pass numeric values — not strings — for all fields except volume_frequency. ' +
      'Skip any field that already has a non-null value unless the user explicitly asks to recalculate.',
    cellFields: [
      {key: 'csat_score',           label: 'CSAT Score (1–10)',            placeholder: 'e.g. 7.4  — healthy: ≥ 8.0'},
      {key: 'completion_rate',      label: 'Completion Rate (%)',           placeholder: 'e.g. 89  — healthy: ≥ 90%'},
      {key: 'drop_off_rate',        label: 'Drop-off Rate (%)',             placeholder: 'e.g. 11  — healthy: ≤ 10%'},
      {key: 'avg_time_to_complete', label: 'Avg Time to Complete (min)',    placeholder: 'e.g. 4'},
      {key: 'error_rate',           label: 'Error Rate (%)',                placeholder: 'e.g. 3.2  — healthy: ≤ 5%'},
      {key: 'sla_compliance_rate',  label: 'SLA Compliance Rate (%)',       placeholder: 'e.g. 91  — healthy: ≥ 90%'},
      {key: 'volume_frequency',     label: 'Volume / Frequency',            placeholder: 'e.g. ~300 interactions/day'},
      {key: 'stage_health',         label: 'Stage Health Score (1–10)',     placeholder: 'Auto-calculated — or override'},
    ],
    cellFieldScaffold: {
      csat_score:           null,
      completion_rate:      null,
      drop_off_rate:        null,
      avg_time_to_complete: null,
      error_rate:           null,
      sla_compliance_rate:  null,
      volume_frequency:     null,
      stage_health:         null,
    },
  },
];

/** Color threshold config for MetricsActorFields. Import in renderers — do not hardcode inline. */
export const METRICS_THRESHOLDS: Record<string, { green: (v: number) => boolean; yellow: (v: number) => boolean }> = {
  stage_health:        { green: v => v >= 8,  yellow: v => v >= 6 },
  csat_score:          { green: v => v >= 8,  yellow: v => v >= 6 },
  completion_rate:     { green: v => v >= 90, yellow: v => v >= 75 },
  drop_off_rate:       { green: v => v <= 10, yellow: v => v <= 20 },
  error_rate:          { green: v => v <= 5,  yellow: v => v <= 15 },
  sla_compliance_rate: { green: v => v >= 90, yellow: v => v >= 75 },
};

export type MetricColor = 'green' | 'yellow' | 'red';

export function getMetricColor(key: string, value: number | null | undefined): MetricColor {
  if (value == null) return 'red';
  const t = METRICS_THRESHOLDS[key];
  if (!t) return 'green';
  if (t.green(value)) return 'green';
  if (t.yellow(value)) return 'yellow';
  return 'red';
}

export const METRICS_ACTOR_ENABLED = true;

export const STAGES: Stage[] = [
  {id: 's1', key: 's1', label: 'Stage 1', displayOrder: 1},
  {id: 's2', key: 's2', label: 'Stage 2', displayOrder: 2},
  {id: 's3', key: 's3', label: 'Stage 3', displayOrder: 3},
  {id: 's4', key: 's4', label: 'Stage 4', displayOrder: 4},
  {id: 's5', key: 's5', label: 'Stage 5', displayOrder: 5},
  {id: 's6', key: 's6', label: 'Stage 6', displayOrder: 6},
  {id: 's7', key: 's7', label: 'Stage 7', displayOrder: 7},
  {id: 's8', key: 's8', label: 'Stage 8', displayOrder: 8},
];

export const LENSES: Lens[] = [
  {id: 'description', key: 'description', label: 'Description', displayOrder: 1},
  {id: 'customer', key: 'customer', label: 'Customer', displayOrder: 2},
  {id: 'owner', key: 'owner', label: 'Primary Owner', displayOrder: 3},
  {id: 'supporting', key: 'supporting', label: 'Supporting Roles', displayOrder: 4},
  {id: 'painpoint', key: 'painpoint', label: 'Top Pain Point', displayOrder: 5},
  {id: 'variable', key: 'variable', label: 'Key Variable', displayOrder: 6},
  {id: 'risk', key: 'risk', label: 'Cascade Risk', displayOrder: 7},
  {id: 'trigger', key: 'trigger', label: 'Escalation Trigger', displayOrder: 8},
  {id: 'notifications', key: 'notifications', label: 'Notifications', displayOrder: 9},
  {id: 'systems', key: 'systems', label: 'Systems / Tools', displayOrder: 10},
];
