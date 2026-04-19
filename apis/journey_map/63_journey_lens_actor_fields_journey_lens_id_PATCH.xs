// Update actor identity fields on an existing journey lens row.
// Accepts any subset of the actor fields — only provided fields are written.
// Returns the updated journey_lens record.
query "journey_lens/actor_fields/{journey_lens_id}" verb=PATCH {
  api_group = "journey-map"

  input {
    int journey_lens_id? filters=min:1
    text label? filters=trim
    enum actor_type? {
      values = ["customer", "operations", "ai_agent", "dev", "custom"]
    }
  
    text template_key? filters=trim
    text role_prompt? filters=trim
    text persona_description? filters=trim
    text primary_goal? filters=trim
    text standing_constraints? filters=trim
  }

  stack {
    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $existing
  
    precondition ($existing != null) {
      error_type = "notfound"
      error = "Journey lens not found"
    }
  
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    // Build patch data from only the fields present in the request body.
    // journey_lens_id is excluded — it is a path param, not a data field.
    var $allowed_fields {
      value = [
        "label"
        "actor_type"
        "template_key"
        "role_prompt"
        "persona_description"
        "primary_goal"
        "standing_constraints"
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
  
    db.patch journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
      data = $patch_data
    } as $updated_lens
  }

  response = $updated_lens
}