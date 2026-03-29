// Edit journey_cell record
query "journey_cell/{journey_cell_id}" verb=PATCH {
  api_group = "journey-map"

  input {
    int journey_cell_id? filters=min:1
    dblink {
      table = "journey_cell"
    }
  }

  stack {
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    db.patch journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
      data = `$input|pick:($raw_input|keys)`|filter_null|filter_empty_text
    } as $model
  }

  response = $model
}