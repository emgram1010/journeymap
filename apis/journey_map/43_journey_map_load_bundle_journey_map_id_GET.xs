// v2 — Load a fully hydrated journey map bundle for Prototype 2. (authenticated, owner-scoped)
query "journey_map/load_bundle/{journey_map_id}" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    var $conversation {
      value = null
    }
  
    var $messages {
      value = []
    }
  
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
  
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $lenses
  
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $cells
  
    db.query agent_conversation {
      where = $db.agent_conversation.journey_map == $input.journey_map_id
      sort = {last_message_at: "desc"}
      return = {type: "list"}
    } as $conversations
  
    conditional {
      if (($conversations|count) > 0) {
        var.update $conversation {
          value = $conversations|first
        }
      }
    }
  
    conditional {
      if ($conversation != null) {
        db.query agent_message {
          where = $db.agent_message.conversation == $conversation.id
          sort = {created_at: "asc"}
          return = {type: "list"}
        } as $messages_for_conversation
      
        var.update $messages {
          value = $messages_for_conversation
        }
      }
    }
  }

  response = {
    journey_map : $journey_map
    stages      : $stages
    lenses      : $lenses
    cells       : $cells
    conversation: $conversation
    messages    : $messages
  }
}