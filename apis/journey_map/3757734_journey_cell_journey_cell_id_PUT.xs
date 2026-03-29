// Update journey_cell record
query "journey_cell/{journey_cell_id}" verb=PUT {
  api_group = "journey-map"

  input {
    int journey_cell_id? filters=min:1
    dblink {
      table = "journey_cell"
    }
  }

  stack {
    db.edit journey_cell {
      field_name = "id"
      field_value = $input.journey_cell_id
      data = {
        updated_at     : $input.updated_at
        journey_map    : $input.journey_map
        stage          : $input.stage
        lens           : $input.lens
        content        : $input.content
        status         : $input.status
        is_locked      : $input.is_locked
        change_source  : $input.change_source
        last_updated_at: $input.last_updated_at
      }
    } as $model
  }

  response = $model
}