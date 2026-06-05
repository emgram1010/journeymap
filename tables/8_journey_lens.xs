// Represents different perspectives or 'lenses' for viewing a journey map.
table journey_lens {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update to the journey lens.
    date updated_at?
  
    // Reference to the journey map this lens belongs to.
    int journey_map? {
      table = "journey_map"
    }
  
    // Unique identifier key for the lens within its journey map.
    text key? filters=trim
  
    // Display label for the journey lens.
    text label? filters=trim
  
    // Semantic definition of what this lens captures — injected into AI context.
    text description? filters=trim
  
    // The order in which the lens should be displayed.
    int display_order?
  
    // The type of actor associated with this lens.
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
  
    // Stores which template was applied when the row was created (e.g., customer-v1).
    text template_key? filters=trim
  
    // Stores the AI role instructions for this actor type, injected into agent context.
    text role_prompt? filters=trim
  
    // Describes who this specific actor persona is.
    text persona_description? filters=trim
  
    // The actor's overarching Job-to-be-Done across the entire journey.
    text primary_goal? filters=trim
  
    // Fixed limitations this actor brings (e.g., schedule, access, budget).
    text standing_constraints? filters=trim
  
    // FK to the journey map that acts as this AI agent's operating manual.
    // When set on an ai_agent lens, the Orchestrator delegates execution to this map
    // instead of generating text output directly. Null for all non-ai_agent lenses.
    int agent_map_id? {
      table = "journey_map"
    }
  
    // ── Ring 2: Cost rate fields (LA-2) ──────────────────────────────────────
    // The actor's labor cost rate used in leakage calculations.
    // Example: 30.00 (dollars per hour)
    decimal cost_rate_value?
  
    // The unit that cost_rate_value is expressed in.
    enum cost_rate_unit? {
      values = ["per_minute", "per_hour", "per_day", "per_week", "per_event"]
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "journey_map", op: "asc"}
        {name: "updated_at", op: "desc"}
      ]
    }
    {
      type : "btree|unique"
      field: [
        {name: "journey_map", op: "asc"}
        {name: "key", op: "asc"}
        {name: "display_order", op: "asc"}
      ]
    }
  ]
}