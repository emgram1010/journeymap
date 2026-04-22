// Reads the full current state of a journey map: stages, lenses, and cells with content, status, lock, and change_source.
// Used by the Journey Map Assistant agent to reason about what is filled, empty, locked, or confirmed.
// Reads the full current state of a journey map including all stages, lenses, and cells.
tool get_map_state {
  instructions = """
      Use this tool to read the complete state of a journey map before making any updates.
      Returns all stages (columns) and lenses (rows) sorted by display_order, plus every cell
      at each stage×lens intersection with its current content, status (open/draft/confirmed),
      is_locked flag, and change_source (user/ai/null).
    
      Call this tool first in every conversation to understand what the map looks like before
      asking questions or proposing changes. Use the stage `key` and lens `key` values when
      calling update_cell or batch_update — never use IDs directly.
    
      Response shape:
      {
        journey_map: { id, title, status, updated_at },
        stages: [ { id, key, label, display_order } ],
        lenses: [ { id, key, label, display_order } ],
        cells: [ { id, stage_id, stage_key, lens_id, lens_key, actor_type, actor_fields, content, status, is_locked, change_source } ],
        // actor_type: the actor type of the parent lens (e.g. "handoff", "customer"); null for non-actor rows.
        // actor_fields: the structured field object written via update_actor_cell_fields; null when not yet populated.
        summary: { total_cells, filled_cells, empty_cells, locked_cells, confirmed_cells, draft_cells, open_cells }
      }
    """

  input {
    // The ID of the journey map to read.
    int journey_map_id filters=min:1
  
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
  
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      sort = {id: "asc"}
      return = {type: "list"}
    } as $raw_cells
  
    // Build a lookup of stage id -> stage record and lens id -> lens record
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
  
    // Enrich cells with stage_key and lens_key for agent consumption
    var $cells {
      value = []
    }
  
    var $filled_count {
      value = 0
    }
  
    var $locked_count {
      value = 0
    }
  
    var $confirmed_count {
      value = 0
    }
  
    var $draft_count {
      value = 0
    }
  
    var $open_count {
      value = 0
    }
  
    foreach ($raw_cells) {
      each as $c {
        var $s_rec {
          value = $stage_map|get:($c.stage|to_text)
        }
      
        var $l_rec {
          value = $lens_map|get:($c.lens|to_text)
        }
      
        array.push $cells {
          value = {
            id           : $c.id
            stage_id     : $c.stage
            stage_key    : $s_rec.key
            lens_id      : $c.lens
            lens_key     : $l_rec.key
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
            var.update $filled_count {
              value = $filled_count + 1
            }
          }
        }
      
        conditional {
          if ($c.is_locked) {
            var.update $locked_count {
              value = $locked_count + 1
            }
          }
        }
      
        conditional {
          if ($c.status == "confirmed") {
            var.update $confirmed_count {
              value = $confirmed_count + 1
            }
          }
        
          elseif ($c.status == "draft") {
            var.update $draft_count {
              value = $draft_count + 1
            }
          }
        
          else {
            var.update $open_count {
              value = $open_count + 1
            }
          }
        }
      }
    }
  
    var $total_cells {
      value = $raw_cells|count
    }
  
    var $empty_cells {
      value = $total_cells - $filled_count
    }
  
    // ── Tool trace logging ──
    conditional {
      if ($input.conversation_id != null && $input.turn_id != null) {
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "get_map_state"
            tool_category : "read"
            input_summary : "Full map: " ~ $journey_map.title
            output_summary: $filled_count ~ " filled, " ~ $empty_cells ~ " empty, " ~ $locked_count ~ " locked"
          }
        } as $tool_log
      }
    }
  }

  response = {
    journey_map: ```
      {
        id        : $journey_map.id
        title     : $journey_map.title
        status    : $journey_map.status
        updated_at: $journey_map.updated_at
      }
      ```
    stages     : $stages
    lenses     : $lenses
    cells      : $cells
    summary    : ```
      {
        total_cells    : $total_cells
        filled_cells   : $filled_count
        empty_cells    : $empty_cells
        locked_cells   : $locked_count
        confirmed_cells: $confirmed_count
        draft_cells    : $draft_count
        open_cells     : $open_count
      }
      ```
  }
}