// Stores high-level information about each customer journey map.
// v2: added nullable journey_architecture FK
table journey_map {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last update to the journey map.
    date updated_at?
  
    // The title of the journey map.
    text title? filters=trim
  
    // The current status of the journey map.
    enum status? {
      values = ["draft", "active", "archived"]
    }
  
    // Reference to the user who owns this journey map (optional).
    int owner_user? {
      table = "user"
    }
  
    // Reference to the account this journey map belongs to (optional).
    int account_id? {
      table = "account"
    }
  
    // Timestamp of the last interaction on the journey map (optional).
    date last_interaction_at?
  
    // JSON object for journey map settings (optional).
    json settings?
  
    // The main user or persona experiencing the journey.
    text primary_actor? filters=trim
  
    // A description of what the journey map covers.
    text journey_scope? filters=trim
  
    // The initial step or event of the journey.
    text start_point? filters=trim
  
    // The final step or outcome of the journey.
    text end_point? filters=trim
  
    // The estimated or actual length of the journey.
    text duration? filters=trim
  
    // Key performance indicators for measuring the journey's success.
    text success_metrics? filters=trim
  
    // Important individuals or groups involved in or affected by the journey.
    text key_stakeholders? filters=trim
  
    // Other systems, processes, or teams that the journey relies on.
    text dependencies? filters=trim
  
    // A summary of major difficulties or frustrations experienced during the journey.
    text pain_points_summary? filters=trim
  
    // Potential areas for improvement or new features identified within the journey.
    text opportunities? filters=trim
  
    // The version identifier for the journey map.
    text version? filters=trim
  
    // Per-map AI behaviour settings controlling interview depth, insight standard, lens priority,
    // emotional mapping, business impact framing, auto-confirm writes, and show reasoning.
    // Null = all defaults. Shape: { interview_depth, insight_standard, lens_priority,
    // emotional_mapping, business_impact_framing, auto_confirm_writes, show_reasoning }
    json smart_ai_settings?
  
    // Optional reference to the Journey Architecture this map belongs to.
    // Null means the map is standalone (not grouped under any architecture).
    int journey_architecture? {
      table = "journey_architecture"
    }
  
    // Optional reference to the journey map this map was cloned from.
    // Set when a scenario is created by cloning an existing map. Null for originals.
    int cloned_from_map_id? {
      table = "journey_map"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "gin", field: [{name: "xdo", op: "jsonb_path_op"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "owner_user", op: "asc"}
        {name: "account_id", op: "asc"}
        {name: "updated_at", op: "desc"}
        {name: "last_interaction_at", op: "desc"}
      ]
    }
    {
      type : "btree"
      field: [{name: "journey_architecture", op: "asc"}]
    }
  ]
}