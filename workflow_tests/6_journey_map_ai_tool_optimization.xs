// Covers Epic 3 tool correctness: scaffold_structure bulk ops, get_slice column/row/cell modes,
// get_gaps gap detection, batch_set_status bulk status changes, mutate_structure reorder actions,
// search_cells keyword search.
workflow_test journey_map_ai_tool_optimization {
  stack {
    // ── Setup: create a draft journey map ──
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      input = {title: "Epic 3 Tool Test", status: "draft"}
    } as $draft
  
    var $journey_map_id {
      value = $draft.journey_map.id
    }
  
    // Load initial state to get keys
    tool.call get_map_state {
      input = {journey_map_id: $journey_map_id}
    } as $initial_state
  
    var $first_stage_key {
      value = $initial_state.stages[0].key
    }
  
    var $second_stage_key {
      value = $initial_state.stages[1].key
    }
  
    var $first_lens_key {
      value = $initial_state.lenses[0].key
    }
  
    var $second_lens_key {
      value = $initial_state.lenses[1].key
    }
  
    var $initial_stage_count {
      value = $initial_state.stages|count
    }
  
    var $initial_lens_count {
      value = $initial_state.lenses|count
    }
  
    // ── US-AI-3.01: scaffold_structure renames and adds in one call ──
    tool.call scaffold_structure {
      input = {
        journey_map_id  : $journey_map_id
        stage_operations: ```
          [
            {action: "rename", key: $first_stage_key, label: "Intake"}
            {action: "rename", key: $second_stage_key, label: "Processing"}
            {action: "add", label: "Resolution"}
          ]
          ```
        lens_operations : ```
          [
            {action: "rename", key: $first_lens_key, label: "Who Owns It"}
            {action: "add", label: "Custom Metric"}
          ]
          ```
      }
    } as $scaffold_result
  
    expect.to_be_true ($scaffold_result.success)
    expect.to_equal ($scaffold_result.stages_renamed) {
      value = 2
    }
  
    expect.to_equal ($scaffold_result.stages_added) {
      value = 1
    }
  
    expect.to_equal ($scaffold_result.lenses_renamed) {
      value = 1
    }
  
    expect.to_equal ($scaffold_result.lenses_added) {
      value = 1
    }
  
    expect.to_equal ($scaffold_result.final_stage_count) {
      value = $initial_stage_count + 1
    }
  
    expect.to_equal ($scaffold_result.final_lens_count) {
      value = $initial_lens_count + 1
    }
  
    // Verify rename took effect
    tool.call get_map_state {
      input = {journey_map_id: $journey_map_id}
    } as $post_scaffold_state
  
    expect.to_equal ($post_scaffold_state.stages[0].label) {
      value = "Intake"
    }
  
    expect.to_equal ($post_scaffold_state.stages[1].label) {
      value = "Processing"
    }
  
    // ── Write some content for slice/gap/search tests ──
    tool.call batch_update {
      input = {
        journey_map_id: $journey_map_id
        updates       : ```
          [
            {stage_key: $first_stage_key, lens_key: $first_lens_key, content: "The support manager triages tickets"}
            {stage_key: $first_stage_key, lens_key: $second_lens_key, content: "Customer submits via portal"}
            {stage_key: $second_stage_key, lens_key: $first_lens_key, content: "Ops team handles processing"}
          ]
          ```
      }
    } as $write_result
  
    expect.to_equal ($write_result.applied_count) {
      value = 3
    }
  
    // ── US-AI-3.02: get_slice column mode ──
    tool.call get_slice {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
      }
    } as $col_slice
  
    expect.to_equal ($col_slice.slice_type) {
      value = "column"
    }
  
    expect.to_equal ($col_slice.stage.label) {
      value = "Intake"
    }
  
    expect.to_equal ($col_slice.summary.filled) {
      value = 2
    }
  
    // ── US-AI-3.02: get_slice row mode ──
    tool.call get_slice {
      input = {
        journey_map_id: $journey_map_id
        lens_key      : $first_lens_key
      }
    } as $row_slice
  
    expect.to_equal ($row_slice.slice_type) {
      value = "row"
    }
  
    expect.to_equal ($row_slice.lens.label) {
      value = "Who Owns It"
    }
  
    expect.to_equal ($row_slice.summary.filled) {
      value = 2
    }
  
    // ── US-AI-3.02: get_slice cell mode ──
    tool.call get_slice {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
        lens_key      : $first_lens_key
      }
    } as $cell_slice
  
    expect.to_equal ($cell_slice.slice_type) {
      value = "cell"
    }
  
    expect.to_equal ($cell_slice.cell.content) {
      value = "The support manager triages tickets"
    }
  
    // ── US-AI-3.03: get_gaps finds empty cells ──
    tool.call get_gaps {
      input = {journey_map_id: $journey_map_id}
    } as $gaps_result
  
    // 3 cells filled, rest are gaps
    expect.to_be_true ($gaps_result.total_gaps > 0)
  
    expect.to_be_true ($gaps_result.most_empty_stage != null)
    expect.to_be_true ($gaps_result.most_empty_lens != null)
    expect.to_be_true (($gaps_result.by_stage|count) > 0)
    expect.to_be_true (($gaps_result.by_lens|count) > 0)
  
    // ── US-AI-3.03: get_gaps filtered by stage ──
    tool.call get_gaps {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
      }
    } as $stage_gaps
  
    // first stage has 2 filled, so gaps = total_lenses - 2
    expect.to_be_true ($stage_gaps.total_gaps > 0)
  
    // ── US-AI-3.07: search_cells finds matching content ──
    tool.call "" {
      input = {journey_map_id: $journey_map_id, query: "manager"}
    } as $search_result
  
    expect.to_equal ($search_result.count) {
      value = 1
    }
  
    expect.to_equal ($search_result.results[0].stage_key) {
      value = $first_stage_key
    }
  
    // ── US-AI-3.07: search_cells with no matches ──
    tool.call "" {
      input = {
        journey_map_id: $journey_map_id
        query         : "nonexistent_xyz"
      }
    } as $search_empty
  
    expect.to_equal ($search_empty.count) {
      value = 0
    }
  
    // ── US-AI-3.05: batch_set_status by filter ──
    // Set all filled cells to "confirmed"
    tool.call batch_set_status {
      input = {
        journey_map_id: $journey_map_id
        filter        : {status: "draft"}
        set           : {status: "confirmed"}
      }
    } as $batch_confirm
  
    // We wrote 3 cells (all become draft via batch_update), so 3 should be confirmed
    expect.to_equal ($batch_confirm.applied_count) {
      value = 3
    }
  
    // ── US-AI-3.05: batch_set_status by explicit targets ──
    tool.call batch_set_status {
      input = {
        journey_map_id: $journey_map_id
        targets       : ```
          [
            {stage_key: $first_stage_key, lens_key: $first_lens_key}
          ]
          ```
        set           : {is_locked: true}
      }
    } as $batch_lock
  
    expect.to_equal ($batch_lock.applied_count) {
      value = 1
    }
  
    expect.to_be_true ($batch_lock.applied[0].new_is_locked)
  
    // Verify the cell is actually locked via get_slice
    tool.call get_slice {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
        lens_key      : $first_lens_key
      }
    } as $locked_cell
  
    expect.to_be_true ($locked_cell.cell.is_locked)
    expect.to_equal ($locked_cell.cell.status) {
      value = "confirmed"
    }
  
    // ── US-AI-3.06: reorder_stages ──
    // Get current stage order
    tool.call get_map_state {
      input = {journey_map_id: $journey_map_id}
    } as $pre_reorder_state
  
    // Collect all stage keys
    var $all_stage_keys {
      value = []
    }
  
    foreach ($pre_reorder_state.stages) {
      each as $s {
        array.push $all_stage_keys {
          value = $s.key
        }
      }
    }
  
    // Reverse the order
    var $reversed_keys {
      value = $all_stage_keys|reverse
    }
  
    tool.call mutate_structure {
      input = {
        journey_map_id: $journey_map_id
        action        : "reorder_stages"
        keys_in_order : $reversed_keys
      }
    } as $reorder_result
  
    expect.to_be_true ($reorder_result.success)
    expect.to_equal ($reorder_result.action) {
      value = "reorder_stages"
    }
  
    expect.to_be_true (($reorder_result.result.items|count) > 0)
  
    // Verify content is preserved after reorder
    tool.call get_slice {
      input = {
        journey_map_id: $journey_map_id
        stage_key     : $first_stage_key
        lens_key      : $first_lens_key
      }
    } as $after_reorder_cell
  
    expect.to_equal ($after_reorder_cell.cell.content) {
      value = "The support manager triages tickets"
    }
  
    // ── US-AI-3.06: reorder_lenses ──
    var $all_lens_keys {
      value = []
    }
  
    foreach ($pre_reorder_state.lenses) {
      each as $l {
        array.push $all_lens_keys {
          value = $l.key
        }
      }
    }
  
    var $reversed_lens_keys {
      value = $all_lens_keys|reverse
    }
  
    tool.call mutate_structure {
      input = {
        journey_map_id: $journey_map_id
        action        : "reorder_lenses"
        keys_in_order : $reversed_lens_keys
      }
    } as $reorder_lens_result
  
    expect.to_be_true ($reorder_lens_result.success)
    expect.to_equal ($reorder_lens_result.action) {
      value = "reorder_lenses"
    }
  }
}