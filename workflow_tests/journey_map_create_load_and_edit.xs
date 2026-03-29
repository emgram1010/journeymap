// Covers create_draft, load_bundle, journey_cell/update, and rename endpoints.
workflow_test journey_map_create_load_and_edit {
  description = "Creates a draft journey map, reloads it, edits a cell, and renames the first stage and lens."

  stack {
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      headers = ""
      input = {title: "Workflow Test Draft", status: "draft"}
    } as $draft

    var $journey_map_id {
      value = $draft.journey_map.id
    }

    var $first_stage {
      value = $draft.stages|first
    }

    var $first_lens {
      value = $draft.lenses|first
    }

    var $first_cell {
      value = $draft.cells|first
    }

    expect.to_equal ($draft.journey_map.title) {
      value = "Workflow Test Draft"
    }

    expect.to_equal ($draft.journey_map.status) {
      value = "draft"
    }

    expect.to_equal ($draft.stages|count) {
      value = 8
    }

    expect.to_equal ($draft.lenses|count) {
      value = 10
    }

    expect.to_equal ($draft.cells|count) {
      value = 80
    }

    api.call "journey_map/load_bundle/{journey_map_id}" verb=GET {
      api_group = "journey-map"
      headers = ""
      input = {journey_map_id: $journey_map_id}
    } as $bundle

    expect.to_equal ($bundle.stages|count) {
      value = 8
    }

    expect.to_equal ($bundle.lenses|count) {
      value = 10
    }

    expect.to_equal ($bundle.cells|count) {
      value = 80
    }

    expect.to_be_null ($bundle.conversation)

    expect.to_equal ($bundle.messages|count) {
      value = 0
    }

    api.call "journey_cell/update/{journey_cell_id}" verb=PATCH {
      api_group = "journey-map"
      headers = ""
      input = {
        journey_cell_id: $first_cell.id
        content: "Workflow test content"
        status: "draft"
      }
    } as $cell_update

    expect.to_equal ($cell_update.content) {
      value = "Workflow test content"
    }

    expect.to_equal ($cell_update.status) {
      value = "draft"
    }

    expect.to_equal ($cell_update.change_source) {
      value = "user"
    }

    expect.to_be_defined ($cell_update.journey_map_updated_at)

    api.call "journey_stage/rename/{journey_stage_id}" verb=PATCH {
      api_group = "journey-map"
      headers = ""
      input = {
        journey_stage_id: $first_stage.id
        label: "Discovery"
      }
    } as $stage_rename

    expect.to_equal ($stage_rename.label) {
      value = "Discovery"
    }

    expect.to_be_defined ($stage_rename.journey_map_updated_at)

    api.call "journey_lens/rename/{journey_lens_id}" verb=PATCH {
      api_group = "journey-map"
      headers = ""
      input = {
        journey_lens_id: $first_lens.id
        label: "Workflow Lens"
      }
    } as $lens_rename

    expect.to_equal ($lens_rename.lens.label) {
      value = "Workflow Lens"
    }

    expect.to_be_defined ($lens_rename.journey_map_updated_at)

    db.get journey_cell {
      field_name = "id"
      field_value = $first_cell.id
    } as $persisted_cell

    expect.to_equal ($persisted_cell.content) {
      value = "Workflow test content"
    }

    expect.to_equal ($persisted_cell.status) {
      value = "draft"
    }

    expect.to_equal ($persisted_cell.change_source) {
      value = "user"
    }

    db.get journey_stage {
      field_name = "id"
      field_value = $first_stage.id
    } as $persisted_stage

    expect.to_equal ($persisted_stage.label) {
      value = "Discovery"
    }

    db.get journey_lens {
      field_name = "id"
      field_value = $first_lens.id
    } as $persisted_lens

    expect.to_equal ($persisted_lens.label) {
      value = "Workflow Lens"
    }
  }
}