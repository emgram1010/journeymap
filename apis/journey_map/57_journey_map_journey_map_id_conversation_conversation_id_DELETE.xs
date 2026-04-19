// Delete a conversation session and cascade-delete all its messages.
// Validates the conversation belongs to the given journey map.
query "journey_map/{journey_map_id}/conversation/{conversation_id}" verb=DELETE {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
    int conversation_id? filters=min:1
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