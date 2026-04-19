// Finds all empty cells in a journey map, optionally filtered by stage or lens.
// Returns gap counts ranked by density to drive interview targeting.
tool get_gaps {
  instructions = """
      Use this tool to find empty cells in the journey map. Returns gaps ranked by density
      so you can prioritize which areas to explore next.
    
      Modes:
      - All gaps (no filter): Returns every empty cell, grouped by stage and lens.
      - By stage (stage_key): Returns empty cells for one stage only.
      - By lens (lens_key): Returns empty cells for one lens only.
    
      The response includes:
      - gaps: Array of empty cells with their stage/lens coordinates.
      - by_stage: Gap counts per stage, sorted most-empty first.
      - by_lens: Gap counts per lens, sorted most-empty first.
      - most_empty_stage / most_empty_lens: Shortcut fields for interview targeting.
    
      Use at the start of an interview to pick the most productive area.
      Use after batch writes to recalculate next target.
      Use when the user asks 'what's missing?'
    """

  input {
    // The ID of the journey map to analyze.
    int journey_map_id filters=min:1
  
    // Optional: filter gaps to one stage.
    text stage_key? filters=trim
  
    // Optional: filter gaps to one lens.
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
  
    // Load stages and lenses
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $lenses
  
    // Load all cells
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $all_cells
  
    // Build lookup maps
    var $stage_map {
      value = {}
    }
  
    foreach ($stages) {
      each as $s {
        var.update $stage_map {
          value = $stage_map|set:($s.id|to_text):$s
        }
      }
    }
  
    var $lens_map {
      value = {}
    }
  
    foreach ($lenses) {
      each as $l {
        var.update $lens_map {
          value = $lens_map|set:($l.id|to_text):$l
        }
      }
    }
  
    // Resolve optional filters to IDs
    var $filter_stage_id {
      value = null
    }
  
    conditional {
      if ($input.stage_key != null && $input.stage_key != "") {
        db.query journey_stage {
          where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.stage_key
          return = {type: "single"}
        } as $filter_stage
      
        precondition ($filter_stage != null) {
          error_type = "notfound"
          error = "Stage not found with key: " + $input.stage_key
        }
      
        var.update $filter_stage_id {
          value = $filter_stage.id
        }
      }
    }
  
    var $filter_lens_id {
      value = null
    }
  
    conditional {
      if ($input.lens_key != null && $input.lens_key != "") {
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.key == $input.lens_key
          return = {type: "single"}
        } as $filter_lens
      
        precondition ($filter_lens != null) {
          error_type = "notfound"
          error = "Lens not found with key: " + $input.lens_key
        }
      
        var.update $filter_lens_id {
          value = $filter_lens.id
        }
      }
    }
  
    // Collect gaps and count per stage/lens
    var $gaps {
      value = []
    }
  
    var $stage_empty_counts {
      value = {}
    }
  
    var $stage_total_counts {
      value = {}
    }
  
    var $lens_empty_counts {
      value = {}
    }
  
    var $lens_total_counts {
      value = {}
    }
  
    foreach ($all_cells) {
      each as $c {
        // Apply filters
        var $include {
          value = true
        }
      
        conditional {
          if ($filter_stage_id != null && $c.stage != $filter_stage_id) {
            var.update $include {
              value = false
            }
          }
        }
      
        conditional {
          if ($filter_lens_id != null && $c.lens != $filter_lens_id) {
            var.update $include {
              value = false
            }
          }
        }
      
        conditional {
          if ($include) {
            var $s_key {
              value = $c.stage|to_text
            }
          
            var $l_key {
              value = $c.lens|to_text
            }
          
            var $s_rec {
              value = $stage_map|get:$s_key
            }
          
            var $l_rec {
              value = $lens_map|get:$l_key
            }
          
            // Track totals per stage
            var $st_cur {
              value = $stage_total_counts|get:$s_key
            }
          
            conditional {
              if ($st_cur == null) {
                var.update $stage_total_counts {
                  value = $stage_total_counts|set:$s_key:1
                }
              }
            
              else {
                var.update $stage_total_counts {
                  value = $stage_total_counts|set:$s_key:$st_cur + 1
                }
              }
            }
          
            // Track totals per lens
            var $lt_cur {
              value = $lens_total_counts|get:$l_key
            }
          
            conditional {
              if ($lt_cur == null) {
                var.update $lens_total_counts {
                  value = $lens_total_counts|set:$l_key:1
                }
              }
            
              else {
                var.update $lens_total_counts {
                  value = $lens_total_counts|set:$l_key:$lt_cur + 1
                }
              }
            }
          
            // Check if cell is empty
            conditional {
              if ($c.content == null || $c.content == "") {
                array.push $gaps {
                  value = {
                    stage_key  : $s_rec.key
                    stage_label: $s_rec.label
                    lens_key   : $l_rec.key
                    lens_label : $l_rec.label
                    cell_id    : $c.id
                  }
                }
              
                // Increment stage empty count
                var $se_cur {
                  value = $stage_empty_counts|get:$s_key
                }
              
                conditional {
                  if ($se_cur == null) {
                    var.update $stage_empty_counts {
                      value = $stage_empty_counts|set:$s_key:1
                    }
                  }
                
                  else {
                    var.update $stage_empty_counts {
                      value = $stage_empty_counts|set:$s_key:$se_cur + 1
                    }
                  }
                }
              
                // Increment lens empty count
                var $le_cur {
                  value = $lens_empty_counts|get:$l_key
                }
              
                conditional {
                  if ($le_cur == null) {
                    var.update $lens_empty_counts {
                      value = $lens_empty_counts|set:$l_key:1
                    }
                  }
                
                  else {
                    var.update $lens_empty_counts {
                      value = $lens_empty_counts|set:$l_key:$le_cur + 1
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  
    // ── Build by_stage array ──
    var $by_stage {
      value = []
    }
  
    foreach ($stages) {
      each as $s {
        var $sk {
          value = $s.id|to_text
        }
      
        var $s_total {
          value = $stage_total_counts|get:$sk
        }
      
        var $s_empty {
          value = $stage_empty_counts|get:$sk
        }
      
        conditional {
          if ($s_total == null) {
            var.update $s_total {
              value = 0
            }
          }
        }
      
        conditional {
          if ($s_empty == null) {
            var.update $s_empty {
              value = 0
            }
          }
        }
      
        conditional {
          if ($s_total > 0) {
            array.push $by_stage {
              value = {
                stage_key  : $s.key
                label      : $s.label
                empty_count: $s_empty
                total      : $s_total
              }
            }
          }
        }
      }
    }
  
    // ── Build by_lens array ──
    var $by_lens {
      value = []
    }
  
    foreach ($lenses) {
      each as $l {
        var $lk {
          value = $l.id|to_text
        }
      
        var $l_total {
          value = $lens_total_counts|get:$lk
        }
      
        var $l_empty {
          value = $lens_empty_counts|get:$lk
        }
      
        conditional {
          if ($l_total == null) {
            var.update $l_total {
              value = 0
            }
          }
        }
      
        conditional {
          if ($l_empty == null) {
            var.update $l_empty {
              value = 0
            }
          }
        }
      
        conditional {
          if ($l_total > 0) {
            array.push $by_lens {
              value = {
                lens_key   : $l.key
                label      : $l.label
                empty_count: $l_empty
                total      : $l_total
              }
            }
          }
        }
      }
    }
  
    // ── Find most empty stage and lens ──
    var $most_empty_stage {
      value = null
    }
  
    var $max_stage_empty {
      value = 0
    }
  
    foreach ($by_stage) {
      each as $bs {
        conditional {
          if ($bs.empty_count > $max_stage_empty) {
            var.update $max_stage_empty {
              value = $bs.empty_count
            }
          
            var.update $most_empty_stage {
              value = {
                key        : $bs.stage_key
                label      : $bs.label
                empty_count: $bs.empty_count
              }
            }
          }
        }
      }
    }
  
    var $most_empty_lens {
      value = null
    }
  
    var $max_lens_empty {
      value = 0
    }
  
    foreach ($by_lens) {
      each as $bl {
        conditional {
          if ($bl.empty_count > $max_lens_empty) {
            var.update $max_lens_empty {
              value = $bl.empty_count
            }
          
            var.update $most_empty_lens {
              value = {
                key        : $bl.lens_key
                label      : $bl.label
                empty_count: $bl.empty_count
              }
            }
          }
        }
      }
    }
  
    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        var $gaps_input_desc {
          value = "All gaps"
        }
      
        conditional {
          if ($input.stage_key != null) {
            var.update $gaps_input_desc {
              value = "Stage: " + $input.stage_key
            }
          }
        
          elseif ($input.lens_key != null) {
            var.update $gaps_input_desc {
              value = "Lens: " + $input.lens_key
            }
          }
        }
      
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "get_gaps"
            tool_category : "read"
            input_summary : $gaps_input_desc
            output_summary: ($gaps|count) ~ " gaps found"
          }
        } as $tool_log
      }
    }
  }

  response = {
    total_gaps      : $gaps|count
    gaps            : $gaps
    by_stage        : $by_stage
    by_lens         : $by_lens
    most_empty_stage: $most_empty_stage
    most_empty_lens : $most_empty_lens
  }
}