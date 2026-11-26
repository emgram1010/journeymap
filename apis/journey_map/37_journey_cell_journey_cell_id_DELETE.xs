// Delete journey_cell record
query "journey_cell/{journey_cell_id}" verb=DELETE {
  api_group = "journey-map"

  input {
    int journey_cell_id? filters=min:1
  }

  stack {
    // REQ-1: a step's needs go with the step.
    function.run "req/delete_cell_needs" {
      input = {journey_cell_id: $input.journey_cell_id}
    } as $_needs_gone

    db.del journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
    }
  }

  response = null
}