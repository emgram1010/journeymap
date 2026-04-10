// Update journey_stage record
query "journey_stage/{journey_stage_id}" verb=PUT {
  api_group = "journey-map"

  input {
    int journey_stage_id? filters=min:1
    dblink {
      table = "journey_stage"
    }
  }

  stack {
    db.edit journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
      data = {
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