// Rename a journey stage label with validation.
// Only the display label is updated; the canonical key is preserved so that
// machine targeting (cell identifiers, AI references) remains stable.
query "journey_stage/rename/{journey_stage_id}" verb=PATCH {
  api_group = "journey-map"

  input {
    int journey_stage_id? filters=min:1
    text label? filters=trim
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
  
    // Only update label and updated_at — key and display_order are intentionally untouched.
    db.edit journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
      data = {label: $input.label, updated_at: "now"}
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