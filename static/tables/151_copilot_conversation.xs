// COP-3 stories 02/03 (2026-11-15) — marks an agent_conversation as a COPILOT chat about one
// business, so the copilot panel lists only its own conversations (never the per-map chats) and
// a conversation's business can never change after it starts. Side table: agent_conversation is
// not changed. Unique agent_conversation_id.
//
// GOV-1: S1 primary key; S2 created_at only (written once); S3 references declared and indexed;
// S6 unique natural key.
table copilot_conversation {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int agent_conversation_id? {
      table = "agent_conversation"
    }

    int account_id? {
      table = "account"
    }

    int journey_architecture_id? {
      table = "journey_architecture"
      description = "The one business this conversation is about. Never changes."
    }

    int started_by_user_id? {
      table = "user"
      description = "The person who started it."
    }

    int copilot_user_id? {
      table = "user"
      description = "The AI identity that answers in it."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "agent_conversation_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "started_by_user_id", op: "asc"}]}
    {type: "btree", field: [{name: "copilot_user_id", op: "asc"}]}
  ]
}
