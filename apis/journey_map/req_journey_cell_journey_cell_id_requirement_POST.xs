// REQ-1 story 04 — Put a need on ONE step of the map, hard (must) or soft (preferred), or change it. A DRAFT edit like any other change to a step: nothing reaches a job until the map is published as a new version (story 05). All the rules are in req/set_need (one place, shared with "apply to the whole row"): the row must do planned work E-REQ-031, a locked step refuses E-REQ-033, an archived requirement cannot be newly added E-REQ-030, at most 10 needs on a step E-REQ-032. The same need twice updates its strength and is not an error. The cell's MAP must belong to the caller's account (journey/assert_map_owner) and the requirement too (req/assert_requirement): another account's is "not found". Events: step.need_added, step.need_changed (map, stage key, row key, requirement, strength, actor); a refusal is logged as rejected with its code. Every input is passed to function.run explicitly.
query "journey_cell/{journey_cell_id}/requirement" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_cell_id filters=min:1
    int requirement_id filters=min:1
    text strength filters=trim
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
      input = {journey_map_id: $map_id, caller_account_id: $actor.account_id, user_id: $auth.id, step: "step_need_set"}
    } as $_owner

    function.run "req/assert_requirement" {
      input = {account_id: $actor.account_id, requirement_id: $input.requirement_id}
    } as $req_guard

    function.run "req/set_need" {
      input = {account_id: $actor.account_id, user_id: $actor.user_id, journey_cell_id: $input.journey_cell_id, requirement_id: $input.requirement_id, strength: $input.strength}
    } as $set

    conditional {
      if ($set.result == "refused") {
        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "step.need_set"
            outcome       : "rejected"
            severity      : "info"
            error_code    : $set.code
            message       : $set.message
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "journey_cell"
            entity_id     : $input.journey_cell_id
            correlation_id: $input.correlation_id
          }
        } as $_logged_reject
      }
    }

    precondition ($set.result != "refused") {
      error_type = "inputerror"
      error = $set.message
    }

    var $step {
      value = (($set.result == "added") ? "step.need_added" : "step.need_changed")
    }

    conditional {
      if ($set.result != "same") {
        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : $step
            outcome       : "success"
            severity      : "info"
            error_code    : ""
            message       : "A need was added to a step or its strength changed."
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "journey_cell"
            entity_id     : $input.journey_cell_id
            correlation_id: $input.correlation_id
            metadata      : {journey_map_id: $map_id, requirement_id: $input.requirement_id, requirement: $req_guard.requirement.name, strength: $input.strength}
          }
        } as $_logged
      }
    }
  }

  response = {journey_cell_id: $input.journey_cell_id, requirement_id: $input.requirement_id, strength: $input.strength, result: $set.result}
}
