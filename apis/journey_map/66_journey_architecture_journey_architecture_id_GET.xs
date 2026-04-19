// Get a single Journey Architecture by ID (authenticated, owner-scoped).
query "journey_architecture/{journey_architecture_id}" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
  }

  stack {
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $model
  
    precondition ($model != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    precondition ($model.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  }

  response = $model
}