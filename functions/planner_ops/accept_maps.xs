// COP-5 story 01 - "the plan accepts these maps": the rule of endpoint 570 (POST /workspace/{workspace_id}/map, PLN-9), moved here unchanged so the endpoint and the copilot tool plan_accept_map share one copy. The caller resolves the actor (planner/resolve_actor) and passes it in; a function has no $auth. Append-only and idempotent: a map the plan already accepts is skipped, never rejected, so calling twice with the same list is safe. A map must belong to this account AND have a published version (planner/assert_maps_publishable, unchanged): not published is E-PLAN-004, not this account's is E-PLAN-015. An archived plan is refused (E-GOV-004). One verdict, one log, one raise.
function "planner_ops/accept_maps" {
  input {
    json actor
    int workspace_id filters=min:1
    json map_ids
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/assert_workspace" {
      input = {account_id: $input.actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived   : $guard.workspace.is_archived
        feature       : "PLN-9"
        step          : "add_workspace_map"
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        user_id       : $input.actor.user_id
        account_id    : $input.actor.account_id
        correlation_id: $input.correlation_id
      }
    }

    function.run "planner/assert_maps_publishable" {
      input = {account_id: $input.actor.account_id, map_ids: $input.map_ids}
    } as $maps_check

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if (($input.map_ids|count) == 0) {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Choose at least one map to add. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $maps_check.ok == false && $maps_check.reason == "not_published") {
        var.update $reject_code {
          value = "E-PLAN-004"
        }

        var.update $reject_msg {
          value = "Publish '" ~ $maps_check.map_title ~ "' first. Only published maps can be used in a plan. (E-PLAN-004)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $maps_check.ok == false) {
        var.update $reject_code {
          value = "E-PLAN-015"
        }

        var.update $reject_msg {
          value = "One of those maps isn't available to this account. (E-PLAN-015)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-9"
            step          : "add_workspace_map"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $input.actor.user_id
            account_id    : $input.actor.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Add map to plan refused."
            duration_ms   : 0
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // Already-attached maps are skipped rather than rejected (same
    // set / get map-membership pattern as the template PATCH - the
    // contains filter is always false on an array, CLAUDE.md).
    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $current_links

    var $have {
      value = {}
    }

    var $key {
      value = ""
    }

    foreach ($current_links) {
      each as $l {
        var.update $key {
          value = $l.journey_map_id|to_text
        }

        var.update $have {
          value = $have|set:$key:1
        }
      }
    }

    var $to_add {
      value = []
    }

    foreach ($input.map_ids) {
      each as $mid {
        var.update $key {
          value = $mid|to_text
        }

        array.push $to_add {
          value = {map_id: $mid, already: ($have|get:$key:null)}
        }
      }
    }

    var $added_count {
      value = 0
    }

    db.transaction {
      stack {
        foreach ($to_add) {
          each as $a {
            conditional {
              if ($a.already == null) {
                db.add planner_workspace_map {
                  data = {workspace_id: $input.workspace_id, journey_map_id: $a.map_id}
                } as $link

                var.update $added_count {
                  value = $added_count + 1
                }
              }
            }
          }
        }
      }
    }

    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $final_links

    var $map_ids_out {
      value = []
    }

    foreach ($final_links) {
      each as $l {
        array.push $map_ids_out {
          value = $l.journey_map_id
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-9"
        step          : "add_workspace_map"
        outcome       : "success"
        severity      : "info"
        user_id       : $input.actor.user_id
        account_id    : $input.actor.account_id
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        correlation_id: $input.correlation_id
        error_code    : ""
        message       : "Map(s) added to plan."
        duration_ms   : 0
        metadata      : {added_count: $added_count, map_ids: $map_ids_out}
      }
    }
  }

  response = {
    map_ids     : $map_ids_out
    added_count : $added_count
  }
}
