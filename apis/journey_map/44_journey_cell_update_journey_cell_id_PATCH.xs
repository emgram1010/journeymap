// Update a single journey cell's content, status, and/or lock state.
// Validates the cell's stage and lens still exist to prevent stale-target writes.
query "journey_cell/update/{journey_cell_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_cell_id? filters=min:1
    text content? filters=trim
    enum status? {
      values = ["open", "draft", "confirmed"]
    }
  
    bool is_locked?
  
    // Structured actor-specific sub-fields — keyed by actor template (e.g. customer-v1).
    json actor_fields?
  }

  stack {
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    db.get journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
    } as $existing_cell
  
    precondition ($existing_cell != null) {
      error_type = "notfound"
      error = "Journey cell not found"
    }
  
    // Stale-target guard: verify the cell's stage and lens still exist.
    db.get journey_stage {
      field_name = "id"
      field_value = $existing_cell.stage
    } as $cell_stage
  
    db.get journey_lens {
      field_name = "id"
      field_value = $existing_cell.lens
    } as $cell_lens
  
    precondition ($cell_stage != null && $cell_lens != null) {
      error_type = "badrequest"
      error = "Cell target is stale — stage or lens has been deleted"
    }
  
    precondition (($raw_input|keys|count) > 0) {
      error = "Provide at least one of content, status, is_locked, or actor_fields"
    }
  
    db.patch journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
      data = `$input|pick:($raw_input|keys)`|filter_null
    } as $patched_cell
  
    db.patch journey_cell {
      field_name = "id"
      field_value = $patched_cell.id
      data = {
        updated_at     : "now"
        last_updated_at: "now"
        change_source  : "user"
      }
    } as $journey_cell
  
    db.patch journey_map {
      field_name = "id"
      field_value = $existing_cell.journey_map
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch_patch
  
    precondition ($journey_map_touch_patch != null) {
      error = "Failed to update journey map"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $existing_cell.journey_map
    } as $journey_map_touch
  }

  response = {
    id                    : $journey_cell.id
    created_at            : $journey_cell.created_at
    updated_at            : $journey_cell.updated_at
    journey_map           : $journey_cell.journey_map
    stage                 : $journey_cell.stage
    lens                  : $journey_cell.lens
    content               : $journey_cell.content
    status                : $journey_cell.status
    is_locked             : $journey_cell.is_locked
    change_source         : $journey_cell.change_source
    last_updated_at       : $journey_cell.last_updated_at
    actor_fields          : $journey_cell.actor_fields
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}