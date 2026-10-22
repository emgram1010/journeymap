// Delete a conversation session and cascade-delete all its messages.
// Validates the conversation belongs to the given journey map.
//
// US-SEC-1-04 (2026-10-18) — WAS AN OPEN DELETE, and the worst of the
// four conversation routes. No login, two guessable integers, and an
// account's entire AI conversation plus every message in it was gone,
// with nothing to restore it from.
//
// THE "DOES THE MAP EXIST" READ IS NOW THE OWNERSHIP CHECK — see
// endpoint 54's note. `journey/assert_map_owner` holds the rule for
// all eight row-touching endpoints in this group, and logs `rejected`
// with E-GOV-001 on a refusal (GOV-1), so an attempt on someone
// else's conversation leaves a record even though nothing is deleted.
//
// The cascade loops and deletes each message by its own id: `db.del`
// with field_name/field_value touches only the FIRST match, so a
// single delete-by-conversation would have orphaned every message
// after the first (CLAUDE.md).
query "journey_map/{journey_map_id}/conversation/{conversation_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    int conversation_id? filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor
  
    function.run "journey/assert_map_owner" {
      input = {
        journey_map_id   : $input.journey_map_id
        caller_account_id: $actor.account_id
        user_id          : $auth.id
        step             : "delete_conversation"
      }
    } as $guard
  
    db.get agent_conversation {
      field_name = "id"
      field_value = $input.conversation_id
    } as $conversation
  
    precondition ($conversation != null) {
      error_type = "notfound"
      error = "Conversation not found"
    }
  
    precondition ($conversation.journey_map == $input.journey_map_id) {
      error_type = "inputerror"
      error = "Conversation does not belong to this journey map"
    }
  
    // Cascade-delete all messages in this conversation
    db.query agent_message {
      where = $db.agent_message.conversation == $input.conversation_id
      return = {type: "list"}
    } as $messages
  
    foreach ($messages) {
      each as $msg {
        db.del agent_message {
          field_name = "id"
          field_value = $msg.id
        }
      }
    }
  
    // Delete the conversation record
    db.del agent_conversation {
      field_name = "id"
      field_value = $input.conversation_id
    }
  }

  response = {id: $input.conversation_id, deleted: true}
}