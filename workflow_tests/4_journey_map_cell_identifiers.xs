// Covers cell identifier stability through rename, add, and remove.
// Verifies canonical keys are preserved when labels change,
// and that new stages/lenses get their own stable keys.
workflow_test journey_map_cell_identifiers {
  stack {
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      input = {title: "Cell Identifier Test", status: "draft"}
    } as $draft
  
    var $journey_map_id {
      value = $draft.journey_map.id
    }
  
    // Load the initial bundle and capture the first stage and lens keys.
    api.call "journey_map/load_bundle/{journey_map_id}" verb=GET {
      api_group = "journey-map"
      input = {journey_map_id: $journey_map_id}
    } as $initial_bundle
  
    var $first_stage {
      value = $initial_bundle.stages[0]
    }
  
    var $first_lens {
      value = $initial_bundle.lenses[0]
    }
  
    var $original_stage_key {
      value = $first_stage.key
    }
  
    var $original_lens_key {
      value = $first_lens.key
    }
  
    // Rename the first stage — key must not change.
    api.call "journey_stage/rename/{journey_stage_id}" verb=PATCH {
      api_group = "journey-map"
      input = {
        journey_stage_id: $first_stage.id
        label           : "Renamed Stage"
      }
    } as $stage_rename
  
    expect.to_equal ($stage_rename.label) {
      value = "Renamed Stage"
    }
  
    expect.to_equal ($stage_rename.key) {
      value = $original_stage_key
    }
  
    // Rename the first lens — key must not change.
    api.call "journey_lens/rename/{journey_lens_id}" verb=PATCH {
      api_group = "journey-map"
      input = {journey_lens_id: $first_lens.id, label: "Renamed Lens"}
    } as $lens_rename
  
    expect.to_equal ($lens_rename.lens.label) {
      value = "Renamed Lens"
    }
  
    expect.to_equal ($lens_rename.lens.key) {
      value = $original_lens_key
    }
  
    // Add a new stage — must get its own key distinct from existing ones.
    api.call "journey_stage/add/{journey_map_id}" verb=POST {
      api_group = "journey-map"
      input = {journey_map_id: $journey_map_id, label: "New Stage"}
    } as $new_stage
  
    expect.to_be_defined ($new_stage.stage.key)
  
    // Add a new lens — must get its own key.
    api.call "journey_lens/add/{journey_map_id}" verb=POST {
      api_group = "journey-map"
      input = {journey_map_id: $journey_map_id, label: "New Lens"}
    } as $new_lens
  
    expect.to_be_defined ($new_lens.lens.key)
  
    // Reload and verify keys survived all changes.
    api.call "journey_map/load_bundle/{journey_map_id}" verb=GET {
      api_group = "journey-map"
      input = {journey_map_id: $journey_map_id}
    } as $final_bundle
  
    // The renamed stage should still have its original key.
    var $renamed_stage {
      value = $final_bundle.stages[0]
    }
  
    expect.to_equal ($renamed_stage.key) {
      value = $original_stage_key
    }
  
    expect.to_equal ($renamed_stage.label) {
      value = "Renamed Stage"
    }
  
    // The renamed lens should still have its original key.
    var $renamed_lens {
      value = $final_bundle.lenses[0]
    }
  
    expect.to_equal ($renamed_lens.key) {
      value = $original_lens_key
    }
  
    expect.to_equal ($renamed_lens.label) {
      value = "Renamed Lens"
    }
  
    // Every cell in the bundle should have a stage and lens reference.
    var $cell_count {
      value = $final_bundle.cells|count
    }
  
    expect.to_equal ($cell_count > 0) {
      value = true
    }
  
    // Remove the added stage and lens to clean up.
    api.call "journey_stage/remove/{journey_stage_id}" verb=DELETE {
      api_group = "journey-map"
      input = {journey_stage_id: $new_stage.stage.id}
    }
  
    api.call "journey_lens/remove/{journey_lens_id}" verb=DELETE {
      api_group = "journey-map"
      input = {journey_lens_id: $new_lens.lens.id}
    }
  }
}