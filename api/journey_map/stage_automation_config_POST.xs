// Create a stage_automation_config record (authenticated, owner-scoped).
// owner_user is inherited from the parent journey_map — never accepted from client.
// New records start as status="draft" unless the caller explicitly sets "confirmed".
query stage_automation_config verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    int journey_stage_id? filters=min:1
    enum trigger_type? {
      values = ["webhook", "inbound_status", "schedule", "manual"]
    }
  
    json trigger_config?
    enum action_type? {
      values = ["sms", "email", "http_post", "jobber_update", "slack", "none"]
    }
  
    json action_config?
    json exception_condition?
    int linked_map_id?
    enum linked_map_link_type? {
      values = ["exception", "anti_journey", "sub_journey"]
    }
  
    enum status? {
      values = ["draft", "confirmed", "disabled"]
    }
  }

  stack {
    // Validate required fields
    precondition ($input.journey_map_id != null) {
      error_type = "inputerror"
      error = "journey_map_id is required"
    }
  
    precondition ($input.journey_stage_id != null) {
      error_type = "inputerror"
      error = "journey_stage_id is required"
    }
  
    // Validate journey map ownership
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
  
    // Validate stage belongs to the map
    db.get journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
    } as $stage
  
    precondition ($stage != null) {
      error_type = "notfound"
      error = "Journey stage not found"
    }
  
    precondition ($stage.journey_map == $input.journey_map_id) {
      error_type = "inputerror"
      error = "journey_stage_id does not belong to this journey_map"
    }
  
    // Default status to draft if not provided
    var $effective_status {
      value = $input.status ?? "draft"
    }
  
    db.add stage_automation_config {
      enforce_hidden_fields = false
      data = {
        created_at          : "now"
        updated_at          : "now"
        journey_map         : $input.journey_map_id
        journey_stage       : $input.journey_stage_id
        trigger_type        : $input.trigger_type
        trigger_config      : $input.trigger_config
        action_type         : $input.action_type
        action_config       : $input.action_config
        exception_condition : $input.exception_condition
        linked_map_id       : $input.linked_map_id
        linked_map_link_type: $input.linked_map_link_type
        status              : $effective_status
        owner_user          : $auth.id
      }
    } as $config
  }

  response = $config
  guid = "hTbVn4kZsUpQeLGdIyfC7xMoKRw"
}