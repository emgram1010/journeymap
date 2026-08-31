// v2 — Stores conversation threads for agents/chatbots.
table agent_conversation {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Reference to the journey map this thread belongs to.
    int journey_map? {
      table = "journey_map"
    }
  
    // The user who owns this conversation thread.
    int owner_user? {
      table = "user"
    }
  
    // The title or subject of the conversation.
    text title? filters=trim
  
    // The second journey map in a compare conversation (null for single-map conversations).
    int map_b_id? {
      table = "journey_map"
    }
  
    // The journey architecture this conversation is scoped to (set for compare conversations).
    int journey_architecture_id? {
      table = "journey_architecture"
    }
  
    // The current mode for the conversation thread.
    enum mode? {
      values = ["interview", "chat", "compare"]
    }
  
    // Timestamp of the last message in the conversation.
    timestamp last_message_at?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "journey_map", op: "asc"}]}
    {
      type : "btree"
      field: [{name: "last_message_at", op: "desc"}]
    }
  ]

  tags = ["xano:quick-start"]
}