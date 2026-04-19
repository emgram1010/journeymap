// Tests Epic 4 transparency features: tool trace logging, trace retrieval, and thinking persistence.
workflow_test ai_transparency {
  stack {
    // ── Setup: create a draft journey map ──
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      input = {title: "Transparency Test Map", status: "draft"}
    } as $draft
  
    var $journey_map_id {
      value = $draft.journey_map.id
    }
  
    // Create a conversation for the map
    api.call "journey_map/{journey_map_id}/conversation" verb=POST {
      api_group = "journey-map"
      input = {
        journey_map_id: $journey_map_id
        title         : "Trace Test Session"
        mode          : "interview"
      }
    } as $conv
  
    var $conversation_id {
      value = $conv.id
    }
  
    var $turn_id {
      value = "test_turn_001"
    }
  
    // ── US-TR-03: Verify tool logging — get_map_state ──
    tool.call get_map_state {
      input = {
        journey_map_id : $journey_map_id
        conversation_id: $conversation_id
        turn_id        : $turn_id
      }
    } as $map_state
  
    // Verify a trace row was created
    db.query agent_tool_log {
      where = $db.agent_tool_log.turn_id == $turn_id
      return = {type: "list"}
    } as $traces_after_1
  
    expect.to_equal ($traces_after_1|count) {
      value = 1
    }
  
    expect.to_equal ($traces_after_1[0].tool_name) {
      value = "get_map_state"
    }
  
    expect.to_equal ($traces_after_1[0].tool_category) {
      value = "read"
    }
  
    expect.to_equal ($traces_after_1[0].conversation) {
      value = $conversation_id
    }
  
    expect.to_equal ($traces_after_1[0].journey_map) {
      value = $journey_map_id
    }
  
    // ── US-TR-03: Verify tool logging — get_slice (column mode) ──
    var $first_stage_key {
      value = $map_state.stages[0].key
    }
  
    var $first_lens_key {
      value = $map_state.lenses[0].key
    }
  
    tool.call get_slice {
      input = {
        journey_map_id : $journey_map_id
        stage_key      : $first_stage_key
        conversation_id: $conversation_id
        turn_id        : $turn_id
      }
    } as $slice_result
  
    db.query agent_tool_log {
      where = $db.agent_tool_log.turn_id == $turn_id
      return = {type: "list"}
    } as $traces_after_2
  
    expect.to_equal ($traces_after_2|count) {
      value = 2
    }
  
    expect.to_equal ($traces_after_2[1].tool_name) {
      value = "get_slice"
    }
  
    expect.to_equal ($traces_after_2[1].tool_category) {
      value = "read"
    }
  
    // ── US-TR-03: Verify tool logging — batch_update (write) ──
    tool.call batch_update {
      input = {
        journey_map_id : $journey_map_id
        conversation_id: $conversation_id
        turn_id        : $turn_id
        updates        : ```
          [
            {stage_key: $first_stage_key, lens_key: $first_lens_key, content: "Test content for transparency"}
          ]
          ```
      }
    } as $batch_result
  
    db.query agent_tool_log {
      where = $db.agent_tool_log.turn_id == $turn_id
      return = {type: "list"}
    } as $traces_after_3
  
    expect.to_equal ($traces_after_3|count) {
      value = 3
    }
  
    expect.to_equal ($traces_after_3[2].tool_name) {
      value = "batch_update"
    }
  
    expect.to_equal ($traces_after_3[2].tool_category) {
      value = "write"
    }
  
    // ── US-TR-03: Verify multiple tools in same turn are grouped ──
    // All 3 traces above share the same turn_id
    expect.to_equal ($traces_after_3[0].turn_id) {
      value = $turn_id
    }
  
    expect.to_equal ($traces_after_3[1].turn_id) {
      value = $turn_id
    }
  
    expect.to_equal ($traces_after_3[2].turn_id) {
      value = $turn_id
    }
  
    // ── US-TR-03: Verify different turn_id creates separate group ──
    var $turn_id_2 {
      value = "test_turn_002"
    }
  
    tool.call get_gaps {
      input = {
        journey_map_id : $journey_map_id
        conversation_id: $conversation_id
        turn_id        : $turn_id_2
      }
    } as $gaps_result
  
    db.query agent_tool_log {
      where = $db.agent_tool_log.turn_id == $turn_id_2
      return = {type: "list"}
    } as $traces_turn_2
  
    expect.to_equal ($traces_turn_2|count) {
      value = 1
    }
  
    expect.to_equal ($traces_turn_2[0].tool_name) {
      value = "get_gaps"
    }
  
    // ── US-TR-03: Verify no logging when conversation_id/turn_id missing ──
    tool.call search_cells {
      input = {journey_map_id: $journey_map_id, query: "test"}
    } as $search_no_trace
  
    // Total traces should still be 4 (3 from turn_001 + 1 from turn_002)
    db.query agent_tool_log {
      where = $db.agent_tool_log.journey_map == $journey_map_id
      return = {type: "list"}
    } as $all_traces
  
    expect.to_equal ($all_traces|count) {
      value = 4
    }
  
    // ── US-TR-03: Verify set_cell_status logging ──
    tool.call set_cell_status {
      input = {
        journey_map_id : $journey_map_id
        stage_key      : $first_stage_key
        lens_key       : $first_lens_key
        status         : "confirmed"
        conversation_id: $conversation_id
        turn_id        : $turn_id_2
      }
    } as $status_result
  
    db.query agent_tool_log {
      where = $db.agent_tool_log.turn_id == $turn_id_2
      return = {type: "list"}
    } as $traces_turn_2_final
  
    expect.to_equal ($traces_turn_2_final|count) {
      value = 2
    }
  
    expect.to_equal ($traces_turn_2_final[1].tool_name) {
      value = "set_cell_status"
    }
  
    expect.to_equal ($traces_turn_2_final[1].tool_category) {
      value = "status"
    }
  }
}