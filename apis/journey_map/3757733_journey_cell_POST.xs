// Add journey_cell record
query journey_cell verb=POST {
  api_group = "journey-map"

  input {
    dblink {
      table = "journey_cell"
    }
  }

  stack {
    db.add journey_cell {
      data = {
        created_at     : "now"
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