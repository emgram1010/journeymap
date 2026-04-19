// Remove a journey lens and all of its cells while preserving minimum matrix structure.
query "journey_lens/remove/{journey_lens_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_lens_id? filters=min:1
  }

  stack {
    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $journey_lens
  
    precondition ($journey_lens != null) {
      error_type = "notfound"
      error = "Journey lens not found"
    }
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $journey_lens.journey_map
      return = {type: "list"}
    } as $map_lenses
  
    precondition (($map_lenses|count) > 1) {
      error_type = "inputerror"
      error = "Journey map must keep at least one lens"
    }
  
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $journey_lens.journey_map && $db.journey_cell.lens == $journey_lens.id
      return = {type: "list"}
    } as $lens_cells
  
    foreach ($lens_cells) {
      each as $cell {
        db.del journey_cell {
          field_name = "id"
          field_value = $cell.id
        }
      }
    }
  
    db.del journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    }
  
    db.patch journey_map {
      field_name = "id"
      field_value = $journey_lens.journey_map
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch
  }

  response = {
    lens                  : $journey_lens
    deleted_cell_count    : $lens_cells|count
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}