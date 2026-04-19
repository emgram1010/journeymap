// Delete an individual message from a conversation.
// Validates the message belongs to a conversation owned by the given journey map.
// Recalculates last_message_at on the parent conversation after deletion.
query "journey_map/{journey_map_id}/conversation/{conversation_id}/message/{message_id}" verb=DELETE {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
    int conversation_id? filters=min:1
    int message_id? filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
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
  
    db.get agent_message {
      field_name = "id"
      field_value = $input.message_id
    } as $message
  
    precondition ($message != null) {
      error_type = "notfound"
      error = "Message not found"
    }
  
    precondition ($message.conversation == $input.conversation_id) {
      error_type = "inputerror"
      error = "Message does not belong to this conversation"
    }
  
    // Delete the message
    db.del agent_message {
      field_name = "id"
      field_value = $input.message_id
    }
  
    // Recalculate last_message_at from remaining messages
    db.query agent_message {
      where = $db.agent_message.conversation == $input.conversation_id
      sort = {created_at: "desc"}
      return = {type: "list"}
    } as $remaining_messages
  
    var $new_last_message_at {
      value = null
    }
  
    conditional {
      if (($remaining_messages|count) > 0) {
        var $latest_msg {
          value = $remaining_messages|first
        }
      
        var.update $new_last_message_at {
          value = $latest_msg.created_at
        }
      }
    }
  
    db.patch agent_conversation {
      field_name = "id"
      field_value = $input.conversation_id
      data = {last_message_at: $new_last_message_at}
    } as $updated_conversation
  }

  response = {id: $input.message_id, deleted: true}
}