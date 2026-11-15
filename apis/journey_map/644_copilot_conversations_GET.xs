// COP-3 stories 02/03 — the copilot chats for ONE business in the signed-in person's account,
// newest first. Only conversations started from the copilot panel (copilot_conversation rows) —
// never the per-map chats. A business outside the account answers "not found" (E-COP-035).
query "copilot/conversations" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id?
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

    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.journey_architecture_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $arch

    precondition ($input.journey_architecture_id != 0 && ($arch|get:"account_id":0) == $account_id && $account_id != 0) {
      error_type = "notfound"
      error = "We couldn't find that business. (E-COP-035)"
    }

    db.query copilot_conversation {
      where = $db.copilot_conversation.account_id == $account_id && $db.copilot_conversation.journey_architecture_id == $input.journey_architecture_id
      return = {type: "list"}
      output = ["agent_conversation_id"]
    } as $marks

    var $conv_ids {
      value = [-1]
    }

    foreach ($marks) {
      each as $m {
        array.push $conv_ids {
          value = $m.agent_conversation_id
        }
      }
    }

    db.query agent_conversation {
      where = $db.agent_conversation.id in $conv_ids
      sort = {last_message_at: "desc"}
      return = {type: "list"}
      output = ["id", "title", "created_at", "last_message_at", "owner_user"]
    } as $conversations
  }

  response = {journey_architecture_id: $input.journey_architecture_id, conversations: $conversations}
  tags = ["cop-3"]
}
