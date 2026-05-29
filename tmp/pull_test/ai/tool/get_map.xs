// IL-00-07: MCP tool — get full map state.
// Thin wrapper over the existing get_map_state tool logic.
// Returns stages, lenses, cells, fill status.
tool get_map {
  instructions = "Read the full current state of a journey map: stages, lenses, cells with content and status. Pass journey_map_id. Returns the complete map bundle plus a fill summary."

  input {
    int journey_map_id filters=min:1
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
  
    // Build stage and lens lookup maps
    var $stage_index {
      value = {}
    }
  
    foreach ($stages) {
      each as $s {
        var.update $stage_index {
          value = $stage_index|set:($s.id|to_text):$s
        }
      }
    }
  
    var $lens_index {
      value = {}
    }
  
    foreach ($lenses) {
      each as $l {
        var.update $lens_index {
          value = $lens_index|set:($l.id|to_text):$l
        }
      }
    }
  
    // Enrich cells
    var $cells {
      value = []
    }
  
    var $filled {
      value = 0
    }
  
    foreach ($raw_cells) {
      each as $c {
        var $s_rec {
          value = $stage_index|get:($c.stage|to_text)
        }
      
        var $l_rec {
          value = $lens_index|get:($c.lens|to_text)
        }
      
        array.push $cells {
          value = {
            id          : $c.id
            stage_key   : $s_rec.key
            lens_key    : $l_rec.key
            actor_type  : $l_rec.actor_type
            actor_fields: $c.actor_fields
            content     : $c.content
            status      : $c.status
            is_locked   : $c.is_locked
          }
        }
      
        conditional {
          if ($c.content != null && $c.content != "") {
            var.update $filled {
              value = $filled + 1
            }
          }
        }
      }
    }
  
    var $total {
      value = $raw_cells|count
    }
  }

  response = {
    journey_map: ```
      {
        id        : $journey_map.id
        title     : $journey_map.title
        status    : $journey_map.status
        intent    : $journey_map.intent
        ai_summary: $journey_map.ai_summary
      }
      ```
    stages     : $stages
    lenses     : $lenses
    cells      : $cells
    summary    : ```
      {
        total_cells : $total
        filled_cells: $filled
        empty_cells : $total - $filled
      }
      ```
  }

  guid = "IL00GetMapTool000000000001"
}