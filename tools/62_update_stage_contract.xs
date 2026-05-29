// SC-MCP-01: MCP tool — set or clear stage_goal and primary_actor_lens on a journey stage.
// Validates that the stage exists and belongs to the given map before writing.
// "Clear" a field by passing null. label is preserved from the existing record.
tool update_stage_contract {
  instructions = "Set or clear the stage_goal (exit condition / definition of done) and/or primary_actor_lens (lens key of the accountable actor) on a specific stage. Always call get_map first to find journey_stage_id from stages[].xanoId and to look up lens keys from the cells[] array — never guess these values. primary_actor_lens must be a lens key (e.g. 'l1', 'l2'), NOT a lens label. To clear a field pass null. Read is free via get_map — only call this tool when writing."

  input {
    int journey_map_id      filters=min:1
    int journey_stage_id    filters=min:1
    text stage_goal?        filters=trim
    text primary_actor_lens? filters=trim
  }

  stack {
    // 1 — Load stage, verify it exists
    db.get journey_stage {
      field_name  = "id"
      field_value = $input.journey_stage_id
    } as $stage

    precondition ($stage != null) {
      error_type = "notfound"
      error = "Stage not found"
    }

    // 2 — Verify stage belongs to the given map
    precondition ($stage.journey_map == $input.journey_map_id) {
      error_type = "inputerror"
      error = "Stage does not belong to this journey map"
    }

    // 3 — Write; preserve existing label (endpoint 211 requires it non-null)
    db.edit journey_stage {
      field_name  = "id"
      field_value = $input.journey_stage_id
      data = {
        updated_at          : "now"
        label               : $stage.label
        stage_goal          : $input.stage_goal
        primary_actor_lens  : $input.primary_actor_lens
      }
    } as $updated
  }

  response = {
    id                 : $updated.id
    journey_map        : $updated.journey_map
    key                : $updated.key
    label              : $updated.label
    stage_goal         : $updated.stage_goal
    primary_actor_lens : $updated.primary_actor_lens
    updated_at         : $updated.updated_at
  }
  guid = "B8Ah3KfuIyani33A4iCPcDLgsaU"
}
