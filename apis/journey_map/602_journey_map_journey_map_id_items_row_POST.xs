// ITEM-1 (US-ITEM-1-01) — Create the map's one Items row. Does only
// what a function cannot (proves the caller owns the map), same split
// as journey_stage/add (47) and journey_lens/add -- the actual work is
// journey/insert_stage-shaped, here items/ensure_items_row.
query "journey_map/{journey_map_id}/items-row" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text correlation_id? filters=trim
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

    function.run "items/ensure_items_row" {
      input = {
        journey_map_id: $input.journey_map_id
        user_id       : $auth.id
        account_id    : $journey_map.account_id
        correlation_id: $input.correlation_id
      }
    } as $created

    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch
  }

  response = {
    lens                  : $created.lens
    cells                 : $created.cells
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}
