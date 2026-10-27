// SC-MCP-01: MCP tool — set or clear stage_goal and primary_actor_lens on a journey stage.
// Validates that the stage exists and belongs to the given map before writing.
// "Clear" a field by passing null. Omitting a field keeps its existing value.
//
// BUG FOUND AND FIXED (STAGE-1, while wiring up US-STAGE-1-04): the original
// "omit = keep existing" logic checked `$input.field != null`, but an
// omitted optional text input arrives as "" here, never null — the same
// trap documented in CLAUDE.md for every other epic this session. That
// condition was always true, so every call that omitted a field was
// silently overwriting it with "". Fixed by reading $raw_input to tell
// omitted / explicit-null / explicit-value apart, for both fields.
//
// STAGE-1 (US-STAGE-1-04): whenever primary_actor_lens is explicitly set or
// cleared, owner_lens_id (journey_stage_owner) is kept in sync via the same
// resolve_stage_owner/set_stage_owner functions the stage PATCH endpoint
// uses, so a tool call and a UI edit never disagree about who owns a stage.
// A key that doesn't resolve to a lens in this map is left unsynced rather
// than thrown — the instructions already tell the caller to only use real
// keys from get_map, so this should not happen in practice.
tool update_stage_contract {
  instructions = "Set or clear the stage_goal (exit condition / definition of done) and/or primary_actor_lens (lens key of the accountable actor) on a specific stage. Always call get_map first to find journey_stage_id from stages[].xanoId and to look up lens keys from the cells[] array — never guess these values. primary_actor_lens must be a lens key (e.g. 'l1', 'l2'), NOT a lens label. To clear a field pass null. Read is free via get_map — only call this tool when writing."

  input {
    int journey_map_id filters=min:1
    int journey_stage_id filters=min:1
    text stage_goal? filters=trim
    text primary_actor_lens? filters=trim
  }

  stack {
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    // 1 — Load stage, verify it exists
    db.get journey_stage {
      field_name = "id"
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

    // 3 — Work out what the caller actually sent for each optional field.
    var $stage_goal_raw {
      value = $raw_input|get:"stage_goal":"__absent__"
    }

    var $has_stage_goal {
      value = ($stage_goal_raw != "__absent__")
    }

    var $stage_goal_to_write {
      value = $stage.stage_goal
    }

    conditional {
      if ($has_stage_goal == true) {
        var.update $stage_goal_to_write {
          value = ($stage_goal_raw == null ? null : $input.stage_goal)
        }
      }
    }

    var $lens_raw {
      value = $raw_input|get:"primary_actor_lens":"__absent__"
    }

    var $has_lens {
      value = ($lens_raw != "__absent__")
    }

    var $clearing_lens {
      value = ($has_lens == true && $lens_raw == null)
    }

    var $primary_actor_lens_to_write {
      value = $stage.primary_actor_lens
    }

    conditional {
      if ($has_lens == true) {
        var.update $primary_actor_lens_to_write {
          value = ($clearing_lens == true ? null : $input.primary_actor_lens)
        }
      }
    }

    // 4 — Write; preserve existing label and any field not explicitly passed.
    db.edit journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
      enforce_hidden_fields = false
      data = {
        updated_at        : "now"
        label             : $stage.label
        stage_goal        : $stage_goal_to_write
        primary_actor_lens: $primary_actor_lens_to_write
      }
    } as $updated

    // 5 — Keep owner_lens_id in sync whenever primary_actor_lens was explicitly touched.
    conditional {
      if ($has_lens == true && $clearing_lens == false) {
        function.run "resolve_stage_owner" {
          input = {
            journey_map_id    : $input.journey_map_id
            primary_actor_lens: $input.primary_actor_lens
          }
        } as $resolution

        conditional {
          if ($resolution.resolved == true) {
            // ITEM-1 (US-ITEM-1-06, audit finding O-1) — resolve_stage_owner
            // is a pure lookup with no actor filter, so it WILL hand back
            // the Items row if a stage names it. The ban belongs here, at
            // the write path, same as endpoint 211.
            db.get journey_lens {
              field_name = "id"
              field_value = $resolution.owner_lens_id
            } as $owner_lens_check

            precondition ($owner_lens_check.template_key != "items-v1") {
              error_type = "inputerror"
              error = "The Items row can't own a stage — pick a person or team row. (E-ITM-007)"
            }

            function.run "set_stage_owner" {
              input = {
                journey_stage_id: $input.journey_stage_id
                owner_lens_id   : $resolution.owner_lens_id
              }
            } as $owner_write
          }
        }
      }

      elseif ($clearing_lens == true) {
        function.run "set_stage_owner" {
          input = {
            journey_stage_id: $input.journey_stage_id
          }
        } as $owner_write
      }
    }

    db.query journey_stage_owner {
      where = $db.journey_stage_owner.journey_stage == $input.journey_stage_id
      return = {type: "list"}
    } as $owner_rows

    var $owner_lens_id {
      value = null
    }

    foreach ($owner_rows) {
      each as $row {
        var.update $owner_lens_id {
          value = $row.owner_lens_id
        }
      }
    }
  }

  response = {
    id                : $updated.id
    journey_map       : $updated.journey_map
    key               : $updated.key
    label             : $updated.label
    stage_goal        : $updated.stage_goal
    primary_actor_lens: $updated.primary_actor_lens
    owner_lens_id     : $owner_lens_id
    updated_at        : $updated.updated_at
  }

  guid = "B8Ah3KfuIyani33A4iCPcDLgsaU"
}
