// Edit journey_map record
query "journey_map/{journey_map_id}" verb=PATCH {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
    dblink {
      table = "journey_map"
    }
  }

  stack {
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = `$input|pick:($raw_input|keys)`|filter_null|filter_empty_text
    } as $model
  }

  response = $model
}