// Create a new conversation session for a journey map.
// Accepts an optional title (defaults to "New Conversation") and a required mode.
query "journey_map/{journey_map_id}/conversation" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text title? filters=trim
    enum mode? {
      values = ["interview", "chat"]
    }
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
  
    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    precondition ($input.mode != null) {
      error_type = "inputerror"
      error = "Mode is required (interview or chat)"
    }
  
    var $title {
      value = "New Conversation"
    }
  
    conditional {
      if ($input.title != null && $input.title != "") {
        var.update $title {
          value = $input.title
        }
      }
    }
  
    db.add agent_conversation {
      data = {
        created_at     : "now"
        journey_map    : $input.journey_map_id
        title          : $title
        mode           : $input.mode
        last_message_at: "now"
      }
    } as $conversation
  }

  response = $conversation
}