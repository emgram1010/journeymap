// PLN-9 (US-PLN-9-06, epic finding 5) — Add a map to an ALREADY-RUNNING
// plan. `template/{id}` PATCH only changes what the NEXT instance will
// accept (PLAN-1's whole point); a planner using the real UI to add a
// second work type to a plan that's already underway had no endpoint
// at all until this one — found live during E2E-1.
//
// APPEND-ONLY AND IDEMPOTENT, same rule as the template's own
// `add_map_ids`: a map already accepted is skipped, never rejected, so
// this is safe to call twice with the same list. Removing a map means
// deleting a `planner_workspace_map` row, and every delete here is
// still awaiting the founder's approval (CLAUDE.md) — a
// `remove_map_ids` input belongs here once deletes are allowed.
//
// Reuses `planner/assert_maps_publishable` unchanged: a map must
// belong to this account AND have a published version, the identical
// rule a template enforces when accepting one.
//
// 2026-10-18 — the "not this account's map" branch was sharing
// E-PLAN-004 with "not published yet", two different failures under
// one code. Renumbered to E-PLAN-015; found by the error-code registry
// guard, which now fails the build on a reused code.
query "workspace/{workspace_id}/map" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    json map_ids
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-9"
        step       : "add_workspace_map"
        entity_type: "planner_workspace"
        entity_id  : $input.workspace_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    function.run "planner/assert_maps_publishable" {
      input = {account_id: $actor.account_id, map_ids: $input.map_ids}
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
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Add map to plan refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // Already-attached maps are skipped rather than rejected (same
    // `|set:`/`|get:` map-membership pattern as the template PATCH —
    // `|contains:` is always false on an array, CLAUDE.md).
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
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        correlation_id: $input.correlation_id
        message       : "Map(s) added to plan."
        metadata      : {added_count: $added_count, map_ids: $map_ids_out}
      }
    }
  }

  response = {
    map_ids     : $map_ids_out
    added_count : $added_count
  }
}
