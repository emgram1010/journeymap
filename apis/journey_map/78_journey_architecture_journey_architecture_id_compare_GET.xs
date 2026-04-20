// Compare two scenarios within a Journey Architecture.
// Validates ownership and membership, then returns titles + dates for both maps.
// Scorecard data is fetched separately by the frontend (reuses existing scorecard endpoint).
query "journey_architecture/{journey_architecture_id}/compare" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
    int map_a?
    int map_b?
  }

  stack {
    // 1 — Validate architecture and ownership
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $arch
  
    precondition ($arch != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    precondition ($arch.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    // 2 — Validate required params
    precondition ($input.map_a != null) {
      error_type = "badrequest"
      error = "map_a is required"
    }
  
    precondition ($input.map_b != null) {
      error_type = "badrequest"
      error = "map_b is required"
    }
  
    precondition ($input.map_a != $input.map_b) {
      error_type = "badrequest"
      error = "Cannot compare a scenario to itself"
    }
  
    // 3 — Validate map_a belongs to this architecture
    db.get journey_map {
      field_name = "id"
      field_value = $input.map_a
    } as $map_a
  
    precondition ($map_a != null) {
      error_type = "notfound"
      error = "Scenario A not found"
    }
  
    precondition ($map_a.journey_architecture == $input.journey_architecture_id) {
      error_type = "accessdenied"
      error = "Scenario A does not belong to this architecture"
    }
  
    // 4 — Validate map_b belongs to this architecture
    db.get journey_map {
      field_name = "id"
      field_value = $input.map_b
    } as $map_b
  
    precondition ($map_b != null) {
      error_type = "notfound"
      error = "Scenario B not found"
    }
  
    precondition ($map_b.journey_architecture == $input.journey_architecture_id) {
      error_type = "accessdenied"
      error = "Scenario B does not belong to this architecture"
    }
  }

  response = {
    map_a: ```
      {
        id        : $map_a.id
        title     : $map_a.title
        updated_at: $map_a.updated_at
      }
      ```
    map_b: ```
      {
        id        : $map_b.id
        title     : $map_b.title
        updated_at: $map_b.updated_at
      }
      ```
  }
}