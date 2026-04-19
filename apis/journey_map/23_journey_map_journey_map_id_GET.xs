// Get journey_map record (authenticated, owner-scoped)
query "journey_map/{journey_map_id}" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $model
  
    precondition ($model != null) {
      error_type = "notfound"
      error = "Not Found"
    }
  
    precondition ($model.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  }

  response = $model
}