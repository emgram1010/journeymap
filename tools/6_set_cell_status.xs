// Changes the status and/or lock flag of a single journey map cell.
// Changes the status and/or lock state of a journey map cell.
tool set_cell_status {
  instructions = """
      Use this tool to change a cell's status (open/draft/confirmed) or lock state (is_locked).
      Only updates the fields you provide — omit a field to leave it unchanged.
    
      Typical uses:
      - Mark a cell as 'confirmed' after the user approves AI-written content.
      - Lock a cell to prevent further AI modifications.
      - Unlock a cell to allow further updates.
      - Reset a cell to 'open' status.
    
      Input:
      - journey_map_id: The ID of the journey map
      - stage_key: The key of the target stage
      - lens_key: The key of the target lens
      - status: (optional) New status — 'open', 'draft', or 'confirmed'
      - is_locked: (optional) New lock state — true or false
    
      Response shape:
      {
        applied: true/false,
        cell: { id, stage_key, lens_key, content, status, is_locked, change_source },
        error: null | string
      }
    """

  input {
    // The ID of the journey map containing the cell.
    int journey_map_id filters=min:1
  
    // Optional: for tool trace logging (transparency layer).
    int conversation_id?
  
    text turn_id?
  
    // The key of the stage (column) for the target cell.
    text stage_key filters=trim
  
    // The key of the lens (row) for the target cell.
    text lens_key filters=trim
  
    // New status for the cell. Omit to leave unchanged.
    enum status? {
      values = ["open", "draft", "confirmed"]
    }
  
    // New lock state for the cell. Omit to leave unchanged.
    bool is_locked?
  }

  stack {
    // Resolve the stage by key
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.stage_key
      return = {type: "single"}
    } as $stage
  
    // Resolve the lens by key
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.lens_key
      return = {type: "single"}
    } as $lens
  
    var $result {
      value = {applied: false, cell: null, error: "Cell not found"}
    }
  
    conditional {
      if ($stage != null && $lens != null) {
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $lens.id
          return = {type: "single"}
        } as $cell
      
        conditional {
          if ($cell != null) {
            // Build the patch data with only the provided fields
            var $patch_data {
              value = {updated_at: "now", last_updated_at: "now"}
            }
          
            conditional {
              if ($input.status != null) {
                var.update $patch_data {
                  value = $patch_data|set:"status":$input.status
                }
              }
            }
          
            conditional {
              if ($input.is_locked != null) {
                var.update $patch_data {
                  value = $patch_data|set:"is_locked":$input.is_locked
                }
              }
            }
          
            db.patch journey_cell {
              field_name = "id"
              field_value = $cell.id
              data = $patch_data
            } as $updated_cell
          
            var.update $result {
              value = {
                applied: true
                cell   : {
                  id           : $updated_cell.id
                  stage_key    : $input.stage_key
                  lens_key     : $input.lens_key
                  content      : $updated_cell.content
                  status       : $updated_cell.status
                  is_locked    : $updated_cell.is_locked
                  change_source: $updated_cell.change_source
                }
                error  : null
              }
            }
          
            db.patch journey_map {
              field_name = "id"
              field_value = $input.journey_map_id
              data = {updated_at: "now", last_interaction_at: "now"}
            } as $map_touch
          }
        }
      }
    }
  
    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "set_cell_status"
            tool_category : "status"
            input_summary : $input.stage_key ~ " × " ~ $input.lens_key
            output_summary: $result.applied ? "Applied" : "Skipped"
          }
        } as $tool_log
      }
    }
  }

  response = $result
}