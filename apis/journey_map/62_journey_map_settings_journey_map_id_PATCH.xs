// Save journey settings context fields for a journey map.
// Accepts any subset of the 11 context fields — only provided fields are written.
// Returns the updated journey_map record.
query "journey_map/settings/{journey_map_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text primary_actor? filters=trim
    text journey_scope? filters=trim
    text start_point? filters=trim
    text end_point? filters=trim
    text duration? filters=trim
    text success_metrics? filters=trim
    text key_stakeholders? filters=trim
    text dependencies? filters=trim
    text pain_points_summary? filters=trim
    text opportunities? filters=trim
    text version? filters=trim
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
  
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    // Build patch data from only the fields present in the request body.
    // journey_map_id is excluded — it is a path param, not a data field.
    var $allowed_fields {
      value = [
        "primary_actor"
        "journey_scope"
        "start_point"
        "end_point"
        "duration"
        "success_metrics"
        "key_stakeholders"
        "dependencies"
        "pain_points_summary"
        "opportunities"
        "version"
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
  
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = $patch_data
    } as $updated
  }

  response = $updated
}