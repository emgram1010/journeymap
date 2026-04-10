// Add journey_map record
query journey_map verb=POST {
  api_group = "journey-map"

  input {
    dblink {
      table = "journey_map"
    }
  }

  stack {
    db.add journey_map {
      data = {
        created_at         : "now"
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