// v3.0 — Stores individual tool call traces within a single agent turn.
// Used by the transparency layer to show users what tools the AI called and why.
// Full payload fields (input_payload, output_payload) are only written when log_tier=full (builder_mode).
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

    // Category of tool: read, write, status, structure, workflow.
    enum tool_category? {
      values = ["read", "write", "status", "structure", "workflow"]
    }

    // Human-readable summary of the tool's inputs (e.g. "Stage 3 (Delivery)").
    text input_summary?

    // Human-readable summary of the tool's output (e.g. "2 cells written, 1 skipped").
    text output_summary?

    // Sequence number within the turn (1, 2, 3...).
    int execution_order?

    // Raw tool input JSON payload. Only populated when log_tier=full (builder_mode=true).
    // Capped at 10,240 characters. Use for replay and validation.
    json input_payload?

    // Raw tool output JSON payload. Only populated when log_tier=full (builder_mode=true).
    // Capped at 10,240 characters.
    json output_payload?

    // True when either input_payload or output_payload was truncated at 10KB.
    bool payload_truncated?

    // Per-tool execution time in milliseconds.
    int duration_ms?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
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
  guid = "gDKey1T3aTcQprwEmKBNQc1v9N4"
}