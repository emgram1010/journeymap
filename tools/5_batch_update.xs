// Updates multiple journey map cells in one call. Skips locked and confirmed cells.
// Updates multiple cells in a journey map in a single call.
tool batch_update {
  instructions = """
      Use this tool when you need to write content into multiple cells at once,
      such as after a multi-topic interview answer.
    
      Each update is identified by stage_key + lens_key. Locked and confirmed cells are
      skipped automatically. All successful writes set change_source='ai' and status='draft'.
    
      Input:
      - journey_map_id: The ID of the journey map
      - updates: A JSON array of objects, each with { stage_key, lens_key, content }
    
      Response shape:
      {
        applied: [ { stage_key, lens_key, cell_id, content } ],
        skipped: [ { stage_key, lens_key, reason } ],
        applied_count: int,
        skipped_count: int
      }
    """

  input {
    // The ID of the journey map containing the cells.
    int journey_map_id filters=min:1
  
    // Optional: for tool trace logging (transparency layer).
    int conversation_id?
  
    text turn_id?
  
    // Array of { stage_key, lens_key, content } objects to apply.
    json updates
  }

  stack {
    var $applied {
      value = []
    }
  
    var $skipped {
      value = []
    }
  
    var $applied_count {
      value = 0
    }
  
    var $skipped_count {
      value = 0
    }
  
    foreach ($input.updates) {
      each as $upd {
        // Resolve stage by key
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $upd.stage_key
          return = {type: "single"}
        } as $stage
      
        // Resolve lens by key
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $upd.lens_key
          return = {type: "single"}
        } as $lens
      
        conditional {
          if ($stage == null || $lens == null) {
            array.push $skipped {
              value = {
                stage_key: $upd.stage_key
                lens_key : $upd.lens_key
                reason   : "not_found"
              }
            }
          
            var.update $skipped_count {
              value = $skipped_count + 1
            }
          }
        
          else {
            // Find the cell at the intersection
            db.query journey_cell {
              where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $lens.id
              return = {type: "single"}
            } as $cell
          
            conditional {
              if ($cell == null) {
                array.push $skipped {
                  value = {
                    stage_key: $upd.stage_key
                    lens_key : $upd.lens_key
                    reason   : "not_found"
                  }
                }
              
                var.update $skipped_count {
                  value = $skipped_count + 1
                }
              }
            
              elseif ($cell.is_locked) {
                array.push $skipped {
                  value = {
                    stage_key: $upd.stage_key
                    lens_key : $upd.lens_key
                    reason   : "locked"
                  }
                }
              
                var.update $skipped_count {
                  value = $skipped_count + 1
                }
              }
            
              elseif ($cell.status == "confirmed") {
                array.push $skipped {
                  value = {
                    stage_key: $upd.stage_key
                    lens_key : $upd.lens_key
                    reason   : "confirmed"
                  }
                }
              
                var.update $skipped_count {
                  value = $skipped_count + 1
                }
              }
            
              else {
                db.patch journey_cell {
                  field_name = "id"
                  field_value = $cell.id
                  data = {
                    content        : $upd.content
                    status         : "draft"
                    change_source  : "ai"
                    updated_at     : "now"
                    last_updated_at: "now"
                  }
                } as $updated_cell
              
                array.push $applied {
                  value = {
                    stage_key: $upd.stage_key
                    lens_key : $upd.lens_key
                    cell_id  : $updated_cell.id
                    content  : $upd.content
                  }
                }
              
                var.update $applied_count {
                  value = $applied_count + 1
                }
              }
            }
          }
        }
      }
    }
  
    // Touch the journey map timestamp once after all updates
    conditional {
      if ($applied_count > 0) {
        db.patch journey_map {
          field_name = "id"
          field_value = $input.journey_map_id
          data = {updated_at: "now", last_interaction_at: "now"}
        } as $map_touch
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
            tool_name     : "batch_update"
            tool_category : "write"
            input_summary : $applied_count ~ " cells targeted"
            output_summary: $applied_count ~ " applied, " ~ $skipped_count ~ " skipped"
          }
        } as $tool_log
      }
    }
  }

  response = {
    applied      : $applied
    skipped      : $skipped
    applied_count: $applied_count
    skipped_count: $skipped_count
  }
}