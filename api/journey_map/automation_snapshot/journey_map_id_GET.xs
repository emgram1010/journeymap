// Fetch the compiled automation snapshot for a journey map (authenticated, owner-scoped).
// Returns the latest version by default. Pass ?version=N to fetch a specific version.
// Consumed by n8n / Make.com to cache the full decision graph locally.
// Returns 404 if no snapshot exists yet (map published but automation not configured + compiled).
query "automation_snapshot/{journey_map_id}" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  
    // Optional: fetch a specific version. Omit for latest.
    int version?
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    // Fetch latest snapshot — list sorted desc, take first
    db.query automation_snapshot {
      where = $db.automation_snapshot.journey_map == $input.journey_map_id
      sort = {version: "desc"}
      return = {type: "list"}
    } as $snapshots
  
    precondition (($snapshots|count) > 0) {
      error_type = "notfound"
      error = "No automation snapshot found for this journey map. Configure automation and publish the map first."
    }
  }

  response = $snapshots|first
  guid = "nYgAs9pDxZvRhILeMjkH2cQrOBt"
}