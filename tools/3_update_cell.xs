// Updates a single journey map cell identified by stage_key + lens_key.
// Respects is_locked — returns a skip result instead of writing if locked.
// Updates a single cell in a journey map by stage key and lens key.
tool update_cell {
  instructions = """
      Use this tool to write content into a specific cell identified by its stage_key and lens_key.
      The tool resolves the target cell by joining stage and lens keys — do NOT pass cell IDs.
    
      The cell will be updated with change_source 'ai' and status 'draft'.
      If the target cell is locked (is_locked=true), the update is skipped and a skip result is returned.
      If the target cell has status 'confirmed', the update is skipped to protect user-confirmed content.
    
      Input:
      - journey_map_id: The ID of the journey map
      - stage_key: The key of the target stage (e.g. 'awareness', 'consideration')
      - lens_key: The key of the target lens (e.g. 'goals', 'touchpoints')
      - content: The text content to write into the cell
    
      Response shape:
      {
        applied: true/false,
        cell: { id, stage_key, lens_key, content, status, is_locked, change_source },
        skip_reason: null | 'locked' | 'confirmed' | 'not_found'
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
  
    // The text content to write into the cell.
    text content filters=trim
  }

  stack {
    // Resolve the stage by key within this journey map
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.stage_key
      return = {type: "single"}
    } as $stage
  
    // Resolve the lens by key within this journey map
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.lens_key
      return = {type: "single"}
    } as $lens
  
    var $result {
      value = {applied: false, cell: null, skip_reason: "not_found"}
    }
  
    conditional {
      if ($stage != null && $lens != null) {
        // Find the cell at the stage×lens intersection
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $lens.id
          return = {type: "single"}
        } as $cell
      
        conditional {
          if ($cell == null) {
            var.update $result {
              value = {applied: false, cell: null, skip_reason: "not_found"}
            }
          }
        
          elseif ($cell.is_locked) {
            var.update $result {
              value = {
                applied    : false
                cell       : {
                  id           : $cell.id
                  stage_key    : $input.stage_key
                  lens_key     : $input.lens_key
                  content      : $cell.content
                  status       : $cell.status
                  is_locked    : $cell.is_locked
                  change_source: $cell.change_source
                }
                skip_reason: "locked"
              }
            }
          }
        
          elseif ($cell.status == "confirmed") {
            var.update $result {
              value = {
                applied    : false
                cell       : {
                  id           : $cell.id
                  stage_key    : $input.stage_key
                  lens_key     : $input.lens_key
                  content      : $cell.content
                  status       : $cell.status
                  is_locked    : $cell.is_locked
                  change_source: $cell.change_source
                }
                skip_reason: "confirmed"
              }
            }
          }
        
          else {
            db.patch journey_cell {
              field_name = "id"
              field_value = $cell.id
              data = {
                content        : $input.content
                status         : "draft"
                change_source  : "ai"
                updated_at     : "now"
                last_updated_at: "now"
              }
            } as $updated_cell
          
            var.update $result {
              value = {
                applied    : true
                cell       : {
                  id           : $updated_cell.id
                  stage_key    : $input.stage_key
                  lens_key     : $input.lens_key
                  content      : $updated_cell.content
                  status       : $updated_cell.status
                  is_locked    : $updated_cell.is_locked
                  change_source: $updated_cell.change_source
                }
                skip_reason: null
              }
            }
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
            tool_name     : "update_cell"
            tool_category : "write"
            input_summary : $input.stage_key ~ " × " ~ $input.lens_key
            output_summary: $result.applied ? "Applied" : "Skipped: " ~ $result.skip_reason
          }
        } as $tool_log
      }
    }
  }

  response = $result
}