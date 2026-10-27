// STAGE-1 (US-STAGE-1-06) — Upserts or clears the one
// journey_lens_planned_work row for a lens. Clearing (does_planned_work
// omitted/null) deletes the row, restoring the actor_type default.
function "set_lens_planned_work" {
  description = "Upserts journey_lens_planned_work for one lens, or deletes its row to restore the type default."

  input {
    int journey_lens_id filters=min:1
    bool does_planned_work?
    bool clear?
  }

  stack {
    // ITEM-1 (US-ITEM-1-06, audit finding P-1) — does_planned_work
    // honours any explicit override, including true, and nothing else in
    // the shared predicate stops the Items row being switched on. Writing
    // `does_planned_work: false` for the Items row (ITEM-1's own create
    // endpoint) stays allowed; only an explicit TRUE on an items-v1 lens
    // is refused.
    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $target_lens

    precondition ($target_lens != null) {
      error_type = "notfound"
      error = "Lens not found"
    }

    precondition ($target_lens.template_key != "items-v1" || $input.does_planned_work != true) {
      error_type = "inputerror"
      error = "The Items row doesn't do planned work; that switch stays off. (E-ITM-008)"
    }

    db.query journey_lens_planned_work {
      where = $db.journey_lens_planned_work.journey_lens == $input.journey_lens_id
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
      if ($input.clear == true) {
        conditional {
          if ($existing_id != null) {
            db.del journey_lens_planned_work {
              field_name = "id"
              field_value = $existing_id
            }
          }
        }
      }

      else {
        conditional {
          if ($existing_id != null) {
            db.edit journey_lens_planned_work {
              field_name = "id"
              field_value = $existing_id
              data = {does_planned_work: $input.does_planned_work, updated_at: "now"}
            } as $saved
          }

          else {
            db.add journey_lens_planned_work {
              data = {journey_lens: $input.journey_lens_id, does_planned_work: $input.does_planned_work}
            } as $saved
          }
        }
      }
    }
  }

  response = {does_planned_work: ($input.clear == true ? null : $input.does_planned_work)}
}
