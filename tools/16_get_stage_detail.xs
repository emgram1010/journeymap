// Reads all lens cells for a given stage in a journey map, including content and actor_fields.
// Used by the Journey Compare Analyst to explain why a stage health score is low.
// This tool is READ-ONLY — it never writes to any cell.
tool get_stage_detail {
  instructions = """
      Use this tool when the user asks WHY a specific stage scores differently between two scenarios,
      or when you need to understand the underlying qualitative data behind a stage health score.
    
      It returns every lens row for the given stage + map, including cell content (Notes) and all
      structured actor_fields (e.g. emotions, friction_points, error_rate). Use the output to cite
      specific evidence when explaining score differences.
    
      Input:
      - journey_map_id: The ID of the map you want to inspect (use map_a_id or map_b_id from context)
      - stage_key: The key of the stage to inspect (e.g. "discovery", "resolution_attempt")
      - conversation_id: (optional) for tool trace logging
      - turn_id: (optional) for tool trace logging
    
      Response shape:
      {
        stage_label: string,
        stage_key: string,
        map_id: number,
        lenses: [
          {
            lens_key: string,
            lens_label: string,
            actor_type: string | null,
            content: string | null,
            actor_fields: object | null
          }
        ]
      }
    
      Returns an empty lenses array if the stage_key is not found.
    """

  input {
    int journey_map_id filters=min:1
    text stage_key filters=trim
    int conversation_id?
    text turn_id?
  }

  stack {
    // Resolve stage
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id && $db.journey_stage.key == $input.stage_key
      return = {type: "single"}
    } as $stage
  
    var $lenses_out {
      value = []
    }
  
    conditional {
      if ($stage != null) {
        // Load all lenses for this map
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id
          sort = {display_order: "asc"}
          return = {type: "list"}
        } as $all_lenses
      
        // For each lens, find the cell at this stage
        foreach ($all_lenses) {
          each as $lens {
            db.query journey_cell {
              where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $lens.id
              return = {type: "single"}
            } as $cell
          
            var $cell_content {
              value = null
            }
          
            var $cell_fields {
              value = null
            }
          
            conditional {
              if ($cell != null) {
                var.update $cell_content {
                  value = $cell.content
                }
              
                var.update $cell_fields {
                  value = $cell.actor_fields
                }
              }
            }
          
            array.push $lenses_out {
              value = {
                lens_key    : $lens.key
                lens_label  : $lens.label
                actor_type  : $lens.actor_type
                content     : $cell_content
                actor_fields: $cell_fields
              }
            }
          }
        }
      }
    }
  
    var $result {
      value = {
        stage_label: ($stage != null ? $stage.label : $input.stage_key)
        stage_key  : $input.stage_key
        map_id     : $input.journey_map_id
        lenses     : $lenses_out
      }
    }
  }

  response = $result
}