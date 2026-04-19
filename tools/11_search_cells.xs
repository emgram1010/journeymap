// Full-text search across cell content in a journey map.
// Returns matching cells with their stage and lens coordinates.
tool search_cells {
  instructions = """
      Use this tool to search cell content by keyword. Returns all cells whose content
      contains the search query (case-insensitive).
    
      Use when the user asks:
      - 'Which cells mention manager?'
      - 'Find everything about SLA'
      - 'Where do we talk about notifications?'
    
      Optional filters narrow the search to one stage or one lens.
    
      Input:
      - journey_map_id: The ID of the journey map
      - query: Text to search for in cell content
      - stage_key: (optional) Limit search to this stage
      - lens_key: (optional) Limit search to this lens
    
      Response shape:
      {
        query: string,
        count: int,
        results: [ { cell_id, stage_key, stage_label, lens_key, lens_label, content } ]
      }
    """

  input {
    // The ID of the journey map to search.
    int journey_map_id filters=min:1
  
    // Text to search for within cell content.
    text query filters=trim
  
    // Optional: restrict search to one stage.
    text stage_key? filters=trim
  
    // Optional: restrict search to one lens.
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
  
    precondition ($input.query != null && $input.query != "") {
      error_type = "inputerror"
      error = "Search query is required"
    }
  
    // Load stages and lenses for enrichment
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $lenses
  
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
  
    // Resolve optional filter IDs
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
  
    // Load and search all cells
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $all_cells
  
    var $results {
      value = []
    }
  
    var $query_lower {
      value = $input.query|to_lower
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
          if ($c.content == null || $c.content == "") {
            var.update $include {
              value = false
            }
          }
        }
      
        conditional {
          if ($include) {
            // Case-insensitive content match
            var $content_lower {
              value = $c.content|to_lower
            }
          
            text.contains $content_lower {
              value = $query_lower
            } as $has_match
          
            conditional {
              if ($has_match) {
                var $s_rec {
                  value = $stage_map|get:($c.stage|to_text)
                }
              
                var $l_rec {
                  value = $lens_map|get:($c.lens|to_text)
                }
              
                array.push $results {
                  value = {
                    cell_id    : $c.id
                    stage_key  : $s_rec.key
                    stage_label: $s_rec.label
                    lens_key   : $l_rec.key
                    lens_label : $l_rec.label
                    content    : $c.content
                  }
                }
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
            tool_name     : "search_cells"
            tool_category : "read"
            input_summary : "Search: " ~ $input.query
            output_summary: ($results|count) ~ " matches"
          }
        } as $tool_log
      }
    }
  }

  response = {
    query  : $input.query
    count  : $results|count
    results: $results
  }
}