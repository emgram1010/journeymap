// v2.1 — Stores individual tool call traces within a single agent turn.
// Used by the transparency layer to show users what tools the AI called and why.
table agent_tool_log {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Reference to the conversation this tool call belongs to.
    int conversation? {
      table = "agent_conversation"
    }
  
    // Reference to the journey map being operated on.
    int journey_map? {
      table = "journey_map"
    }
  
    // Groups tool calls within a single agent turn.
    text turn_id?
  
    // Name of the tool that was called (e.g. "get_slice", "batch_update").
    text tool_name?
  
    // Category of tool: read, write, status, structure.
    enum tool_category? {
      values = ["read", "write", "status", "structure"]
    }
  
    // Human-readable summary of the tool's inputs (e.g. "Stage 3 (Delivery)").
    text input_summary?
  
    // Human-readable summary of the tool's output (e.g. "2 cells written, 1 skipped").
    text output_summary?
  
    // Sequence number within the turn (1, 2, 3...).
    int execution_order?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "gin", field: [{name: "xdo", op: "jsonb_path_op"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "conversation", op: "asc"}
        {name: "turn_id", op: "asc"}
      ]
    }
    {type: "btree", field: [{name: "turn_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map", op: "asc"}]}
  ]

  tags = ["xano:quick-start"]
}