// Partially update a Journey Link (authenticated, owner-scoped).
// Only link_type and label are patchable.
// source_cell and target_map are immutable — delete and recreate to change them.
// updated_at is refreshed on every successful call.
query "journey_link/{journey_link_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_link_id? filters=min:1
  
    // Only these two fields can be patched.
    enum link_type? {
      values = ["exception", "anti_journey", "sub_journey"]
    }
  
    text label? filters=trim
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
  
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    // Patch only fields the caller provided (excludes journey_link_id path param)
    db.patch journey_link {
      field_name = "id"
      field_value = $input.journey_link_id
      data = `$input|pick:($raw_input|keys)`|filter_null|filter_empty_text
    } as $model
  
    // Always refresh updated_at
    db.patch journey_link {
      field_name = "id"
      field_value = $input.journey_link_id
      data = {updated_at: "now"}
    } as $model
  }

  response = $model
}