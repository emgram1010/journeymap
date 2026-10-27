// Update journey_stage label, stage_goal, and primary_actor_lens in one call.
// Validates label is non-empty; stage_goal and primary_actor_lens are optional and nullable.
// Also touches journey_map.updated_at and last_interaction_at.
//
// STAGE-1 (US-STAGE-1-03): owner_lens_id is the new, validated way to set
// the stage's owner (checked via $raw_input, since an omitted optional int
// arrives as 0 — see CLAUDE.md). When provided, it must be a lens on the
// SAME map as the stage; the legacy primary_actor_lens text field is kept
// in sync automatically (set to the resolved lens's key) so old readers of
// that field see the same owner the new journey_stage_owner row has.
// owner_lens_id omitted entirely leaves ownership untouched — a plain
// label/goal edit never clears it.
query "journey_stage/update/{journey_stage_id}" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_stage_id? filters=min:1
    text label? filters=trim
    text stage_goal? filters=trim
    text primary_actor_lens? filters=trim
    int owner_lens_id?
  }

  stack {
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    precondition ($input.label != null && $input.label != "") {
      error_type = "inputerror"
      error = "Stage label is required"
    }

    db.get journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
    } as $existing_stage

    precondition ($existing_stage != null) {
      error_type = "notfound"
      error = "Journey stage not found"
    }

    var $has_owner_lens_id {
      value = $raw_input|has:"owner_lens_id"
    }

    var $clearing_owner {
      value = ($has_owner_lens_id == true && ($input.owner_lens_id == null || $input.owner_lens_id == 0))
    }

    var $owner_lens {
      value = null
    }

    conditional {
      if ($has_owner_lens_id == true && $clearing_owner == false) {
        db.get journey_lens {
          field_name = "id"
          field_value = $input.owner_lens_id
        } as $owner_lens_lookup

        precondition ($owner_lens_lookup != null && $owner_lens_lookup.journey_map == $existing_stage.journey_map) {
          error_type = "inputerror"
          error = "Pick an owner from this map's rows. (E-STAGE-001)"
        }

        // ITEM-1 (US-ITEM-1-06, audit finding O-1) — resolve_stage_owner
        // and this lookup are pure, unfiltered by row kind on purpose; the
        // ban on the Items row owning a stage belongs at the write path.
        precondition ($owner_lens_lookup.template_key != "items-v1") {
          error_type = "inputerror"
          error = "The Items row can't own a stage — pick a person or team row. (E-ITM-007)"
        }

        var.update $owner_lens {
          value = $owner_lens_lookup
        }
      }
    }

    var $primary_actor_lens_to_write {
      value = $input.primary_actor_lens
    }

    conditional {
      if ($owner_lens != null) {
        var.update $primary_actor_lens_to_write {
          value = $owner_lens.key
        }
      }

      elseif ($clearing_owner == true) {
        var.update $primary_actor_lens_to_write {
          value = ""
        }
      }
    }

    db.edit journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
      enforce_hidden_fields = false
      data = {
        label             : $input.label
        stage_goal        : $input.stage_goal
        primary_actor_lens: $primary_actor_lens_to_write
        updated_at        : "now"
      }
    } as $journey_stage

    conditional {
      if ($has_owner_lens_id == true) {
        function.run "set_stage_owner" {
          input = {
            journey_stage_id: $input.journey_stage_id
            owner_lens_id   : $clearing_owner == true ? null : $input.owner_lens_id
          }
        } as $owner_write
      }
    }

    db.patch journey_map {
      field_name = "id"
      field_value = $existing_stage.journey_map
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $journey_map_touch_patch

    precondition ($journey_map_touch_patch != null) {
      error = "Failed to update journey map"
    }

    db.get journey_map {
      field_name = "id"
      field_value = $existing_stage.journey_map
    } as $journey_map_touch

    // Always report the CURRENT owner, not just what this call touched —
    // a plain label/goal edit must not make an existing owner look cleared.
    db.query journey_stage_owner {
      where = $db.journey_stage_owner.journey_stage == $input.journey_stage_id
      return = {type: "list"}
    } as $current_owner_rows

    var $current_owner_lens_id {
      value = null
    }

    foreach ($current_owner_rows) {
      each as $row {
        var.update $current_owner_lens_id {
          value = $row.owner_lens_id
        }
      }
    }
  }

  response = $journey_stage
    |set:"journey_map_updated_at":$journey_map_touch.updated_at
    |set:"owner_lens_id":$current_owner_lens_id
}