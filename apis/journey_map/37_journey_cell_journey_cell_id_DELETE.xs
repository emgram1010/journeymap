// Delete journey_cell record
query "journey_cell/{journey_cell_id}" verb=DELETE {
  api_group = "journey-map"

  input {
    int journey_cell_id? filters=min:1
  }

  stack {
    db.del journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
    }
  }

  response = null
}