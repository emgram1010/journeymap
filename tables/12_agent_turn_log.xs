// v3.0 — Records one row per agent turn — the orchestrator-level log.
// Sentinel pattern: written BEFORE the LLM call (status=in_progress), patched after.
// Complements agent_tool_log (per-tool) with a per-turn summary including
// timing, token usage, hallucination signals, and logging tier.
table agent_turn_log {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    // Written at sentinel time (before LLM call). Enables orphan turn detection.
    timestamp started_at?


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

    // interview, chat, orchestrator, or builder
    enum mode? {
      values = ["interview", "chat", "orchestrator", "builder"]
    }

    // Logging verbosity applied to this turn.
    // full = builder_mode (payloads captured), summary = chat/interview, minimal = S2S/orchestrator
    enum log_tier? {
      values = ["full", "summary", "minimal"]
    }


    // First 200 chars of the user message for quick scanning.
    text user_message_preview?

    // First 200 chars of the assistant reply for quick scanning.
    text reply_preview?

    // How many tools the agent called this turn.
    int tool_count?

    // How many cells were written/changed this turn.
    int cells_written?

    // LLM wall time in milliseconds (patched after agent run completes).
    int duration_ms?

    // Token usage from the agent run result (nullable — may be absent on error).
    int tokens_input?
    int tokens_output?

    // SHA-256 hash of the system prompt injected this turn.
    // Allows detecting when context changed without storing the full 50KB prompt.
    text system_prompt_hash?

    // Turn outcome. in_progress = sentinel written, not yet completed.
    enum status? {
      values = ["in_progress", "success", "error", "empty_reply"]
    }

    // Populated when status = error.
    text error_message?

    // True if the async or post-turn log write failed (user was unaffected).
    bool log_write_failed?

    // Rolled-up hallucination risk level for this turn.
    enum hallucination_risk? {
      values = ["none", "low", "medium", "high"]
    }

    // Array of detected hallucination signal objects (JSON).
    // Shape: [{ type, severity, detail, auto_flagged }]
    json hallucination_signals?

    // HUX-01: Set to true when a user explicitly flags this reply as incorrect.
    bool flagged_by_user?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "started_at", op: "desc"}]}
    {type: "btree", field: [{name: "conversation", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map", op: "asc"}]}
    {type: "btree", field: [{name: "turn_id", op: "asc"}]}
    {type: "btree", field: [{name: "status", op: "asc"}]}
    {type: "btree", field: [{name: "hallucination_risk", op: "asc"}]}
  ]
  guid = "c3AP3NHYuV1QVE9uNbDWafVWjtQ"
}