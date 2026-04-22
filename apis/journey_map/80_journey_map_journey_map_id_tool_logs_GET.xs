// Returns agent_tool_log records for a specific turn_id within a journey map.
// Used for debugging: shows the exact sequence of tool calls the agent made,
// what inputs were passed, and what each tool returned (including skipped cells).
query "journey_map/{journey_map_id}/tool-logs" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text turn_id filters=trim
    int conversation_id?
  }

  stack {
    // Validate journey map exists and belongs to the caller
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    // Optional: validate conversation belongs to this map
    var $conversation_valid {
      value = true
    }
  
    conditional {
      if ($input.conversation_id != null) {
        db.get agent_conversation {
          field_name = "id"
          field_value = $input.conversation_id
        } as $conversation
      
        conditional {
          if ($conversation == null || $conversation.journey_map != $input.journey_map_id) {
            var.update $conversation_valid {
              value = false
            }
          }
        }
      }
    }
  
    precondition ($conversation_valid) {
      error_type = "inputerror"
      error = "Conversation does not belong to this journey map"
    }
  
    // Fetch tool log records for the given turn_id, scoped to this journey map
    db.query agent_tool_log {
      where = $db.agent_tool_log.journey_map == $input.journey_map_id && $db.agent_tool_log.turn_id == $input.turn_id
      sort = {execution_order: "asc", created_at: "asc"}
      return = {type: "list"}
    } as $tool_calls
  }

  response = {
    journey_map_id: $input.journey_map_id
    turn_id       : $input.turn_id
    count         : $tool_calls|count
    tool_calls    : $tool_calls
  }
}