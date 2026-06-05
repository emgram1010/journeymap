// List stage_automation_config records for a journey map (authenticated, owner-scoped).
// Returns draft + confirmed records by default. Pass include_disabled=true to include disabled.
query stage_automation_config verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    bool include_disabled?
  }

  stack {
    // Validate journey map exists and is owned by the caller
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
  
    conditional {
      if ($input.include_disabled) {
        db.query stage_automation_config {
          where = $db.stage_automation_config.journey_map == $input.journey_map_id && $db.stage_automation_config.owner_user == $auth.id
          sort = {created_at: "asc"}
          return = {type: "list"}
        } as $configs
      }
    
      else {
        db.query stage_automation_config {
          where = $db.stage_automation_config.journey_map == $input.journey_map_id && $db.stage_automation_config.owner_user == $auth.id && $db.stage_automation_config.status != "disabled"
          sort = {created_at: "asc"}
          return = {type: "list"}
        } as $configs
      }
    }
  }

  response = $configs
  guid = "gSaUm3hZrNqPdLFcHyeB6wJoKTv"
}