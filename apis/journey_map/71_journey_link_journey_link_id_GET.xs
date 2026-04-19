// Fetch a single Journey Link by ID (authenticated, owner-scoped).
query "journey_link/{journey_link_id}" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_link_id? filters=min:1
  }

  stack {
    db.get journey_link {
      field_name = "id"
      field_value = $input.journey_link_id
    } as $link
  
    precondition ($link != null) {
      error_type = "notfound"
      error = "Journey Link not found"
    }
  
    precondition ($link.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  }

  response = $link
}