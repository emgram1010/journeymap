// MCP server — Journey Map tools
// Exposes journey map AI capabilities to enterprise AI agents, CRMs, and
// ticket systems via the Model Context Protocol.
// Auth: X-Account-Key header (account-scoped API key, same pattern as incident_tracking.xs)
// US-BIM-07

mcp_server "journey_map" {

  // ── build_journey_map ─────────────────────────────────────────────────────
  // Triggers a full AI build of a journey map. Runs autonomously across
  // multiple turns until all cells are filled or max_turns is reached.
  // Returns when complete — does not stream. Poll /build_full if you need
  // progress; use this tool when you just need a done/partial/stalled result.
  mcp_tool "build_journey_map" {
    description = """
      Builds or completes a journey map using AI.
      Runs the Journey Map Assistant autonomously across multiple turns,
      filling all empty cells in the correct sequence (structure → actors →
      free-text lenses → insights).
      Returns when all cells are filled, the build stalls, or max_turns is reached.
      Returns: status (complete | partial | stalled), cells_filled,
               cells_remaining, progress_percentage, skipped_cells,
               and a per-turn tool_trace_summary.
    """

    input {
      // The numeric ID of the journey map to build.
      int journey_map_id filters=min:1

      // Optional domain context injected into the first build prompt.
      // Example: "B2B SaaS onboarding flow for mid-market customers"
      text context?

      // Maximum number of agent turns to run. Default: 8.
      int max_turns?
    }

    stack {
      // ── Auth: resolve account from API key ──
      precondition ($mcp_auth.account_id != null) {
        error_type = "unauthorized"
        error      = "Missing or invalid account API key"
      }

      // ── Resolve the map and verify it belongs to this account ──
      db.get journey_map {
        field_name  = "id"
        field_value = $input.journey_map_id
      } as $jm

      precondition ($jm != null) {
        error_type = "not_found"
        error      = "Journey map not found"
      }

      precondition ($jm.account_id == $mcp_auth.account_id) {
        error_type = "not_found"
        error      = "Journey map not found"
      }

      // ── Delegate to the server-side build loop endpoint ──
      api.call "journey_map/{journey_map_id}/build_full" verb=POST {
        api_group = "journey-map"
        path_params = {journey_map_id: $input.journey_map_id}
        input = {
          journey_map_id : $input.journey_map_id
          context        : $input.context
          max_turns      : $input.max_turns
        }
        auth_context = {account_id: $mcp_auth.account_id}
      } as $build_result
    }

    response = {
      status             : $build_result.status
      turns_used         : $build_result.turns_used
      cells_filled       : $build_result.cells_filled
      cells_remaining    : $build_result.cells_remaining
      progress_percentage: $build_result.progress_percentage
      skipped_cells      : $build_result.skipped_cells
      tool_trace_summary : $build_result.tool_trace_summary
      conversation_id    : $build_result.conversation_id
    }
  }

}
