// MCP server — Journey Map tools
// Exposes journey map AI capabilities to enterprise AI agents, CRMs, and
// ticket systems via the Model Context Protocol.
// US-BIM-07
mcp_server "journey_map" {
  instructions = "Use these tools to build and inspect journey maps on behalf of users. Always pass a valid journey_map_id. The build_journey_map tool runs the AI builder autonomously and returns when complete, stalled, or at max_turns."
  tags = ["journey_map", "ai"]
  tools = [{name: "build_journey_map"}]
}
