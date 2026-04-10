// Add journey_stage record
query journey_stage verb=POST {
  api_group = "journey-map"

  input {
    dblink {
      table = "journey_stage"
    }
  }

  stack {
    db.add journey_stage {
      data = {
        created_at   : "now"
        updated_at   : $input.updated_at
        journey_map  : $input.journey_map
        key          : $input.key
        label        : $input.label
        display_order: $input.display_order
      }
    } as $model
  }

  response = $model
}