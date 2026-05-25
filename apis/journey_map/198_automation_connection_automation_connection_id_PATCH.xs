// Partially update an automation_connection (authenticated, owner-scoped).
// Use to update label, webhook_url, provider, or status (pause/resume/re-activate).
// updated_at is refreshed on every successful call.
query "automation_connection/{automation_connection_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int automation_connection_id? filters=min:1
    text label? filters=trim
    text webhook_url? filters=trim
    enum provider? {
      values = ["n8n", "make", "zapier", "custom"]
    }
  
    // Set to "paused" to stop receiving pushes. Set to "active" to resume.
    // "error" is set by the system on failed pushes — user can reset to "active" to retry.
    enum status? {
      values = ["active", "paused", "error"]
    }
  }

  stack {
    db.get automation_connection {
      field_name = "id"
      field_value = $input.automation_connection_id
    } as $existing
  
    precondition ($existing != null) {
      error_type = "notfound"
      error = "Automation connection not found"
    }
  
    precondition ($existing.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    var $allowed_fields {
      value = ["label", "webhook_url", "provider", "status"]
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
  
    // If re-activating from error, clear last_error_message
    conditional {
      if (($raw_input|get:"status") == "active" && $existing.status == "error") {
        var.update $patch_data {
          value = $patch_data|set:"last_error_message":null
        }
      }
    }
  
    db.patch automation_connection {
      field_name = "id"
      field_value = $input.automation_connection_id
      data = $patch_data
    } as $model
  }

  response = $model
}