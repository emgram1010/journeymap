// Returns the 100 most recent agent turn logs for a journey map.
// Filter by conversation_id or status (success | error | empty_reply).
query "journey_map/{journey_map_id}/turn-logs" verb=GET {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
    int conversation_id?
    text status? filters=trim
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
  
    // ==? skips the condition when the value is null (ignore-if-null operator)
    db.query agent_turn_log {
      where = $db.agent_turn_log.journey_map == $input.journey_map_id && $db.agent_turn_log.conversation ==? $input.conversation_id && $db.agent_turn_log.status ==? $input.status
      sort = {created_at: "desc"}
      return = {type: "list", paging: {page: 1, per_page: 100}}
    } as $turns
  }

  response = {
    journey_map_id: $input.journey_map_id
    count         : $turns|count
    turns         : $turns
  }
}