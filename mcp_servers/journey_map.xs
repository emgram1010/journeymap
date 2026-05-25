// MCP server — Journey Map tools
// Exposes journey map AI capabilities to enterprise AI agents, CRMs, and
// ticket systems via the Model Context Protocol.
// US-BIM-07 / Epic IL-0
mcp_server journey_map {
  canonical = "ju0Zh1JM"
  instructions = "Use these tools to build and inspect journey maps on behalf of users. Always pass a valid journey_map_id. The build_journey_map tool runs the AI builder autonomously and returns when complete, stalled, or at max_turns. Full operator flow: create_workspace → create_journey_map → scaffold_map → fill_cells → publish_map → get_map. Use list_maps to browse existing maps and search_maps for semantic discovery."
  tags = ["journey_map", "ai"]
  tools = [
    {name: "build_journey_map"}
    {name: "create_workspace"}
    {name: "create_journey_map"}
    {name: "scaffold_map"}
    {name: "fill_cells"}
    {name: "publish_map"}
    {name: "list_maps"}
    {name: "get_map"}
    {name: "search_maps"}
  ]
  guid = "Hin32z0HEnscqbQVs1kSquiHiQ4"
}