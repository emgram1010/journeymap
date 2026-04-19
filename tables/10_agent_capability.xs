// v2.1 — Registry of non-matrix AI capabilities that the agent discovers at runtime.
// Adding a row makes the capability available; setting enabled=false removes it.
table agent_capability {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Unique identifier key for this capability.
    text key? filters=trim
  
    // Human-readable label for the capability.
    text label? filters=trim
  
    // The name of the agent tool that implements this capability.
    text tool_name? filters=trim
  
    // Markdown instructions injected into the agent's system prompt when enabled.
    text instructions? filters=trim
  
    // Whether this capability is currently active.
    bool enabled?
  
    // JSON schema describing the inputs this capability accepts (optional).
    json input_schema?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "gin", field: [{name: "xdo", op: "jsonb_path_op"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "key", op: "asc"}]}
    {type: "btree", field: [{name: "enabled", op: "asc"}]}
  ]
}