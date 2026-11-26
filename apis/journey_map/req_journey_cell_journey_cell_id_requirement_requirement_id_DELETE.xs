// REQ-1 story 04 — Take a need off ONE step. A DRAFT edit: published versions keep what they froze (story 05). A locked step refuses with the same plain message as adding (E-REQ-033). Removing a need the step does not have is not an error (removed: false). The cell's map must belong to the caller's account (journey/assert_map_owner): another account's is "not found". The row is deleted by its own id. Event: step.need_removed (map, stage key, row key, requirement, actor). Every input is passed to function.run explicitly.
query "journey_cell/{journey_cell_id}/requirement/{requirement_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_cell_id filters=min:1
    int requirement_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.query journey_cell {
      where = $db.journey_cell.id == $input.journey_cell_id
      return = {type: "single"}
    } as $cell

    var $map_id {
      value = $cell|get:"journey_map":0
    }

    precondition ($map_id != 0) {
      error_type = "notfound"
      error = "That step was not found. (E-REQ-035)"
    }

    function.run "journey/assert_map_owner" {
      input = {journey_map_id: $map_id, caller_account_id: $actor.account_id, user_id: $auth.id, step: "step_need_remove"}
    } as $_owner

    var $locked {
      value = ($cell|get:"is_locked":false) == true
    }

    var $locked_msg {
      value = "This step is locked, so it can't be changed. Unlock it first. (E-REQ-033)"
    }

    conditional {
      if ($locked == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "step.need_remove"
            outcome       : "rejected"
            severity      : "info"
            error_code    : "E-REQ-033"
            message       : $locked_msg
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "journey_cell"
            entity_id     : $input.journey_cell_id
            correlation_id: $input.correlation_id
          }
        } as $_logged_reject
      }
    }

    precondition ($locked == false) {
      error_type = "inputerror"
      error = $locked_msg
    }

    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.journey_cell_id == $input.journey_cell_id && $db.journey_cell_requirement.requirement_id == $input.requirement_id && $db.journey_cell_requirement.account_id == $actor.account_id
      return = {type: "single"}
    } as $row

    var $row_id {
      value = $row|get:"id":0
    }

    var $had {
      value = $row|get:"strength":""
    }

    conditional {
      if ($row_id != 0) {
        db.del journey_cell_requirement {
          field_name = "id"
          field_value = $row_id
        }

        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "step.need_removed"
            outcome       : "success"
            severity      : "info"
            error_code    : ""
            message       : "A need was removed from a step."
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "journey_cell"
            entity_id     : $input.journey_cell_id
            correlation_id: $input.correlation_id
            metadata      : {journey_map_id: $map_id, requirement_id: $input.requirement_id, strength: $had}
          }
        } as $_logged
      }
    }
  }

  response = {journey_cell_id: $input.journey_cell_id, requirement_id: $input.requirement_id, removed: ($row_id != 0)}
}
