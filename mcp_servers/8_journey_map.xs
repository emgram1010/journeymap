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
      get_slice         — targeted read of a single stage column, lens row, or individual cell
      get_gaps          — find all empty cells; ranked by density to drive interview targeting
      list_maps         — browse maps; filter by architecture_id, intent, status, map_level
      search_maps       — natural language search across published maps (ai_summary + tags); filter by map_level
    
      ## Scenario Loop (clone → edit → compare)
      list_scenarios    — list all maps in an architecture; always call before clone_scenario
      clone_scenario    — deep-clone a map into a new scenario (stages + lenses + cells copied)
      update_cell       — write content into a single cell by stage_key + lens_key on the clone
      batch_update      — write improvements to multiple cells in one call; respects locked/confirmed
      publish_map       — must be called on the clone before compare_scenarios
      compare_scenarios — side-by-side health scorecard for two maps
    
      ## Map Linking (exception / sub-journey / anti-journey wiring)
      link_map          — create a directed cell→map link; always call get_map first to find source_cell_id
    
      ## Stage Contract (goal + actor ownership per stage)
      update_stage_contract — set or clear stage_goal and primary_actor_lens on a stage; always call get_map first to find journey_stage_id and lens keys
    
      ## Map Settings
      update_journey_settings — write map-level context fields (intent, primary_actor, journey_scope, start_point,
                                end_point, duration, success_metrics, key_stakeholders, dependencies,
                                pain_points_summary, opportunities, version, measurement_frequency,
                                measurement_period_label). Use intent to set or correct sop|automation|hybrid
                                after map creation. Call after create_journey_map.
    
      ## Actor Identity & AI Agent Wiring
      update_actor_identity — write persona_description, primary_goal, standing_constraints, and agent_map_id on a lens row. Use agent_map_id to wire an ai_agent lens to its sub-journey operating manual (the map that runs when the Orchestrator delegates to this actor). Always resolve lens_key from get_map before calling.
    
      ## Autonomous Build
      build_journey_map — runs the AI builder end-to-end; returns when complete, stalled, or at max_turns
    
      ## Leakage Analysis (Intelligence Layer — Ring 2)
      calculate_leakage — compute per-event, monthly, annual, and 3-year cost of inaction for an L3 atomic map.
                          Requires time_duration on cells and cost_rate on actor lenses. Guard: only valid for
                          map_level='atomic'. Returns incomplete_cells[] when fields are missing.
                          Always verify map_level before calling — use list_maps with map_level='atomic' to find eligible maps.
    
      ## CRUD Pre-Flight Protocol
      Before executing any Create, Update, or Delete operation, follow this sequence:
    
      **Step 1 — Read first**
      Always call get_map (or list_maps / search_maps to locate the map first) before calling
      fill_cells, update_cell, batch_update, scaffold_map, clone_scenario, or update_stage_contract.
      This gives you the current structure, stage keys, lens keys, fill state, and locked/confirmed
      cells — ground truth required before touching anything.
    
      **Step 2 — Assess ambiguity**
      Using the map state, check whether the requested operation is fully specified:
      - Is the target stage or lens unambiguous, or could it match multiple candidates?
      - Are target cells already filled — will this overwrite content the user did not intend to change?
      - Is the scope (single cell, full stage, full lens, full map) clear from the request?
    
      **Step 3 — Clarify before writing (if needed)**
      If anything in Step 2 is ambiguous, surface ONE question to the caller before proceeding.
      Reference actual stage or lens names from the map state you read. Never assume scope that
      could lead to unintended overwrites.
    
      **Step 4 — Act**
      Once the map is read and intent is clear, proceed with the CRUD operation.
    
      ## Rules
      - Always pass a valid journey_map_id obtained from create_journey_map, list_maps, or search_maps.
      - publish_map must be called before compare_scenarios or link_map snapshot is included.
      - Never guess a source_cell_id — always read it from get_map cells[] matched by stage_key + lens_key.
      - Scenario edit loop: clone_scenario → update_cell/batch_update → publish_map → compare_scenarios.
      - calculate_leakage is only valid on map_level='atomic' maps — guard enforced server-side.
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
    {name: "get_slice"}
    {name: "get_gaps"}
    {name: "search_maps"}
    {name: "update_journey_settings"}
    {name: "list_scenarios"}
    {name: "clone_scenario"}
    {name: "update_cell"}
    {name: "batch_update"}
    {name: "compare_scenarios"}
    {name: "link_map"}
    {name: "update_stage_contract"}
    {name: "update_actor_identity"}
    {name: "calculate_leakage"}
  ]
}