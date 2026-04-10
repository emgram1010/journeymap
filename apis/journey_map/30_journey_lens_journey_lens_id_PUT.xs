// Update journey_lens record
query "journey_lens/{journey_lens_id}" verb=PUT {
  api_group = "journey-map"

  input {
    int journey_lens_id? filters=min:1
    dblink {
      table = "journey_lens"
    }
  }

  stack {
    db.edit journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
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