// Rename a journey lens label with validation.
// Only the display label is updated; the canonical key is preserved so that
// machine targeting (cell identifiers, AI references) remains stable.
query "journey_lens/rename/{journey_lens_id}" verb=PATCH {
  api_group = "journey-map"

  input {
    int journey_lens_id? filters=min:1
    text label? filters=trim
  }

  stack {
    precondition ($input.label != null && $input.label != "") {
      error_type = "inputerror"
      error = "Lens label is required"
    }
  
    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $existing_lens
  
    precondition ($existing_lens != null) {
      error_type = "notfound"
      error = "Journey lens not found"
    }
  
    // Only update label and updated_at — key and display_order are intentionally untouched.
    db.edit journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
      data = {label: $input.label, updated_at: "now"}
    } as $journey_lens_patch
  
    precondition ($journey_lens_patch != null) {
      error = "Failed to update journey lens"
    }
  
    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $journey_lens
  
    db.patch journey_map {
      field_name = "id"
      field_value = $existing_lens.journey_map
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch_patch
  
    precondition ($journey_map_touch_patch != null) {
      error = "Failed to update journey map"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $existing_lens.journey_map
    } as $journey_map_touch
  }

  response = {
    lens                  : $journey_lens
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}