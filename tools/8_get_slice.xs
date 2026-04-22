// Reads a targeted slice of a journey map: one column (stage), one row (lens), or one cell.
// Avoids loading the entire map when the AI PM only needs a specific section.
tool get_slice {
  instructions = """
      Use this tool to read a targeted slice of the journey map instead of loading everything
      with get_map_state. Returns only the cells you need with a mini-summary.
    
      Modes:
      - Column (provide stage_key only): All cells for one stage, across every lens.
      - Row (provide lens_key only): All cells for one lens, across every stage.
      - Cell (provide both stage_key + lens_key): One specific cell at that intersection.
      - If neither key is provided, use get_map_state instead.
    
      Input:
      - journey_map_id: The ID of the journey map
      - stage_key: (optional) The key of the stage to slice
      - lens_key: (optional) The key of the lens to slice
    
      Response shape varies by mode:
      Column: { slice_type: "column", stage: {...}, cells: [{ lens_key, lens_label, actor_type, actor_fields, content, status, is_locked, change_source }], summary: {...} }
      Row:    { slice_type: "row",    lens: {...},  cells: [{ stage_key, stage_label, actor_type, actor_fields, content, status, is_locked, change_source }], summary: {...} }
      Cell:   { slice_type: "cell",  stage: {...}, lens: {...}, cell: { id, actor_type, actor_fields, content, status, is_locked, change_source } }
    
      actor_type: the actor type of the lens (e.g. "handoff", "customer"); null for non-actor lenses.
      actor_fields: the structured field object written via update_actor_cell_fields; null when not yet populated.
      Use actor_fields after writing with update_actor_cell_fields to verify the correct keys were saved.
    """

  input {
    // The ID of the journey map to read from.
    int journey_map_id filters=min:1
  
    // The key of the stage (column) to slice. Optional.
    text stage_key? filters=trim
  
    // The key of the lens (row) to slice. Optional.
    text lens_key? filters=trim
  
    // Optional: for tool trace logging (transparency layer).
    int conversation_id?
  
    text turn_id?
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
  
    precondition ($input.stage_key != null || $input.lens_key != null) {
      error_type = "inputerror"
      error = "Provide stage_key and/or lens_key. Use get_map_state for the full map."
    }
  
    // Resolve stage if provided
    var $stage {
      value = null
    }
  
    conditional {
      if ($input.stage_key != null && $input.stage_key != "") {
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.stage_key
          return = {type: "single"}
        } as $found_stage
      
        precondition ($found_stage != null) {
          error_type = "notfound"
          error = "Stage not found with key: " + $input.stage_key
        }
      
        var.update $stage {
          value = $found_stage
        }
      }
    }
  
    // Resolve lens if provided
    var $lens {
      value = null
    }
  
    conditional {
      if ($input.lens_key != null && $input.lens_key != "") {
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.lens_key
          return = {type: "single"}
        } as $found_lens
      
        precondition ($found_lens != null) {
          error_type = "notfound"
          error = "Lens not found with key: " + $input.lens_key
        }
      
        var.update $lens {
          value = $found_lens
        }
      }
    }
  
    var $result {
      value = null
    }
  
    var $cells {
      value = []
    }
  
    var $filled {
      value = 0
    }
  
    var $locked {
      value = 0
    }
  
    var $confirmed {
      value = 0
    }
  
    // ── Mode: single cell (both keys provided) ──
    conditional {
      if ($stage != null && $lens != null) {
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $lens.id
          return = {type: "single"}
        } as $cell
      
        var.update $result {
          value = {
            slice_type: "cell"
            stage     : {key: $stage.key, label: $stage.label, display_order: $stage.display_order}
            lens      : {key: $lens.key, label: $lens.label, description: $lens.description, display_order: $lens.display_order}
            cell      : {
              id           : $cell.id
              actor_type   : $lens.actor_type
              actor_fields : $cell.actor_fields
              content      : $cell.content
              status       : $cell.status
              is_locked    : $cell.is_locked
              change_source: $cell.change_source
            }
          }
        }
      }
    
      // ── Mode: column (stage_key only) ──
      elseif ($stage != null) {
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id
          sort = {id: "asc"}
          return = {type: "list"}
        } as $col_raw_cells
      
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id
          sort = {display_order: "asc"}
          return = {type: "list"}
        } as $col_lenses
      
        var $col_lens_map {
          value = {}
        }
      
        foreach ($col_lenses) {
          each as $l {
            var.update $col_lens_map {
              value = $col_lens_map|set:($l.id|to_text):$l
            }
          }
        }
      
        foreach ($col_raw_cells) {
          each as $c {
            var $l_rec {
              value = $col_lens_map|get:($c.lens|to_text)
            }
          
            array.push $cells {
              value = {
                lens_key     : $l_rec.key
                lens_label   : $l_rec.label
                actor_type   : $l_rec.actor_type
                actor_fields : $c.actor_fields
                content      : $c.content
                status       : $c.status
                is_locked    : $c.is_locked
                change_source: $c.change_source
              }
            }
          
            conditional {
              if ($c.content != null && $c.content != "") {
                var.update $filled {
                  value = $filled + 1
                }
              }
            }
          
            conditional {
              if ($c.is_locked) {
                var.update $locked {
                  value = $locked + 1
                }
              }
            }
          
            conditional {
              if ($c.status == "confirmed") {
                var.update $confirmed {
                  value = $confirmed + 1
                }
              }
            }
          }
        }
      
        var.update $result {
          value = {
            slice_type: "column"
            stage     : {key: $stage.key, label: $stage.label, display_order: $stage.display_order}
            cells     : $cells
            summary   : {filled: $filled, empty: ($col_raw_cells|count) - $filled, locked: $locked, confirmed: $confirmed}
          }
        }
      }
    
      // ── Mode: row (lens_key only) ──
      elseif ($lens != null) {
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.lens == $lens.id
          sort = {id: "asc"}
          return = {type: "list"}
        } as $row_raw_cells
      
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id
          sort = {display_order: "asc"}
          return = {type: "list"}
        } as $row_stages
      
        var $row_stage_map {
          value = {}
        }
      
        foreach ($row_stages) {
          each as $s {
            var.update $row_stage_map {
              value = $row_stage_map|set:($s.id|to_text):$s
            }
          }
        }
      
        foreach ($row_raw_cells) {
          each as $c {
            var $s_rec {
              value = $row_stage_map|get:($c.stage|to_text)
            }
          
            array.push $cells {
              value = {
                stage_key    : $s_rec.key
                stage_label  : $s_rec.label
                actor_type   : $lens.actor_type
                actor_fields : $c.actor_fields
                content      : $c.content
                status       : $c.status
                is_locked    : $c.is_locked
                change_source: $c.change_source
              }
            }
          
            conditional {
              if ($c.content != null && $c.content != "") {
                var.update $filled {
                  value = $filled + 1
                }
              }
            }
          
            conditional {
              if ($c.is_locked) {
                var.update $locked {
                  value = $locked + 1
                }
              }
            }
          
            conditional {
              if ($c.status == "confirmed") {
                var.update $confirmed {
                  value = $confirmed + 1
                }
              }
            }
          }
        }
      
        var.update $result {
          value = {
            slice_type: "row"
            lens      : {key: $lens.key, label: $lens.label, description: $lens.description, display_order: $lens.display_order}
            cells     : $cells
            summary   : {filled: $filled, empty: ($row_raw_cells|count) - $filled, locked: $locked, confirmed: $confirmed}
          }
        }
      }
    }
  
    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        var $slice_summary {
          value = "Slice: "
        }
      
        conditional {
          if ($input.stage_key != null && $input.lens_key != null) {
            var.update $slice_summary {
              value = "Cell: " + $input.stage_key + " × " + $input.lens_key
            }
          }
        
          elseif ($input.stage_key != null) {
            var.update $slice_summary {
              value = "Column: " + $input.stage_key + " (" + $filled + " filled)"
            }
          }
        
          elseif ($input.lens_key != null) {
            var.update $slice_summary {
              value = "Row: " + $input.lens_key + " (" + $filled + " filled)"
            }
          }
        }
      
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "get_slice"
            tool_category : "read"
            input_summary : $slice_summary
            output_summary: $slice_summary
          }
        } as $tool_log
      }
    }
  }

  response = $result
}