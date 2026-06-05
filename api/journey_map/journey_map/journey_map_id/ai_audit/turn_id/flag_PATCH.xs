// HUX-01 — Flag a turn as hallucinated by the user.
// Writes flagged_by_user=true on the agent_turn_log row for the given turn_id.
// Auth-guarded: only the journey map owner may flag turns.
query "journey_map/{journey_map_id}/ai_audit/{turn_id}/flag" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id filters=min:1
    text turn_id filters=trim
  
    // Pass false to un-flag a previously flagged turn.
    bool flagged?=true
  }

  stack {
    // ── Auth + ownership guard ──
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
  
    // ── Find the turn log row ──
    db.query agent_turn_log {
      where = $db.agent_turn_log.journey_map == $input.journey_map_id && $db.agent_turn_log.turn_id == $input.turn_id
      return = {type: "single"}
    } as $turn
  
    precondition ($turn != null) {
      error_type = "notfound"
      error = "Turn not found"
    }
  
    // ── Patch the flag ──
    db.patch agent_turn_log {
      field_name = "id"
      field_value = $turn.id
      data = {flagged_by_user: $input.flagged}
    } as $patched
  
    var $result {
      value = {
        turn_id        : $input.turn_id
        flagged_by_user: $patched.flagged_by_user
      }
    }
  }

  response = $result
  guid = "hux01_flag_turn_v1"
}