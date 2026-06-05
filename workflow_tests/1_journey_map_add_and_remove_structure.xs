// Covers add/remove stage and lens plus scaffolded cell cleanup.
// Adds a stage and lens, verifies scaffolded cell counts, then removes them and verifies cleanup.
workflow_test journey_map_add_and_remove_structure {
  stack {
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      input = {title: "Workflow Structure Test", status: "draft"}
    } as $draft
  
    var $journey_map_id {
      value = $draft.journey_map.id
    }
  
    api.call "journey_stage/add/{journey_map_id}" verb=POST {
      api_group = "journey-map"
      input = {journey_map_id: $journey_map_id, label: "Escalation"}
    } as $stage_add
  
    expect.to_equal ($stage_add.stage.label) {
      value = "Escalation"
    }
  
    expect.to_equal ($stage_add.cells|count) {
      value = 10
    }
  
    expect.to_be_defined ($stage_add.journey_map_updated_at)
    api.call "journey_lens/add/{journey_map_id}" verb=POST {
      api_group = "journey-map"
      input = {journey_map_id: $journey_map_id, label: "Automation"}
    } as $lens_add
  
    expect.to_equal ($lens_add.lens.label) {
      value = "Automation"
    }
  
    expect.to_equal ($lens_add.cells|count) {
      value = 9
    }
  
    expect.to_be_defined ($lens_add.journey_map_updated_at)
    api.call "journey_map/load_bundle/{journey_map_id}" verb=GET {
      api_group = "journey-map"
      input = {journey_map_id: $journey_map_id}
    } as $expanded_bundle
  
    expect.to_equal ($expanded_bundle.stages|count) {
      value = 9
    }
  
    expect.to_equal ($expanded_bundle.lenses|count) {
      value = 11
    }
  
    expect.to_equal ($expanded_bundle.cells|count) {
      value = 99
    }
  
    api.call "journey_lens/remove/{journey_lens_id}" verb=DELETE {
      api_group = "journey-map"
      input = {journey_lens_id: $lens_add.lens.id}
    } as $lens_remove
  
    expect.to_equal ($lens_remove.deleted_cell_count) {
      value = 9
    }
  
    expect.to_be_defined ($lens_remove.journey_map_updated_at)
    db.query journey_cell {
      where = $db.journey_cell.lens == $lens_add.lens.id
      return = {type: "list"}
    } as $removed_lens_cells
  
    expect.to_equal ($removed_lens_cells|count) {
      value = 0
    }
  
    api.call "journey_stage/remove/{journey_stage_id}" verb=DELETE {
      api_group = "journey-map"
      input = {journey_stage_id: $stage_add.stage.id}
    } as $stage_remove
  
    expect.to_equal ($stage_remove.deleted_cell_count) {
      value = 10
    }
  
    expect.to_be_defined ($stage_remove.journey_map_updated_at)
    db.query journey_cell {
      where = $db.journey_cell.stage == $stage_add.stage.id
      return = {type: "list"}
    } as $removed_stage_cells
  
    expect.to_equal ($removed_stage_cells|count) {
      value = 0
    }
  
    api.call "journey_map/load_bundle/{journey_map_id}" verb=GET {
      api_group = "journey-map"
      input = {journey_map_id: $journey_map_id}
    } as $final_bundle
  
    expect.to_equal ($final_bundle.stages|count) {
      value = 8
    }
  
    expect.to_equal ($final_bundle.lenses|count) {
      value = 10
    }
  
    expect.to_equal ($final_bundle.cells|count) {
      value = 80
    }
  }
}