// COP-3 story 03 — the messages of one copilot chat, oldest first, so the panel reopens where the
// person left off. Only a copilot conversation in the person's own account (anything else answers
// E-COP-042 "belongs to another business", the same as the chat endpoint).
query "copilot/conversation_messages" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int conversation_id?
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id"]
    } as $me

    var $account_id {
      value = $me|get:"account_id":0
    }

    db.query copilot_conversation {
      where = $db.copilot_conversation.agent_conversation_id == $input.conversation_id
      return = {type: "single"}
    } as $cc

    precondition ($input.conversation_id != 0 && ($cc|get:"account_id":0) == $account_id && $account_id != 0) {
      error_type = "inputerror"
      error = "That conversation belongs to another business. Pick it from that business, or start a new one here. (E-COP-042)"
    }

    db.query agent_message {
      where = $db.agent_message.conversation == $input.conversation_id
      sort = {created_at: "asc"}
      return = {type: "list"}
      output = ["id", "created_at", "role", "content"]
    } as $messages
  }

  response = {
    conversation_id        : $input.conversation_id
    journey_architecture_id: ($cc|get:"journey_architecture_id":0)
    messages               : $messages
  }
  tags = ["cop-3"]
}
