export type CellStatus = 'draft' | 'confirmed' | 'open';

// ── Actor / Role types ──

export type ActorType = 'customer' | 'internal' | 'engineering' | 'handoff' | 'vendor' | 'financial' | 'operations' | 'ai_agent' | 'dev' | 'custom' | 'metrics';

/** Structured cell-level fields for a Customer actor row. */
export interface CustomerActorFields {
  entry_trigger?: string | null;
  emotions?: string | null;
  information_needs?: string | null;
  decisions_required?: string | null;
  friction_points?: string | null;
  assumptions?: string | null;
  acceptance_criteria?: string | null;
  expected_output?: string | null;
  channel_touchpoint?: string | null;
}

/** Structured cell-level fields for an Internal Employee actor row. */
export interface InternalActorFields {
  task_objective?: string | null;
  entry_trigger?: string | null;
  tools_systems?: string | null;
  information_needs?: string | null;
  decisions_required?: string | null;
  friction_points?: string | null;
  assumptions?: string | null;
  handoff_dependencies?: string | null;
  success_criteria?: string | null;
  output_deliverable?: string | null;
  employee_constraints?: string | null;
  pain_points?: string | null;
}

/** Structured cell-level fields for an Engineering lens row. */
export interface EngineeringActorFields {
  system_service_owner?: string | null;
  data_inputs?: string | null;
  data_outputs?: string | null;
  api_integration_dependencies?: string | null;
  business_rules_logic?: string | null;
  error_states_edge_cases?: string | null;
  data_storage_requirements?: string | null;
  security_permissions?: string | null;
  performance_requirements?: string | null;
  audit_logging_needs?: string | null;
}

/** Structured cell-level fields for an AI Agent lens row. */
export interface AiAgentActorFields {
  ai_model_agent?: string | null;
  input_data?: string | null;
  decision_output?: string | null;
  confidence_threshold?: string | null;
  escalation_logic?: string | null;
  training_data?: string | null;
  retraining_frequency?: string | null;
  bias_fairness_considerations?: string | null;
  failure_scenarios?: string | null;
  performance_metrics?: string | null;
  model_owner?: string | null;
  explainability_needs?: string | null;
}

/** Structured cell-level fields for a System Handoff & Dependencies lens row. */
export interface HandoffActorFields {
  trigger_event?: string | null;
  upstream_actor?: string | null;
  prerequisite_data?: string | null;
  upstream_dependencies?: string | null;
  handoff_output?: string | null;
  handoff_format?: string | null;
  handoff_timing?: string | null;
  downstream_actor?: string | null;
  validation_rules?: string | null;
  failure_recovery?: string | null;
  communication_method?: string | null;
  data_retention_policy?: string | null;
}

/** Structured cell-level fields for a Third-Party Vendor lens row. */
export interface VendorActorFields {
  vendor_name_type?: string | null;
  role_at_step?: string | null;
  engagement_trigger?: string | null;
  contractual_obligations?: string | null;
  information_needs?: string | null;
  information_returned?: string | null;
  integration_method?: string | null;
  sla_performance_metrics?: string | null;
  failure_scenario?: string | null;
  escalation_path?: string | null;
  data_privacy_compliance?: string | null;
  vendor_constraints?: string | null;
  cost_impact?: string | null;
  dependency_on_internal?: string | null;
}

/** Structured cell-level fields for a Financial Intelligence lens row. */
export interface FinancialActorFields {
  cost_to_serve?: string | null;
  revenue_at_risk?: string | null;
  automation_savings?: string | null;
  upsell_opportunity?: string | null;
  revenue_leakage?: string | null;
  cost_efficiency_note?: string | null;
  breakeven_threshold?: string | null;
  cac_contribution?: string | null;
  clv_impact?: string | null;
  priority_score?: string | null;
  /** Numeric paired fields for rollup calculations — written alongside string fields. */
  cost_to_serve_value?: number | null;
  revenue_at_risk_value?: number | null;
  automation_savings_value?: number | null;
  revenue_leakage_value?: number | null;
}

/**
 * Structured cell-level fields for a Metrics actor row.
 * NOTE: First actor interface in the system to use number | null typed fields.
 * Always use isMetricsActorFields() type guard before accessing numeric properties.
 * Always use parseMetricValue() when reading these values from API responses.
 */
export interface MetricsActorFields {
  /** Customer satisfaction score — range 1–10. Healthy: ≥ 8.0 */
  csat_score?: number | null;
  /** Percentage of interactions that complete this stage — 0–100. Healthy: ≥ 90 */
  completion_rate?: number | null;
  /** Percentage of interactions that abandon this stage — 0–100. Healthy: ≤ 10 */
  drop_off_rate?: number | null;
  /** Average time in minutes to complete this stage. */
  avg_time_to_complete?: number | null;
  /** Percentage of interactions resulting in an error — 0–100. Healthy: ≤ 5 */
  error_rate?: number | null;
  /** Percentage of SLA commitments met at this stage — 0–100. Healthy: ≥ 90 */
  sla_compliance_rate?: number | null;
  /** Free text volume or frequency description, e.g. "~300 interactions/day" */
  volume_frequency?: string | null;
  /**
   * Composite stage health score — range 1–10.
   * Auto-calculated on the frontend via calcStageHealth() if not explicitly set.
   * Healthy: ≥ 8.0
   */
  stage_health?: number | null;
}

/** Type guard — use before accessing numeric MetricsActorFields properties. */
export function isMetricsActorFields(f: ActorFields): f is MetricsActorFields {
  return f != null && typeof f === 'object' && ('csat_score' in f || 'stage_health' in f || 'completion_rate' in f);
}

/**
 * Safe numeric parser for MetricsActorFields values read from the API.
 * Xano may return numbers as strings from JSON columns — this normalises them.
 */
export const parseMetricValue = (v: unknown): number | null => {
  if (v == null) return null;
  if (typeof v === 'number') return isNaN(v) ? null : v;
  const n = Number(v);
  return isNaN(n) ? null : n;
};

/**
 * Null-safe stage health calculator (SE-B1).
 * Re-weights proportionally when some fields are null — never returns NaN.
 * Returns null when no fields are populated.
 * If stage_health is explicitly set, the caller should use that value instead.
 */
export function calcStageHealth(f: MetricsActorFields): number | null {
  const parts: Array<{value: number; weight: number}> = [];
  if (f.csat_score != null)       parts.push({value: f.csat_score / 10,             weight: 0.35});
  if (f.completion_rate != null)  parts.push({value: f.completion_rate / 100,        weight: 0.35});
  if (f.drop_off_rate != null)    parts.push({value: (100 - f.drop_off_rate) / 100,  weight: 0.20});
  if (f.error_rate != null)       parts.push({value: (100 - f.error_rate) / 100,     weight: 0.10});
  if (parts.length === 0) return null;
  const totalWeight = parts.reduce((s, p) => s + p.weight, 0);
  return (parts.reduce((s, p) => s + p.value * p.weight, 0) / totalWeight) * 10;
}

/** Union of all actor field shapes. Extend when new actor types are defined. */
export type ActorFields = CustomerActorFields | InternalActorFields | EngineeringActorFields | AiAgentActorFields | HandoffActorFields | VendorActorFields | FinancialActorFields | MetricsActorFields | Record<string, string | number | null>;

export type ToolTraceCategory = 'read' | 'write' | 'status' | 'structure';

export interface ToolTraceEntry {
  toolName: string;
  toolCategory: ToolTraceCategory;
  inputSummary: string;
  outputSummary: string;
  executionOrder: number;
}

export interface MessageActivity {
  cellsUpdated: number;
  cellsSkipped: number;
  structureChanged: boolean;
  progress: { totalCells: number; filledCells: number; percentage: number };
  /** Per-cell details for expanded view */
  updatedCells: { stageLabel: string; lensLabel: string }[];
  /** Layer 2: ordered tool calls from agent_tool_log */
  toolTrace?: ToolTraceEntry[];
  /** Layer 3: raw agent thinking/reasoning text */
  thinking?: string | null;
}

export interface Message {
  id: string;
  role: 'ai' | 'expert';
  content: string;
  timestamp: Date;
  /** Populated on AI messages after an ai_message call */
  activity?: MessageActivity;
}

export interface MatrixCell {
  id: string;
  xanoId?: number;
  journeyCellId?: number;
  journeyMapId?: number;
  stageId: string;
  stageKey?: string;
  stageXanoId?: number;
  lensId: string;
  lensKey?: string;
  lensXanoId?: number;
  content: string;
  status: CellStatus;
  isLocked?: boolean;
  lastUpdated?: Date;
  /** Structured actor-specific fields — populated when the parent lens has an actor_type. */
  actorFields?: ActorFields | null;
}

export interface Stage {
  id: string;
  key?: string;
  xanoId?: number;
  displayOrder?: number;
  label: string;
}

export interface Lens {
  id: string;
  key?: string;
  xanoId?: number;
  displayOrder?: number;
  label: string;
  /** Actor identity fields — populated when row was created via Actor Setup Wizard. */
  actorType?: ActorType;
  templateKey?: string;
  rolePrompt?: string;
  personaDescription?: string;
  primaryGoal?: string;
  standingConstraints?: string;
}
