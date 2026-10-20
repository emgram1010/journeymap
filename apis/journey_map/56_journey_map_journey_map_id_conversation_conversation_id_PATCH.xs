// Update conversation session metadata (title and/or mode).
// Validates the conversation belongs to the given journey map.
//
// US-SEC-1-04 (2026-10-18) — WAS AN OPEN WRITE. No login: anyone could
// retitle or re-mode any account's AI conversation.
//
// THE "DOES THE MAP EXIST" READ IS NOW THE OWNERSHIP CHECK — see
// endpoint 54's note. `journey/assert_map_owner` holds the rule for
// all eight row-touching endpoints in this group, and logs `rejected`
// with E-GOV-001 on a refusal (GOV-1).
query "journey_map/{journey_map_id}/conversation/{conversation_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    int conversation_id? filters=min:1
    text title? filters=trim
    enum mode? {
      values = ["interview", "chat"]
    }
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
        step             : "patch_conversation"
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
  
    // Reject empty/whitespace-only title when provided
    conditional {
      if ($input.title != null) {
        precondition ($input.title != "") {
          error_type = "inputerror"
          error = "Title cannot be empty"
        }
      }
    }
  
    // Build patch data with only provided fields
    var $patch_data {
      value = {}
    }
  
    conditional {
      if ($input.title != null && $input.title != "") {
        var.update $patch_data {
          value = $patch_data|set:"title":$input.title
        }
      }
    }
  
    conditional {
      if ($input.mode != null) {
        var.update $patch_data {
          value = $patch_data|set:"mode":$input.mode
        }
      }
    }
  
    db.patch agent_conversation {
      field_name = "id"
      field_value = $input.conversation_id
      data = $patch_data
    } as $updated_conversation
  
    precondition ($updated_conversation != null) {
      error = "Failed to update conversation"
    }
  }

  response = $updated_conversation
}