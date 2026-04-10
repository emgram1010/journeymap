// Delete journey_map record
query "journey_map/{journey_map_id}" verb=DELETE {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    db.del journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    }
  }

  response = null
}