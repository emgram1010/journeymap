// v2 — Stores individual messages within conversation threads.
// ── RES-3 Lifecycle classification ───────────────────────────────────────
// Growth class    : HIGH (every chat turn writes 2+ rows; content is JSON).
// Dominant window : active conversation (hours–days).
// Old rows read?  : Sometimes — historical conversation review.
// Retention       : 180 days (configurable via retention_policy table).
// Prune cadence   : daily 03:00 UTC (task: prune_agent_message).
// Payload budget  : content JSON should stay < 100KB per row (see RES-3-04).
table agent_message {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Reference to the parent conversation thread.
    int conversation? {
      table = "agent_conversation"
    }
  
    // The role of the message sender (e.g., system, user, assistant, tool).
    enum role? {
      values = ["system", "user", "assistant", "tool"]
    }
  
    // The journey interview mode active when this message was created.
    enum mode? {
      values = ["interview", "chat", "compare"]
    }
  
    // The content of the message, compatible with AI SDK.
    json content?
  
    // Agent thinking output (reasoning trace) from include_thoughts. Null for user messages.
    text thinking?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "conversation", op: "asc"}]}
    {
      type : "btree"
      field: [
        {name: "conversation", op: "asc"}
        {name: "created_at", op: "desc"}
      ]
    }
  ]

  tags = ["xano:quick-start"]
}