// REQ-1 story 04 — "Apply to every step in this row": put one need on every step (stage) of ONE row of the map, in one request. A shortcut in the screen, NOT a second place to store it: it writes the same per-step rows as the single-step call, through the SAME rule (req/set_need), so a locked step, a full step or an archived requirement refuse exactly as they would one at a time. A row that is not planned work refuses outright (E-REQ-031). The answer COUNTS what happened, re-read from the database after the writes (never the loop's own tally): added, changed, already there, and skipped with a reason per step, so the person is told how many were changed. The row's steps are queried first and written by cell id inside a transaction, so it never changes only the first step. The map must belong to the caller's account. Events: one step.need_row_applied with the counts. Every input is passed to function.run explicitly.
query "journey_map/{journey_map_id}/row-requirement" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id filters=min:1
    int journey_lens_id filters=min:1
    int requirement_id filters=min:1
    text strength filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "journey/assert_map_owner" {
      input = {journey_map_id: $input.journey_map_id, caller_account_id: $actor.account_id, user_id: $auth.id, step: "row_need_set"}
    } as $_owner

    function.run "req/assert_requirement" {
      input = {account_id: $actor.account_id, requirement_id: $input.requirement_id}
    } as $req_guard

    db.query journey_lens {
      where = $db.journey_lens.id == $input.journey_lens_id && $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "single"}
    } as $lens

    var $lens_found {
      value = $lens|get:"id":0
    }

    precondition ($lens_found != 0) {
      error_type = "notfound"
      error = "That row was not found on this map."
    }

    var $lens_actor_type {
      value = $lens|get:"actor_type":""
    }

    // THE one rule for "does this row do planned work": an explicit override wins, otherwise the default by actor type.
    function.run "does_planned_work" {
      input = {journey_lens_id: $input.journey_lens_id, actor_type: $lens_actor_type}
    } as $planned_rule

    var $planned {
      value = ($planned_rule.does_planned_work == true)|to_int
    }

    var $not_planned_msg {
      value = "This row is not marked as planned work, so its steps cannot have needs. Mark the row as planned work first. (E-REQ-031)"
    }

    precondition ($planned > 0) {
      error_type = "inputerror"
      error = $not_planned_msg
    }

    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.lens == $input.journey_lens_id
      return = {type: "list"}
      output = ["id"]
    } as $cells

    var $added {
      value = 0
    }

    var $changed {
      value = 0
    }

    var $same {
      value = 0
    }

    var $skipped {
      value = []
    }

    db.transaction {
      stack {
        foreach ($cells) {
          each as $c {
            function.run "req/set_need" {
              input = {account_id: $actor.account_id, user_id: $actor.user_id, journey_cell_id: $c.id, requirement_id: $input.requirement_id, strength: $input.strength}
            } as $r

            var.update $added {
              value = $added + (($r.result == "added")|to_int)
            }

            var.update $changed {
              value = $changed + (($r.result == "changed")|to_int)
            }

            var.update $same {
              value = $same + (($r.result == "same")|to_int)
            }

            array.push $skipped {
              value = {journey_cell_id: $c.id, result: $r.result, code: $r.code}
            }
          }
        }
      }
    }

    var $refused_list {
      value = []
    }

    foreach ($skipped) {
      each as $s {
        conditional {
          if ($s.result == "refused") {
            array.push $refused_list {
              value = {journey_cell_id: $s.journey_cell_id, code: $s.code}
            }
          }
        }
      }
    }

    // Re-count from the database: how many steps of this row now carry the need at this strength.
    var $cell_ids {
      value = [-1]
    }

    foreach ($cells) {
      each as $c {
        array.push $cell_ids {
          value = $c.id
        }
      }
    }

    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.journey_cell_id in $cell_ids && $db.journey_cell_requirement.requirement_id == $input.requirement_id && $db.journey_cell_requirement.strength == $input.strength
      return = {type: "count"}
    } as $now_with_it

    function.run "ops/log_event" {
      input = {
        feature       : "REQ-1"
        step          : "step.need_row_applied"
        outcome       : "success"
        severity      : "info"
        error_code    : ""
        message       : "A need was applied to every step of a row."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "journey_lens"
        entity_id     : $input.journey_lens_id
        correlation_id: $input.correlation_id
        metadata      : {journey_map_id: $input.journey_map_id, requirement_id: $input.requirement_id, strength: $input.strength, added: $added, changed: $changed, already: $same, refused: ($refused_list|count)}
      }
    } as $_logged
  }

  response = {
    journey_lens_id   : $input.journey_lens_id
    steps_in_row      : ($cells|count)
    added             : $added
    changed           : $changed
    already_there     : $same
    refused           : $refused_list
    steps_with_it_now : $now_with_it
  }
}
