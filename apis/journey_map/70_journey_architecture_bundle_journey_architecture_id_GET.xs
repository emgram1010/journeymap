// Return a Journey Architecture and all its Journey Maps in a single response.
// journey_maps is always an array — empty array when no maps exist yet.
query "journey_architecture/bundle/{journey_architecture_id}" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
  }

  stack {
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $journey_architecture
  
    precondition ($journey_architecture != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    precondition ($journey_architecture.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    db.query journey_map {
      where = $db.journey_map.journey_architecture == $input.journey_architecture_id
      sort = {updated_at: "desc"}
      return = {type: "list"}
    } as $journey_maps
  
    db.query journey_link {
      where = $db.journey_link.journey_architecture == $input.journey_architecture_id
      return = {type: "list"}
    } as $journey_links
  }

  response = {
    journey_architecture: $journey_architecture
    journey_maps        : $journey_maps
    journey_links       : $journey_links
  }
}