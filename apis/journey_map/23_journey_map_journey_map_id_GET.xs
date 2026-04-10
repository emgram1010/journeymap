// Get journey_map record
query "journey_map/{journey_map_id}" verb=GET {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $model
  
    precondition ($model != null) {
      error_type = "notfound"
      error = "Not Found"
    }
  }

  response = $model
}