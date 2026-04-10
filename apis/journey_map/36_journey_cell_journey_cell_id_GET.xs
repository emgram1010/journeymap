// Get journey_cell record
query "journey_cell/{journey_cell_id}" verb=GET {
  api_group = "journey-map"

  input {
    int journey_cell_id? filters=min:1
  }

  stack {
    db.get journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
    } as $model
  
    precondition ($model != null) {
      error_type = "notfound"
      error = "Not Found"
    }
  }

  response = $model
}