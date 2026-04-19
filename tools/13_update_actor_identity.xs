// Writes actor identity fields (persona, goal, constraints) to a lens row.
// Resolves the lens by lens_key within the journey map. Partial updates allowed.
tool update_actor_identity {
  instructions = """
      Use this tool to populate the actor identity profile on a row (lens) of the journey map.
      Identity fields describe WHO the actor is at the lens level — not stage-specific data.
    
      Fields:
      - persona_description: Who this actor is — their role, background, and context
      - primary_goal: The overarching outcome they are trying to achieve in this journey
      - standing_constraints: Ongoing limitations, policies, or restrictions that always apply
    
      Identify the lens by lens_key. Do NOT pass lens IDs.
      Provide only the fields you have information for — other fields are left unchanged.
    
      When to use:
      - When the user describes who the actor is (persona_description)
      - When the user states the actor's goal (primary_goal)
      - When the user mentions standing limitations or constraints (standing_constraints)
      - Proactively after gathering enough context from the interview
    
      Input:
      - journey_map_id: The ID of the journey map
      - lens_key: The key of the target lens (e.g. 'customer', 'driver', 'engineer')
      - persona_description: (optional) text
      - primary_goal: (optional) text
      - standing_constraints: (optional) text
      - conversation_id: (optional) for tool trace logging
      - turn_id: (optional) for tool trace logging
    
      Response shape:
      {
        applied: true/false,
        lens: { id, lens_key, label, persona_description, primary_goal, standing_constraints },
        skip_reason: null | 'not_found' | 'nothing_to_write'
      }
    """

  input {
    int journey_map_id filters=min:1
    int conversation_id?
    text turn_id?
    text lens_key filters=trim
    text persona_description?
    text primary_goal?
    text standing_constraints?
  }

  stack {
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.lens_key
      return = {type: "single"}
    } as $lens
  
    var $result {
      value = {applied: false, lens: null, skip_reason: "not_found"}
    }
  
    conditional {
      if ($lens == null) {
        var.update $result {
          value = {applied: false, lens: null, skip_reason: "not_found"}
        }
      }
    }
  
    conditional {
      if ($lens != null) {
        // Check there is at least one field to write
        var $has_data {
          value = false
        }
      
        conditional {
          if ($input.persona_description != null && $input.persona_description != "") {
            var.update $has_data {
              value = true
            }
          }
        }
      
        conditional {
          if ($input.primary_goal != null && $input.primary_goal != "") {
            var.update $has_data {
              value = true
            }
          }
        }
      
        conditional {
          if ($input.standing_constraints != null && $input.standing_constraints != "") {
            var.update $has_data {
              value = true
            }
          }
        }
      
        conditional {
          if ($has_data == false) {
            var.update $result {
              value = {
                applied    : false
                lens       : null
                skip_reason: "nothing_to_write"
              }
            }
          }
        }
      
        conditional {
          if ($has_data) {
            // Build patch object with only provided fields
            var $patch_data {
              value = {}|set:"updated_at":"now"
            }
          
            conditional {
              if ($input.persona_description != null && $input.persona_description != "") {
                var.update $patch_data {
                  value = $patch_data
                    |set:"persona_description":$input.persona_description
                }
              }
            }
          
            conditional {
              if ($input.primary_goal != null && $input.primary_goal != "") {
                var.update $patch_data {
                  value = $patch_data
                    |set:"primary_goal":$input.primary_goal
                }
              }
            }
          
            conditional {
              if ($input.standing_constraints != null && $input.standing_constraints != "") {
                var.update $patch_data {
                  value = $patch_data
                    |set:"standing_constraints":$input.standing_constraints
                }
              }
            }
          
            db.patch journey_lens {
              field_name = "id"
              field_value = $lens.id
              data = $patch_data
            } as $updated_lens
          
            var.update $result {
              value = {
                applied    : true
                lens       : {
                  id                  : $updated_lens.id
                  lens_key            : $input.lens_key
                  label               : $updated_lens.label
                  persona_description : $updated_lens.persona_description
                  primary_goal        : $updated_lens.primary_goal
                  standing_constraints: $updated_lens.standing_constraints
                }
                skip_reason: null
              }
            }
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
            tool_name     : "update_actor_identity"
            tool_category : "write"
            input_summary : "lens: " ~ $input.lens_key
            output_summary: $result.applied ? "Applied identity fields" : "Skipped: " ~ $result.skip_reason
          }
        } as $tool_log
      }
    }
  }

  response = $result
}