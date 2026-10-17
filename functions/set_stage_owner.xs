// STAGE-1 (US-STAGE-1-02/03/04) — Upserts or clears the one
// journey_stage_owner row for a stage. owner_lens_id omitted or 0
// clears the owner (0 is never a real lens id, so no separate
// has_X flag is needed here, unlike a decimal where 0 is a valid
// value — see TIME-1's duration_to_minutes for that case).
function "set_stage_owner" {
  description = "Upserts journey_stage_owner for one stage, or deletes its row when no owner_lens_id is given."

  input {
    int journey_stage_id filters=min:1
    int owner_lens_id?
  }

  stack {
    var $has_owner {
      value = ($input.owner_lens_id != null && $input.owner_lens_id != 0)
    }

    db.query journey_stage_owner {
      where = $db.journey_stage_owner.journey_stage == $input.journey_stage_id
      return = {type: "list"}
    } as $existing_rows

    var $existing_id {
      value = null
    }

    foreach ($existing_rows) {
      each as $row {
        var.update $existing_id {
          value = $row.id
        }
      }
    }

    conditional {
      if ($has_owner == true) {
        conditional {
          if ($existing_id != null) {
            db.edit journey_stage_owner {
              field_name = "id"
              field_value = $existing_id
              data = {owner_lens_id: $input.owner_lens_id, updated_at: "now"}
            } as $saved
          }

          else {
            db.add journey_stage_owner {
              data = {journey_stage: $input.journey_stage_id, owner_lens_id: $input.owner_lens_id}
            } as $saved
          }
        }
      }

      else {
        conditional {
          if ($existing_id != null) {
            db.del journey_stage_owner {
              field_name = "id"
              field_value = $existing_id
            }
          }
        }
      }
    }
  }

  response = {owner_lens_id: ($has_owner == true ? $input.owner_lens_id : null)}
}
