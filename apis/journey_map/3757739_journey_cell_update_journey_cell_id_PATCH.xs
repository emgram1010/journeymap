// Update a single journey cell's content, status, and/or lock state.
query "journey_cell/update/{journey_cell_id}" verb=PATCH {
  api_group = "journey-map"

  input {
    int journey_cell_id? filters=min:1
    text content? filters=trim
    enum status? {
      values = ["open", "draft", "confirmed"]
    }
  
    bool is_locked?
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
  
    precondition (($raw_input|keys|count) > 0) {
      error = "Provide at least one of content, status, or is_locked"
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
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}