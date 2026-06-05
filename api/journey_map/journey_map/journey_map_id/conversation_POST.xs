// Create a new conversation session for a journey map.
// Accepts an optional title (defaults to "New Conversation") and a required mode.
query "journey_map/{journey_map_id}/conversation" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text title? filters=trim
    enum mode? {
      values = ["interview", "chat", "orchestrator"]
    }
  
    // US-WE-05: set to true to store conversation as orchestrator mode (bypasses enum constraint)
    bool orchestrator_mode?
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
      error = "Mode is required (interview, chat, or orchestrator)"
    }
  
    // Resolve effective mode: orchestrator_mode=true stores as 'orchestrator' (US-WE-05)
    var $effective_mode {
      value = $input.mode
    }
  
    conditional {
      if ($input.orchestrator_mode) {
        var.update $effective_mode {
          value = "orchestrator"
        }
      }
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
      enforce_hidden_fields = false
      data = {
        created_at     : "now"
        journey_map    : $input.journey_map_id
        title          : $title
        mode           : $effective_mode
        last_message_at: "now"
      }
    } as $conversation
  }

  response = $conversation
  guid = "S3DbRSnuiUP33BUyCFtYtGlCc6k"
}