// Partially update a Journey Architecture (authenticated, owner-scoped).
// Only fields present in the request body are written; omitted fields are unchanged.
// updated_at is refreshed on every successful call.
query "journey_architecture/{journey_architecture_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
    text title? filters=trim
    text description? filters=trim
    enum status? {
      values = ["draft", "active", "archived"]
    }
  }

  stack {
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $existing
  
    precondition ($existing != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    precondition ($existing.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    // Patch only the fields the caller provided
    db.patch journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
      data = `$input|pick:($raw_input|keys)`|filter_null|filter_empty_text
    } as $model
  
    // Always refresh updated_at regardless of which fields were written
    db.patch journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
      data = {updated_at: "now"}
    } as $model
  }

  response = $model
}