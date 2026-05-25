// IL-00-04: MCP tool — fill journey map cells with content and/or actor_fields.
// Maps to batch cell writes. Input: journey_map_id + array of { stage_key, lens_key, content?, actor_fields? }.
tool fill_cells {
  instructions = "Write content into journey map cells. Pass journey_map_id and an array of cell updates, each with stage_key, lens_key, and optionally content (text) and actor_fields (JSON object). Returns count of cells written and skipped."

  input {
    int journey_map_id filters=min:1
  
    // Array of { stage_key, lens_key, content?, actor_fields? }
    json cell_updates
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    // Load stages and lenses for key lookups
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $lenses
  
    var $written {
      value = 0
    }
  
    var $skipped {
      value = 0
    }
  
    foreach ($input.cell_updates) {
      each as $upd {
        // Resolve stage
        var $matched_stage {
          value = null
        }
      
        foreach ($stages) {
          each as $s {
            conditional {
              if ($s.key == $upd.stage_key) {
                var.update $matched_stage {
                  value = $s
                }
              }
            }
          }
        }
      
        // Resolve lens
        var $matched_lens {
          value = null
        }
      
        foreach ($lenses) {
          each as $l {
            conditional {
              if ($l.key == $upd.lens_key) {
                var.update $matched_lens {
                  value = $l
                }
              }
            }
          }
        }
      
        conditional {
          if ($matched_stage != null && $matched_lens != null) {
            // Find the cell at stage × lens intersection
            db.query journey_cell {
              where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $matched_stage.id && $db.journey_cell.lens == $matched_lens.id
              return = {type: "single"}
            } as $cell
          
            conditional {
              if ($cell != null) {
                db.patch journey_cell {
                  field_name = "id"
                  field_value = $cell.id
                  data = {
                    content      : $upd.content ?? $cell.content
                    actor_fields : $upd.actor_fields ?? $cell.actor_fields
                    status       : "draft"
                    change_source: "ai"
                    updated_at   : "now"
                  }
                } as $patched_cell
              
                var.update $written {
                  value = $written + 1
                }
              }
            
              else {
                var.update $skipped {
                  value = $skipped + 1
                }
              }
            }
          }
        
          else {
            var.update $skipped {
              value = $skipped + 1
            }
          }
        }
      }
    }
  
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $map_touch
  }

  response = {
    journey_map_id: $input.journey_map_id
    written       : $written
    skipped       : $skipped
  }
}