// Add a journey stage and scaffold matching cells for all lenses in the map.
query "journey_stage/add/{journey_map_id}" verb=POST {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
    text label? filters=trim
  }

  stack {
    var $cells {
      value = []
    }
  
    var $next_stage_order {
      value = 1
    }
  
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
      sort = {display_order: "desc"}
      return = {type: "list"}
    } as $existing_stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $existing_lenses
  
    precondition (($existing_lenses|count) > 0) {
      error_type = "inputerror"
      error = "Journey map must include at least one lens before adding a stage"
    }
  
    conditional {
      if (($existing_stages|count) > 0) {
        var.update $next_stage_order {
          value = $existing_stages
            |first
            |get:"display_order"
            |add:1
        }
      }
    }
  
    var $stage_label {
      value = "Stage %d"|sprintf:$next_stage_order
    }
  
    conditional {
      if ($input.label != null) {
        precondition ($input.label != "") {
          error_type = "inputerror"
          error = "Stage label is required"
        }
      
        var.update $stage_label {
          value = $input.label
        }
      }
    }
  
    var $stage_key {
      value = "s%d"|sprintf:$next_stage_order
    }
  
    db.add journey_stage {
      data = {
        created_at   : "now"
        updated_at   : "now"
        journey_map  : $input.journey_map_id
        key          : $stage_key
        label        : $stage_label
        display_order: $next_stage_order
      }
    } as $journey_stage
  
    foreach ($existing_lenses) {
      each as $lens {
        db.add journey_cell {
          data = {
            created_at : "now"
            updated_at : "now"
            journey_map: $input.journey_map_id
            stage      : $journey_stage.id
            lens       : $lens.id
            content    : ""
            status     : "open"
            is_locked  : false
          }
        } as $cell
      
        array.push $cells {
          value = $cell
        }
      }
    }
  
    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch_patch
  
    precondition ($journey_map_touch_patch != null) {
      error = "Failed to update journey map"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map_touch
  }

  response = {
    stage                 : $journey_stage
    cells                 : $cells
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}