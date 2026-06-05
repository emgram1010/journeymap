// Triggers a full multi-turn AI build of a journey map via the build_full endpoint.
// Designed for MCP callers and external agents that need headless map building.
// US-BIM-07
tool build_journey_map {
  instructions = "Use this tool to autonomously build or complete a journey map using AI. Pass journey_map_id. Optionally pass context to describe the domain. The build runs multiple AI turns until complete or stalled."

  input {
    // The numeric ID of the journey map to build.
    int journey_map_id filters=min:1
  
    // Optional domain context to guide the AI builder.
    text context?
  }

  stack {
    // Validate map exists before triggering the build
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    // Invoke the server-side build loop
    api.call "" verb=GET {
      api_group = ""
      input = {
        journey_map_id: $input.journey_map_id
        context       : $input.context
      }
    } as $build_result
  }

  response = $build_result
}