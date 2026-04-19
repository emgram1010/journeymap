// Delete journey_map record (authenticated, owner-scoped)
query "journey_map/{journey_map_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $existing
  
    precondition ($existing != null) {
      error_type = "notfound"
      error = "Not Found"
    }
  
    precondition ($existing.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    // Delete any journey_link rows where this map is the source or target
    db.query journey_link {
      where = $db.journey_link.source_map == $input.journey_map_id || $db.journey_link.target_map == $input.journey_map_id
      return = {type: "list"}
    } as $links
  
    foreach ($links) {
      each as $link {
        db.del journey_link {
          field_name = "id"
          field_value = $link.id
        }
      }
    }
  
    db.del journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    }
  }

  response = null
}