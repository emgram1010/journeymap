// v2.1 — Records one row per agent turn — the orchestrator-level log.
// Complements agent_tool_log (per-tool) with a per-turn summary:
// how long the turn took, how many tools fired, cells written, final status.
table agent_turn_log {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // The conversation this turn belongs to.
    int conversation? {
      table = "agent_conversation"
    }
  
    // The journey map being worked on.
    int journey_map? {
      table = "journey_map"
    }
  
    // Groups this turn with its tool logs in agent_tool_log.
    text turn_id?
  
    // interview or chat
    enum mode? {
      values = ["interview", "chat"]
    }
  
    // First 200 chars of the user message for quick scanning.
    text user_message_preview?
  
    // First 200 chars of the assistant reply for quick scanning.
    text reply_preview?
  
    // How many tools the agent called this turn.
    int tool_count?
  
    // How many cells were written/changed this turn.
    int cells_written?
  
    // Turn outcome.
    enum status? {
      values = ["success", "error", "empty_reply"]
    }
  
    // Populated when status = error.
    text error_message?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "conversation", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map", op: "asc"}]}
    {type: "btree", field: [{name: "turn_id", op: "asc"}]}
    {type: "btree", field: [{name: "status", op: "asc"}]}
  ]
}