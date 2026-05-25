// Update journey_stage label, stage_goal, and primary_actor_lens in one call.
// Validates label is non-empty; stage_goal and primary_actor_lens are optional and nullable.
// Also touches journey_map.updated_at and last_interaction_at.
query "journey_stage/update/{journey_stage_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_stage_id? filters=min:1
    text label? filters=trim
    text stage_goal? filters=trim
    text primary_actor_lens? filters=trim
  }

  stack {
    precondition ($input.label != null && $input.label != "") {
      error_type = "inputerror"
      error = "Stage label is required"
    }
  
    db.get journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
    } as $existing_stage
  
    precondition ($existing_stage != null) {
      error_type = "notfound"
      error = "Journey stage not found"
    }
  
    db.edit journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
      data = {
        label             : $input.label
        stage_goal        : $input.stage_goal
        primary_actor_lens: $input.primary_actor_lens
        updated_at        : "now"
      }
    } as $journey_stage
  
    db.patch journey_map {
      field_name = "id"
      field_value = $existing_stage.journey_map
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch_patch
  
    precondition ($journey_map_touch_patch != null) {
      error = "Failed to update journey map"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $existing_stage.journey_map
    } as $journey_map_touch
  }

  response = $journey_stage
    |set:"journey_map_updated_at":$journey_map_touch.updated_at
}