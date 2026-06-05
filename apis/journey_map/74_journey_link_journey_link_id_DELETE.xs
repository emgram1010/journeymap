// Delete a Journey Link by ID (authenticated, owner-scoped).
query "journey_link/{journey_link_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_link_id? filters=min:1
  }

  stack {
    db.get journey_link {
      field_name = "id"
      field_value = $input.journey_link_id
    } as $existing
  
    precondition ($existing != null) {
      error_type = "notfound"
      error = "Journey Link not found"
    }
  
    precondition ($existing.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    db.del journey_link {
      field_name = "id"
      field_value = $input.journey_link_id
    }
  }

  response = {deleted: true, id: $input.journey_link_id}
}