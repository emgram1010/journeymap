// Add a journey stage and scaffold matching cells for all lenses in the map.
//
// ORD-2 (US-ORD-2-04): the work moved to journey/insert_stage, which the AI
// tools call too, so a column added by the AI and a column added from the
// matrix are now produced by the same code. This endpoint is the
// authenticated front door and does only what a function cannot:
//
//   1. proves the caller owns the map, and
//   2. decides whether an insert position was actually SENT.
//
// (2) has to happen here. An omitted optional int arrives as 0, and 0 is also
// the legitimate "insert at the very front" value, so the two are told apart
// by reading the raw request body — which only an endpoint has (CLAUDE.md).
// The function then receives an explicit -1 (append), 0 (first) or an id.
query "journey_stage/add/{journey_map_id}" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text label? filters=trim
    text stage_goal? filters=trim
    text primary_actor_lens? filters=trim

    // ORD-1: insert after this stage id; 0 = insert first; omit = append.
    int after_stage_id?
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $after_stage_id {
      value = -1
    }

    conditional {
      if ($raw_input|has:"after_stage_id") {
        var.update $after_stage_id {
          value = ($raw_input|get:"after_stage_id":0)|to_int
        }
      }
    }

    function.run "journey/insert_stage" {
      input = {
        journey_map_id    : $input.journey_map_id
        after_stage_id    : $after_stage_id
        label             : $input.label
        stage_goal        : $input.stage_goal
        primary_actor_lens: $input.primary_actor_lens
        user_id           : $auth.id
        account_id        : $journey_map.account_id
        step              : "insert_stage"
      }
    } as $added
  }

  response = {
    stage                 : $added.stage
    cells                 : $added.cells
    journey_map_updated_at: $added.journey_map_updated_at
  }
}
