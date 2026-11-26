// REQ-1 story 04 — THE one rule for putting a need on a STEP of the map (one cell = one stage of one row): used by the single-step endpoint and by "apply to the whole row", so the two can never disagree. A step has needs only if its ROW does planned work (the shared rule `does_planned_work`: an explicit override wins, otherwise internal and AI rows do and the rest do not) -> E-REQ-031; a LOCKED step refuses, with the same plain message other edits to a locked cell get -> E-REQ-033; an ARCHIVED requirement cannot be newly added (but its strength can change where it is already set) -> E-REQ-030; at most 10 needs on a step -> E-REQ-032; strength is hard or soft. Adding the same need again updates its strength and is not an error. Returns a RESULT, not an exception, so the row-wide call can count what changed and what was skipped: result is added | changed | same | refused, with code and message when refused. WRITE-ONLY on success: tenancy is the caller's job (journey/assert_map_owner on the cell's map, and req/assert_requirement for the requirement), checked BEFORE this runs. A draft edit: it changes nothing for jobs until the map is published (story 05). Every input is passed explicitly by callers.
function "req/set_need" {
  input {
    int account_id filters=min:1
    int user_id?
    int journey_cell_id filters=min:1
    int requirement_id filters=min:1
    text strength filters=trim
  }

  stack {
    db.query journey_cell {
      where = $db.journey_cell.id == $input.journey_cell_id
      return = {type: "single"}
    } as $cell

    var $cell_id {
      value = $cell|get:"id":0
    }

    var $lens_id {
      value = $cell|get:"lens":0
    }

    var $map_id {
      value = $cell|get:"journey_map":0
    }

    var $locked {
      value = ($cell|get:"is_locked":false) == true
    }

    db.query journey_lens {
      where = $db.journey_lens.id == $lens_id
      return = {type: "single"}
    } as $lens

    var $lens_actor_type {
      value = $lens|get:"actor_type":""
    }

    // THE one rule for "does this row do planned work": an explicit override wins, otherwise the default by actor type.
    function.run "does_planned_work" {
      input = {journey_lens_id: $lens_id, actor_type: $lens_actor_type}
    } as $planned_rule

    var $planned_rows {
      value = ($planned_rule.does_planned_work == true)|to_int
    }

    db.query requirement {
      where = $db.requirement.id == $input.requirement_id && $db.requirement.account_id == $input.account_id
      return = {type: "single"}
    } as $req

    var $req_active {
      value = ($req|get:"is_active":false) == true
    }

    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.journey_cell_id == $input.journey_cell_id
      return = {type: "list"}
      output = ["id", "requirement_id", "strength"]
    } as $current

    var $current_n {
      value = $current|count
    }

    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.journey_cell_id == $input.journey_cell_id && $db.journey_cell_requirement.requirement_id == $input.requirement_id
      return = {type: "single"}
    } as $same_req

    var $same_id {
      value = $same_req|get:"id":0
    }

    var $same_strength {
      value = $same_req|get:"strength":""
    }

    var $code {
      value = ""
    }

    var $message {
      value = ""
    }

    var $strength_ok {
      value = ($input.strength == "hard") || ($input.strength == "soft")
    }

    // Most serious last, so the one left standing is the first the person must fix.
    conditional {
      if ($same_id == 0 && $current_n >= 10) {
        var.update $code {
          value = "E-REQ-032"
        }

        var.update $message {
          value = "A step can have at most 10 needs. (E-REQ-032)"
        }
      }
    }

    conditional {
      if ($same_id == 0 && $req_active == false) {
        var.update $code {
          value = "E-REQ-030"
        }

        var.update $message {
          value = "That requirement is archived, so it cannot be added to a step. (E-REQ-030)"
        }
      }
    }

    conditional {
      if ($planned_rows == 0) {
        var.update $code {
          value = "E-REQ-031"
        }

        var.update $message {
          value = "This row is not marked as planned work, so its steps cannot have needs. Mark the row as planned work first. (E-REQ-031)"
        }
      }
    }

    conditional {
      if ($locked == true) {
        var.update $code {
          value = "E-REQ-033"
        }

        var.update $message {
          value = "This step is locked, so it can't be changed. Unlock it first. (E-REQ-033)"
        }
      }
    }

    conditional {
      if ($strength_ok == false) {
        var.update $code {
          value = "E-REQ-034"
        }

        var.update $message {
          value = "A need is either a must (hard) or a preference (soft). (E-REQ-034)"
        }
      }
    }

    conditional {
      if ($cell_id == 0) {
        var.update $code {
          value = "E-REQ-035"
        }

        var.update $message {
          value = "That step was not found. (E-REQ-035)"
        }
      }
    }

    var $result {
      value = "refused"
    }

    conditional {
      if ($code == "" && $same_id == 0) {
        db.add journey_cell_requirement {
          data = {
            account_id     : $input.account_id
            journey_map_id : $map_id
            journey_cell_id: $input.journey_cell_id
            requirement_id : $input.requirement_id
            strength       : $input.strength
            updated_by     : $input.user_id
            updated_at     : "now"
          }
        } as $added

        var.update $result {
          value = "added"
        }
      }

      elseif ($code == "" && $same_strength != $input.strength) {
        db.patch journey_cell_requirement {
          field_name = "id"
          field_value = $same_id
          data = {strength: $input.strength, updated_by: $input.user_id, updated_at: "now"}
        } as $changed

        var.update $result {
          value = "changed"
        }
      }

      elseif ($code == "") {
        var.update $result {
          value = "same"
        }
      }
    }
  }

  response = {result: $result, code: $code, message: $message, map_id: $map_id}
}
