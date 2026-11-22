// SAFE-1 (US-SAFE-1-01/02) — the ONE keep-or-clear rule for every AI tool that writes a cell.
// Pure: reads nothing, writes nothing. Given the stored cell and what the caller sent, it returns
// the final value of each writable field and the list of fields this call sets.
//
// The rule: a field is set only when the caller SENT it with a non-null value.
//   - left out        -> keep the stored value
//   - sent as null    -> keep the stored value ("nothing to say", not "clear")
//   - sent as ""      -> clear the text (an empty string is a real value)
//   - sent as 0       -> store 0 (a zero is a real value)
//
// Why it is written this way (probed live 2026-11-21, scratch/safe1_probe):
//   - `$obj|get:"k":null` gives null for BOTH a left-out key and a key sent as null, and the
//     real value otherwise; `??` is strict, so `(x ?? "__unset__") != "__unset__"` is true for
//     "", 0, false and objects, and false only for a real null.
//   - `$obj|has:"k"` is FALSE for a key sent as null, so it cannot tell "sent as null" apart
//     from "left out" and is not used here.
//   - `$input.x` cannot be used at all: an omitted optional text arrives as "" and an omitted
//     decimal as 0, which is how update_cell wiped text and zeroed times.
//
// actor_fields is a json column and db.patch MERGES json (CLAUDE.md). Passing an object here
// merges it into the stored one, exactly as fill_cells did before; that behaviour is kept.
function "journey/cell_merge_patch" {
  input {
    // The stored journey_cell row.
    json cell

    // What the caller sent: util.get_raw_input for update_cell, one list element for fill_cells
    // and batch_update.
    json patch
  }

  stack {
    var $fields_set {
      value = []
    }

    // ── content ──
    var $content_raw {
      value = $input.patch|get:"content":null
    }

    var $content_set {
      value = (($content_raw ?? "__unset__") != "__unset__")
    }

    var $content_final {
      value = $input.cell|get:"content":null
    }

    conditional {
      if ($content_set == true) {
        var.update $content_final {
          value = $content_raw|to_text|trim
        }

        array.push $fields_set {
          value = "content"
        }
      }
    }

    // ── actor_fields ──
    var $af_raw {
      value = $input.patch|get:"actor_fields":null
    }

    var $af_set {
      value = (($af_raw ?? "__unset__") != "__unset__")
    }

    var $af_final {
      value = $input.cell|get:"actor_fields":null
    }

    conditional {
      if ($af_set == true) {
        var.update $af_final {
          value = $af_raw
        }

        array.push $fields_set {
          value = "actor_fields"
        }
      }
    }

    // ── time_duration_value ──
    var $tdv_raw {
      value = $input.patch|get:"time_duration_value":null
    }

    var $tdv_set {
      value = (($tdv_raw ?? "__unset__") != "__unset__")
    }

    var $tdv_final {
      value = $input.cell|get:"time_duration_value":null
    }

    conditional {
      if ($tdv_set == true) {
        var.update $tdv_final {
          value = $tdv_raw
        }

        array.push $fields_set {
          value = "time_duration_value"
        }
      }
    }

    // ── time_duration_unit ──
    var $tdu_raw {
      value = $input.patch|get:"time_duration_unit":null
    }

    var $tdu_set {
      value = (($tdu_raw ?? "__unset__") != "__unset__")
    }

    var $tdu_final {
      value = $input.cell|get:"time_duration_unit":null
    }

    conditional {
      if ($tdu_set == true) {
        var.update $tdu_final {
          value = $tdu_raw
        }

        array.push $fields_set {
          value = "time_duration_unit"
        }
      }
    }

    // ── planned_duration ──
    var $pd_raw {
      value = $input.patch|get:"planned_duration":null
    }

    var $pd_set {
      value = (($pd_raw ?? "__unset__") != "__unset__")
    }

    var $pd_final {
      value = $input.cell|get:"planned_duration":null
    }

    conditional {
      if ($pd_set == true) {
        var.update $pd_final {
          value = $pd_raw
        }

        array.push $fields_set {
          value = "planned_duration"
        }
      }
    }

    // ── actual_duration ──
    var $ad_raw {
      value = $input.patch|get:"actual_duration":null
    }

    var $ad_set {
      value = (($ad_raw ?? "__unset__") != "__unset__")
    }

    var $ad_final {
      value = $input.cell|get:"actual_duration":null
    }

    conditional {
      if ($ad_set == true) {
        var.update $ad_final {
          value = $ad_raw
        }

        array.push $fields_set {
          value = "actual_duration"
        }
      }
    }

    var $set_count {
      value = $fields_set|count
    }
  }

  response = {
    data      : {
      content            : $content_final
      actor_fields       : $af_final
      time_duration_value: $tdv_final
      time_duration_unit : $tdu_final
      planned_duration   : $pd_final
      actual_duration    : $ad_final
    }
    fields_set: $fields_set
    set_count : $set_count
  }
}
