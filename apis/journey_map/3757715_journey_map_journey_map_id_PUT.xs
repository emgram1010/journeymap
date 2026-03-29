// Update journey_map record
query "journey_map/{journey_map_id}" verb=PUT {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
    dblink {
      table = "journey_map"
    }
  }

  stack {
    db.edit journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {
        updated_at         : $input.updated_at
        title              : $input.title
        status             : $input.status
        owner_user         : $input.owner_user
        account_id         : $input.account_id
        last_interaction_at: $input.last_interaction_at
        settings           : $input.settings
      }
    } as $model
  }

  response = $model
}