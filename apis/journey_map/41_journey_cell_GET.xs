// Query journey_cell records scoped to a specific journey map.
// US-RES-4-05: journey_map_id is required — eliminates unbounded full-table read.
query journey_cell verb=GET {
  api_group = "journey-map"

  input {
    int journey_map? filters=min:1
  }

  stack {
    db.query journey_cell {
      where  = $db.journey_cell.journey_map == $input.journey_map
      return = {type: "list"}
    } as $model
  }

  response = $model
}