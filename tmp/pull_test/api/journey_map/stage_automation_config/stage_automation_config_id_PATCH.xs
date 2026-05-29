// Partially update a stage_automation_config record (authenticated, owner-scoped).
// Only mutable fields are patchable — journey_map and journey_stage are immutable.
// updated_at is refreshed on every successful call.
query "stage_automation_config/{stage_automation_config_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int stage_automation_config_id? filters=min:1
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
    db.get stage_automation_config {
      field_name = "id"
      field_value = $input.stage_automation_config_id
    } as $existing
  
    precondition ($existing != null) {
      error_type = "notfound"
      error = "Stage automation config not found"
    }
  
    precondition ($existing.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    // Patch only fields the caller provided; exclude the path param
    var $allowed_fields {
      value = [
        "trigger_type"
        "trigger_config"
        "action_type"
        "action_config"
        "exception_condition"
        "linked_map_id"
        "linked_map_link_type"
        "status"
      ]
    }
  
    var $patch_data {
      value = {}|set:"updated_at":"now"
    }
  
    foreach ($allowed_fields) {
      each as $field {
        var $field_value {
          value = $raw_input|get:$field
        }
      
        conditional {
          if ($field_value != null) {
            var.update $patch_data {
              value = $patch_data|set:$field:$field_value
            }
          }
        }
      }
    }
  
    db.patch stage_automation_config {
      field_name = "id"
      field_value = $input.stage_automation_config_id
      data = $patch_data
    } as $model
  }

  response = $model
  guid = "jUcWo5lAuVrQeFHdJzgD8yNpLSm"
}