// Save smart AI behaviour settings for a journey map.
// Accepts any subset of the 7 settings fields — only provided fields are written (partial update).
// Returns the updated journey_map record.
query "journey_map/smart_ai_settings/{journey_map_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  
    // Enum settings
    enum interview_depth? {
      values = ["strategic", "discovery", "rapid_capture"]
    }
  
    enum insight_standard? {
      values = ["surface", "discovery", "deep_dive"]
    }
  
    enum lens_priority? {
      values = ["balanced", "customer", "operations", "engineering"]
    }
  
    // Boolean settings
    bool emotional_mapping?
  
    bool business_impact_framing?
    bool auto_confirm_writes?
    bool show_reasoning?
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $existing
  
    precondition ($existing != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    precondition ($existing.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    // Read current smart_ai_settings (or start from empty object if null)
    var $current_settings {
      value = $existing.smart_ai_settings
    }
  
    conditional {
      if ($current_settings == null) {
        var.update $current_settings {
          value = {}
        }
      }
    }
  
    // Merge only the fields present in the request
    var $allowed_fields {
      value = [
        "interview_depth"
        "insight_standard"
        "lens_priority"
        "emotional_mapping"
        "business_impact_framing"
        "auto_confirm_writes"
        "show_reasoning"
      ]
    }
  
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    var $merged_settings {
      value = $current_settings
    }
  
    foreach ($allowed_fields) {
      each as $field {
        var $field_value {
          value = $raw_input|get:$field
        }
      
        conditional {
          if ($field_value != null) {
            var.update $merged_settings {
              value = $merged_settings|set:$field:$field_value
            }
          }
        }
      }
    }
  
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {smart_ai_settings: $merged_settings, updated_at: "now"}
    } as $updated
  }

  response = $updated
}