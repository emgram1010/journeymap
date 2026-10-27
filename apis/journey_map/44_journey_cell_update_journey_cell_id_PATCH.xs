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
  
    // Ring 2 leakage math fields — time spent by the primary actor at this stage.
    decimal time_duration_value?
  
    enum time_duration_unit? {
      values = ["minutes", "hours", "days", "weeks"]
    }
  
    // Plan vs Actual fields (TL-6)
    decimal planned_duration?
  
    decimal actual_duration?
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
  
    // RATE-1 review #4 (D-R2) — an Items cell's actor_fields are written
    // only by its own endpoint (605), which runs validate_items_cell
    // (E-ITM-002..006), empties per_order lines and reconciles links.
    // Writing them here would skip all of that.
    var $writes_actor_fields {
      value = $raw_input|has:"actor_fields"
    }

    precondition ($cell_lens.template_key != "items-v1" || $writes_actor_fields == false) {
      error_type = "inputerror"
      error = "Edit an Items cell with the Items cell editor. (E-ITM-010)"
    }

    precondition (($raw_input|keys|count) > 0) {
      error = "Provide at least one of content, status, is_locked, or actor_fields"
    }

    // TIME-1 (US-TIME-1-04): duration fields are additive, optional, and only
    // checked when actually present in this PATCH — an omitted decimal input
    // arrives as 0, not null, so presence is read from $raw_input (the keys
    // the caller actually sent), never from the input value itself.
    var $has_duration_value {
      value = $raw_input|has:"time_duration_value"
    }

    var $has_duration_unit {
      value = $raw_input|has:"time_duration_unit"
    }

    var $has_planned {
      value = $raw_input|has:"planned_duration"
    }

    var $has_actual {
      value = $raw_input|has:"actual_duration"
    }

    precondition ($has_duration_value == false || $input.time_duration_value >= 0) {
      error_type = "inputerror"
      error = "Enter how long this takes as a number, like 15. (E-TIME-001)"
    }

    precondition ($has_planned == false || $input.planned_duration >= 0) {
      error_type = "inputerror"
      error = "Enter how long this takes as a number, like 15. (E-TIME-001)"
    }

    precondition ($has_actual == false || $input.actual_duration >= 0) {
      error_type = "inputerror"
      error = "Enter how long this takes as a number, like 15. (E-TIME-001)"
    }

    // time_duration_unit is an enum input, so an invalid unit is already
    // rejected by the framework before this stack runs (E-TIME-002). This
    // only catches the pairing: a value with no unit, or a unit with no value.
    precondition ($has_duration_value == $has_duration_unit) {
      error_type = "inputerror"
      error = "Add both a number and a unit, or leave both empty. (E-TIME-003)"
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
    time_duration_value   : $journey_cell.time_duration_value
    time_duration_unit    : $journey_cell.time_duration_unit
    planned_duration      : $journey_cell.planned_duration
    actual_duration       : $journey_cell.actual_duration
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}