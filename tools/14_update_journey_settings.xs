// Writes map-level context fields to a journey map (journey settings panel).
// Accepts any subset of the 11 settings fields — only provided fields are written.
tool update_journey_settings {
  instructions = """
      Use this tool to populate map-level context fields (the journey settings panel).
      These fields describe the journey at a high level — scope, actors, start/end points, success metrics, etc.
    
      Provide only the fields you have information for. Existing values are not overwritten unless you explicitly supply a new value.
    
      Fields available:
      - primary_actor: The main actor or persona this journey is mapped for
      - journey_scope: The overall scope or boundary of this journey (what's in and out of scope)
      - start_point: Where the journey begins (triggering event or first touchpoint)
      - end_point: Where the journey ends (final outcome or exit point)
      - duration: Typical time span for the full journey (e.g. '3-5 business days')
      - success_metrics: How success is measured for this journey
      - key_stakeholders: Key stakeholders or teams involved in this journey
      - dependencies: External systems, teams, or conditions the journey depends on
      - pain_points_summary: High-level summary of recurring pain points across the journey
      - opportunities: Key improvement opportunities identified
      - version: Version or iteration label for this journey map (e.g. 'v1.2 - Q2 2026')
    
      When to use:
      - When the user describes the overall journey scope, goals, or timeframe
      - When the user mentions who this journey is for (primary_actor)
      - When the user identifies key stakeholders or success metrics
      - Proactively as journey-level context emerges from the interview
    
      Input:
      - journey_map_id: The ID of the journey map
      - Any subset of the 11 fields above
      - conversation_id: (optional) for tool trace logging
      - turn_id: (optional) for tool trace logging
    
      Response shape:
      {
        applied: true/false,
        settings: { primary_actor, journey_scope, start_point, end_point, duration, success_metrics, key_stakeholders, dependencies, pain_points_summary, opportunities, version },
        skip_reason: null | 'nothing_to_write'
      }
    """

  input {
    int journey_map_id filters=min:1
    int conversation_id?
    text turn_id?
    text primary_actor?
    text journey_scope?
    text start_point?
    text end_point?
    text duration?
    text success_metrics?
    text key_stakeholders?
    text dependencies?
    text pain_points_summary?
    text opportunities?
    text version?
  }

  stack {
    var $result {
      value = {
        applied    : false
        settings   : null
        skip_reason: "nothing_to_write"
      }
    }
  
    // Build patch object — only include fields that were provided
    var $patch_data {
      value = {}|set:"updated_at":"now"
    }
  
    var $field_count {
      value = 0
    }
  
    conditional {
      if ($input.primary_actor != null && $input.primary_actor != "") {
        var.update $patch_data {
          value = $patch_data
            |set:"primary_actor":$input.primary_actor
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.journey_scope != null && $input.journey_scope != "") {
        var.update $patch_data {
          value = $patch_data
            |set:"journey_scope":$input.journey_scope
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.start_point != null && $input.start_point != "") {
        var.update $patch_data {
          value = $patch_data
            |set:"start_point":$input.start_point
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.end_point != null && $input.end_point != "") {
        var.update $patch_data {
          value = $patch_data|set:"end_point":$input.end_point
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.duration != null && $input.duration != "") {
        var.update $patch_data {
          value = $patch_data|set:"duration":$input.duration
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.success_metrics != null && $input.success_metrics != "") {
        var.update $patch_data {
          value = $patch_data
            |set:"success_metrics":$input.success_metrics
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.key_stakeholders != null && $input.key_stakeholders != "") {
        var.update $patch_data {
          value = $patch_data
            |set:"key_stakeholders":$input.key_stakeholders
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.dependencies != null && $input.dependencies != "") {
        var.update $patch_data {
          value = $patch_data
            |set:"dependencies":$input.dependencies
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.pain_points_summary != null && $input.pain_points_summary != "") {
        var.update $patch_data {
          value = $patch_data
            |set:"pain_points_summary":$input.pain_points_summary
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.opportunities != null && $input.opportunities != "") {
        var.update $patch_data {
          value = $patch_data
            |set:"opportunities":$input.opportunities
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($input.version != null && $input.version != "") {
        var.update $patch_data {
          value = $patch_data|set:"version":$input.version
        }
      
        var.update $field_count {
          value = $field_count + 1
        }
      }
    }
  
    conditional {
      if ($field_count > 0) {
        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = $patch_data
        } as $updated_map
      
        var.update $result {
          value = {
            applied    : true
            settings   : {
              primary_actor       : $updated_map.primary_actor
              journey_scope       : $updated_map.journey_scope
              start_point         : $updated_map.start_point
              end_point           : $updated_map.end_point
              duration            : $updated_map.duration
              success_metrics     : $updated_map.success_metrics
              key_stakeholders    : $updated_map.key_stakeholders
              dependencies        : $updated_map.dependencies
              pain_points_summary : $updated_map.pain_points_summary
              opportunities       : $updated_map.opportunities
              version             : $updated_map.version
            }
            skip_reason: null
          }
        }
      }
    }
  
    // Tool trace logging
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "update_journey_settings"
            tool_category : "write"
            input_summary : $field_count ~ " field(s)"
            output_summary: $result.applied ? "Applied " ~ $field_count ~ " settings field(s)" : "Skipped: nothing_to_write"
          }
        } as $tool_log
      }
    }
  }

  response = $result
}