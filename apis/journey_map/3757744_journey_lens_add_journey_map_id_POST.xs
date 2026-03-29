// Add a journey lens and scaffold matching cells for all stages in the map.
query "journey_lens/add/{journey_map_id}" verb=POST {
  api_group = "journey-map"

  input {
    int journey_map_id? filters=min:1
    text label? filters=trim
  }

  stack {
    var $cells {
      value = []
    }
  
    var $next_lens_order {
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
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "desc"}
      return = {type: "list"}
    } as $existing_lenses
  
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $existing_stages
  
    precondition (($existing_stages|count) > 0) {
      error_type = "inputerror"
      error = "Journey map must include at least one stage before adding a lens"
    }
  
    conditional {
      if (($existing_lenses|count) > 0) {
        var.update $next_lens_order {
          value = $existing_lenses
            |first
            |get:"display_order"
            |add:1
        }
      }
    }
  
    var $lens_label {
      value = "New Lens %d"|sprintf:$next_lens_order
    }
  
    conditional {
      if ($input.label != null) {
        precondition ($input.label != "") {
          error_type = "inputerror"
          error = "Lens label is required"
        }
      
        var.update $lens_label {
          value = $input.label
        }
      }
    }
  
    var $lens_key {
      value = "lens-%d"|sprintf:$next_lens_order
    }
  
    db.add journey_lens {
      data = {
        created_at   : "now"
        updated_at   : "now"
        journey_map  : $input.journey_map_id
        key          : $lens_key
        label        : $lens_label
        display_order: $next_lens_order
      }
    } as $journey_lens
  
    foreach ($existing_stages) {
      each as $stage {
        db.add journey_cell {
          data = {
            created_at : "now"
            updated_at : "now"
            journey_map: $input.journey_map_id
            stage      : $stage.id
            lens       : $journey_lens.id
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
    } as $journey_map_touch
  }

  response = {
    lens                  : $journey_lens
    cells                 : $cells
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}