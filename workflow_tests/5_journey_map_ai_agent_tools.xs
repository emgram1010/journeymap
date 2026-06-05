// Covers AI agent tool correctness: get_map_state returns schema,
// update_cell writes and respects locks, batch_update handles mixed cells,
// mutate_structure scaffolds correctly, set_cell_status changes status/lock.
workflow_test journey_map_ai_agent_tools {
  stack {
    // ── Setup: create a draft journey map ──
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      input = {title: "AI Agent Tool Test", status: "draft"}
    } as $draft
  
    var $journey_map_id {
      value = $draft.journey_map.id
    }
  
    // ── US-AI-01: get_map_state returns full schema ──
    tool.call get_map_state {
      input = {journey_map_id: $journey_map_id}
    } as $map_state
  
    // Map title matches
    expect.to_equal ($map_state.journey_map.title) {
      value = "AI Agent Tool Test"
    }
  
    // Has stages and lenses
    expect.to_be_true (($map_state.stages|count) > 0)
  
    expect.to_be_true (($map_state.lenses|count) > 0)
  
    // Cells exist and summary is consistent
    expect.to_equal ($map_state.summary.total_cells) {
      value = $map_state.cells|count
    }
  
    // All cells should be empty initially
    expect.to_equal ($map_state.summary.filled_cells) {
      value = 0
    }
  
    // ── US-AI-02: update_cell writes by key and respects locks ──
    var $first_stage_key {
      value = $map_state.stages[0].key
    }
  
    var $first_lens_key {
      value = $map_state.lenses[0].key
    }
  
    tool.call update_cell {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
        lens_key      : $first_lens_key
        content       : "AI-written content"
      }
    } as $update_result
  
    expect.to_be_true ($update_result.applied)
    expect.to_equal ($update_result.cell.content) {
      value = "AI-written content"
    }
  
    expect.to_equal ($update_result.cell.change_source) {
      value = "ai"
    }
  
    expect.to_equal ($update_result.cell.status) {
      value = "draft"
    }
  
    // Lock the cell via set_cell_status, then try to update — should be skipped
    tool.call set_cell_status {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
        lens_key      : $first_lens_key
        is_locked     : true
      }
    } as $lock_result
  
    expect.to_be_true ($lock_result.applied)
    expect.to_be_true ($lock_result.cell.is_locked)
    tool.call update_cell {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
        lens_key      : $first_lens_key
        content       : "Should be skipped"
      }
    } as $locked_update
  
    expect.to_be_true ($locked_update.applied == false)
    expect.to_equal ($locked_update.skip_reason) {
      value = "locked"
    }
  
    // ── US-AI-04: batch_update handles mixed locked/unlocked cells ──
    var $second_lens_key {
      value = $map_state.lenses[1].key
    }
  
    tool.call batch_update {
      input = {
        journey_map_id: $journey_map_id
        updates       : ```
          [
            {stage_key: $first_stage_key, lens_key: $first_lens_key, content: "Locked cell attempt"}
            {stage_key: $first_stage_key, lens_key: $second_lens_key, content: "Unlocked cell write"}
          ]
          ```
      }
    } as $batch_result
  
    // One skipped (locked), one applied
    expect.to_equal ($batch_result.skipped_count) {
      value = 1
    }
  
    expect.to_equal ($batch_result.applied_count) {
      value = 1
    }
  
    // ── US-AI-03: mutate_structure adds a stage with scaffolded cells ──
    tool.call mutate_structure {
      input = {
        journey_map_id: $journey_map_id
        action        : "add_stage"
        label         : "AI-Added Stage"
      }
    } as $add_stage_result
  
    expect.to_be_true ($add_stage_result.success)
  
    // Verify new cells were scaffolded by re-reading map state
    tool.call get_map_state {
      input = {journey_map_id: $journey_map_id}
    } as $map_state_after
  
    // Should have more cells than before (one new cell per lens)
    expect.to_be_true ($map_state_after.summary.total_cells > $map_state.summary.total_cells)
  
    // ── US-AI-06: set_cell_status can confirm a cell ──
    tool.call set_cell_status {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
        lens_key      : $second_lens_key
        status        : "confirmed"
      }
    } as $confirm_result
  
    expect.to_be_true ($confirm_result.applied)
    expect.to_equal ($confirm_result.cell.status) {
      value = "confirmed"
    }
  
    // update_cell should skip confirmed cells
    tool.call update_cell {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
        lens_key      : $second_lens_key
        content       : "Should skip confirmed"
      }
    } as $confirmed_update
  
    expect.to_be_true ($confirmed_update.applied == false)
    expect.to_equal ($confirmed_update.skip_reason) {
      value = "confirmed"
    }
  }
}