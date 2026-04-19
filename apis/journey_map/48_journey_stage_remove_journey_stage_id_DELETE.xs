// Remove a journey stage and all of its cells while preserving minimum matrix structure.
query "journey_stage/remove/{journey_stage_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_stage_id? filters=min:1
  }

  stack {
    db.get journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
    } as $journey_stage
  
    precondition ($journey_stage != null) {
      error_type = "notfound"
      error = "Journey stage not found"
    }
  
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $journey_stage.journey_map
      return = {type: "list"}
    } as $map_stages
  
    precondition (($map_stages|count) > 1) {
      error_type = "inputerror"
      error = "Journey map must keep at least one stage"
    }
  
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $journey_stage.journey_map && $db.journey_cell.stage == $journey_stage.id
      return = {type: "list"}
    } as $stage_cells
  
    foreach ($stage_cells) {
      each as $cell {
        db.del journey_cell {
          field_name = "id"
          field_value = $cell.id
        }
      }
    }
  
    db.del journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
    }
  
    db.patch journey_map {
      field_name = "id"
      field_value = $journey_stage.journey_map
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch_patch
  
    precondition ($journey_map_touch_patch != null) {
      error = "Failed to update journey map"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $journey_stage.journey_map
    } as $journey_map_touch
  }

  response = {
    stage                 : $journey_stage
    deleted_cell_count    : $stage_cells|count
    journey_map_updated_at: $journey_map_touch.updated_at
  }
}