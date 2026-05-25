// MCP server — Journey Map tools
// Exposes journey map AI capabilities to enterprise AI agents, CRMs, and
// ticket systems via the Model Context Protocol.
// US-BIM-07 | Epic IL-0 | Epic SCN-MCP | Epic LM-1
mcp_server journey_map {
  canonical = "ju0Zh1JM"
  instructions = """
    Use these tools to create, scaffold, fill, publish, search, and link journey maps on behalf of users.

    ## Core Build Flow
    create_workspace → create_journey_map → scaffold_map → fill_cells → publish_map

    ## Read / Query
    get_map           — full map state (stages, lenses, cells, fill summary)
    list_maps         — browse maps; filter by architecture_id, intent, status
    search_maps       — natural language search across published maps (ai_summary + tags)

    ## Scenario Loop (clone → modify → compare)
    list_scenarios    — list all maps in an architecture; always call before clone_scenario
    clone_scenario    — deep-clone a map into a new scenario (stages + lenses + cells copied)
    compare_scenarios — side-by-side health scorecard for two maps

    ## Map Linking (exception / sub-journey / anti-journey wiring)
    link_map          — create a directed cell→map link; always call get_map first to find source_cell_id

    ## Autonomous Build
    build_journey_map — runs the AI builder end-to-end; returns when complete, stalled, or at max_turns

    ## Rules
    - Always pass a valid journey_map_id obtained from create_journey_map, list_maps, or search_maps.
    - publish_map must be called before compare_scenarios or link_map snapshot is included.
    - Never guess a source_cell_id — always read it from get_map cells[] matched by stage_key + lens_key.
  """
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
    {name: "list_scenarios"}
    {name: "clone_scenario"}
    {name: "compare_scenarios"}
    {name: "link_map"}
  ]
  guid = "Hin32z0HEnscqbQVs1kSquiHiQ4"
}