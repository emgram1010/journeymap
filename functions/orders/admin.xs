// DEMAND-1 story 03 — what an admin (a person, never an AI: aim/assert_admin_person) may change about incoming orders. action route_save: add or change a routing rule (decision D-5): orders from source_system with this fulfilment type (empty = any) become jobs in one plan from one map; the plan and the map must be in the account and the plan must already accept the map (E-HOOK-005). key_create: make a new order key for a source (it replaces the old one on every rule of that source) and return it ONCE; only its hash is stored. route_delete: remove one rule. flag_clear: mark an "order changed" or "order cancelled" job as handled, logged with who and when. retry: run a held, unrouted or failed order again from what was kept of it. live_member_save (decision D-11): pick the plan member whose LIVE day same-day orders of one rule are added to, or 0 to switch that off; the member must be in the rule's plan and have a login (E-HOOK-010). place_live: try again to put one order's job onto its live day; the answer says in a sentence whether it went on.
function "orders/admin" {
  input {
    int actor_user_id
    text action filters=trim
    int route_id?
    text source_system? filters=trim
    text match_fulfilment? filters=trim
    int workspace_id?
    int journey_map_id?
    bool is_enabled?
    int work_item_id?
    int order_inbox_id?
    int agent_id?
  }

  stack {
    function.run "aim/assert_admin_person" {
      input = {actor_user_id: $input.actor_user_id, step: "orders_admin"}
    } as $admin

    var $acct {
      value = $admin.account_id
    }

    var $action {
      value = $input.action
    }

    precondition ($action == "route_save" || $action == "key_create" || $action == "route_delete" || $action == "flag_clear" || $action == "retry" || $action == "live_member_save" || $action == "place_live") {
      error_type = "inputerror"
      error = "action is route_save, key_create, route_delete, flag_clear, retry, live_member_save or place_live."
    }

    var $source {
      value = ($input.source_system ?? "")|trim|lower
    }

    var $match {
      value = ($input.match_fulfilment ?? "")|trim|lower
    }

    var $result {
      value = {}
    }

    conditional {
      if ($action == "route_save") {
        var $source_ok {
          value = "/^[a-z0-9][a-z0-9-]{1,39}$/"|regex_matches:$source
        }

        var $match_ok {
          value = ($match == "") || ("/^[a-z0-9][a-z0-9 _-]{0,39}$/"|regex_matches:$match)
        }

        precondition ($source_ok && $match_ok) {
          error_type = "inputerror"
          error = "Name the order system in 2 to 40 lower-case letters, digits or hyphens. A fulfilment type is up to 40 letters, digits, spaces or hyphens. (E-HOOK-006)"
        }

        db.query planner_workspace {
          where = $db.planner_workspace.id == $input.workspace_id && $db.planner_workspace.account_id == $acct
          return = {type: "count"}
        } as $plan_found

        db.query journey_map {
          where = $db.journey_map.id == $input.journey_map_id && $db.journey_map.account_id == $acct
          return = {type: "count"}
        } as $map_found

        db.query planner_workspace_map {
          where = $db.planner_workspace_map.workspace_id == $input.workspace_id && $db.planner_workspace_map.journey_map_id == $input.journey_map_id
          return = {type: "count"}
        } as $accepted

        precondition ($plan_found == 1 && $map_found == 1 && $accepted > 0) {
          error_type = "inputerror"
          error = "Pick a plan and a map from your account, where the plan already uses that map. (E-HOOK-005)"
        }

        db.query order_route {
          where = $db.order_route.account_id == $acct && $db.order_route.source_system == $source
          return = {type: "list"}
        } as $siblings

        var $shared_hash {
          value = ""
        }

        var $same_id {
          value = 0
        }

        var $hit {
          value = 0
        }

        foreach ($siblings) {
          each as $s {
            conditional {
              if ($s.key_hash != "") {
                var.update $shared_hash {
                  value = $s.key_hash
                }
              }
            }

            var.update $hit {
              value = ($s.match_fulfilment == $match)|to_int
            }

            var.update $same_id {
              value = $same_id + (($s.id - $same_id) * $hit)
            }
          }
        }

        var $target_id {
          value = $input.route_id ?? 0
        }

        conditional {
          if ($target_id == 0) {
            var.update $target_id {
              value = $same_id
            }
          }
        }

        var $enabled {
          value = $input.is_enabled == true
        }

        conditional {
          if ($target_id == 0) {
            db.add order_route {
              data = {created_at: "now", updated_at: "now", account_id: $acct, source_system: $source, key_hash: $shared_hash, match_fulfilment: $match, workspace_id: $input.workspace_id, journey_map_id: $input.journey_map_id, is_enabled: $enabled, created_by_user_id: $input.actor_user_id}
            } as $made

            var.update $target_id {
              value = $made.id
            }
          }

          else {
            db.query order_route {
              where = $db.order_route.id == $target_id && $db.order_route.account_id == $acct
              return = {type: "count"}
            } as $mine

            precondition ($mine == 1) {
              error_type = "notfound"
              error = "Routing rule not found. (E-HOOK-007)"
            }

            db.patch order_route {
              field_name = "id"
              field_value = $target_id
              data = {updated_at: "now", match_fulfilment: $match, workspace_id: $input.workspace_id, journey_map_id: $input.journey_map_id, is_enabled: $enabled, created_by_user_id: $input.actor_user_id}
            } as $saved
          }
        }

        var.update $result {
          value = {status: "saved", route_id: $target_id, has_key: ($shared_hash != "")}
        }
      }

      elseif ($action == "key_create") {
        db.query order_route {
          where = $db.order_route.account_id == $acct && $db.order_route.source_system == $source
          return = {type: "list"}
        } as $rows

        precondition (($rows|count) > 0) {
          error_type = "inputerror"
          error = "Add a routing rule for this order system first. (E-HOOK-009)"
        }

        security.create_uuid as $u1

        security.create_uuid as $u2

        var $part1 {
          value = $u1|replace:"-":""
        }

        var $part2 {
          value = $u2|replace:"-":""
        }

        var $key {
          value = "emg_ord_" ~ $part1 ~ $part2
        }

        var $hash {
          value = $key|sha256
        }

        foreach ($rows) {
          each as $row {
            db.patch order_route {
              field_name = "id"
              field_value = $row.id
              data = {key_hash: $hash, updated_at: "now"}
            } as $keyed
          }
        }

        var.update $result {
          value = {status: "key_created", source_system: $source, order_key: $key}
        }
      }

      elseif ($action == "route_delete") {
        db.query order_route {
          where = $db.order_route.id == $input.route_id && $db.order_route.account_id == $acct
          return = {type: "count"}
        } as $mine_del

        precondition ($mine_del == 1) {
          error_type = "notfound"
          error = "Routing rule not found. (E-HOOK-007)"
        }

        db.query order_route_live_day {
          where = $db.order_route_live_day.route_id == $input.route_id
          return = {type: "list"}
        } as $live_rows_del

        db.transaction {
          stack {
            foreach ($live_rows_del) {
              each as $lrd {
                db.del order_route_live_day {
                  field_name = "id"
                  field_value = $lrd.id
                }
              }
            }

            db.del order_route {
              field_name = "id"
              field_value = $input.route_id
            }
          }
        }

        var.update $result {
          value = {status: "deleted", route_id: $input.route_id}
        }
      }

      elseif ($action == "flag_clear") {
        db.query work_item_origin {
          where = $db.work_item_origin.work_item_id == $input.work_item_id && $db.work_item_origin.account_id == $acct && $input.work_item_id != 0
          return = {type: "single"}
        } as $origin

        var $oid {
          value = $origin|get:"id":0
        }

        precondition ($oid != 0) {
          error_type = "notfound"
          error = "Job not found"
        }

        db.patch work_item_origin {
          field_name = "id"
          field_value = $oid
          data = {order_flag: "none", flag_cleared_at: "now", flag_cleared_by_user_id: $input.actor_user_id, updated_at: "now"}
        } as $cleared

        var.update $result {
          value = {status: "cleared", work_item_id: $input.work_item_id}
        }
      }

      elseif ($action == "live_member_save") {
        db.query order_route {
          where = $db.order_route.id == $input.route_id && $db.order_route.account_id == $acct
          return = {type: "single"}
        } as $live_route

        var $live_route_id {
          value = $live_route|get:"id":0
        }

        precondition ($live_route_id != 0) {
          error_type = "notfound"
          error = "Routing rule not found. (E-HOOK-007)"
        }

        var $live_plan {
          value = $live_route|get:"workspace_id":0
        }

        var $want_agent {
          value = $input.agent_id ?? 0
        }

        db.query planner_agent {
          where = $db.planner_agent.id == $want_agent && $db.planner_agent.workspace_id == $live_plan && $db.planner_agent.user_id != 0
          return = {type: "count"}
        } as $agent_ok

        precondition ($want_agent == 0 || $agent_ok == 1) {
          error_type = "inputerror"
          error = "Pick a member of that plan who has a login. (E-HOOK-010)"
        }

        db.query order_route_live_day {
          where = $db.order_route_live_day.route_id == $live_route_id
          return = {type: "single"}
        } as $live_old

        var $live_old_id {
          value = $live_old|get:"id":0
        }

        conditional {
          if ($live_old_id == 0) {
            db.add order_route_live_day {
              data = {created_at: "now", updated_at: "now", account_id: $acct, route_id: $live_route_id, agent_id: $want_agent, updated_by_user_id: $input.actor_user_id}
            } as $live_made
          }

          else {
            db.patch order_route_live_day {
              field_name = "id"
              field_value = $live_old_id
              data = {agent_id: $want_agent, updated_at: "now", updated_by_user_id: $input.actor_user_id}
            } as $live_saved
          }
        }

        var.update $result {
          value = {status: "saved", route_id: $live_route_id, live_agent_id: $want_agent}
        }
      }

      elseif ($action == "place_live") {
        function.run "orders/place_live" {
          input = {account_id: $acct, work_item_id: ($input.work_item_id ?? 0), route_id: 0, actor_user_id: $input.actor_user_id}
        } as $place

        var.update $result {
          value = {status: "done", placed: $place.placed, reason: $place.reason, detail: $place.detail}
        }
      }

      else {
        db.query order_inbox {
          where = $db.order_inbox.id == $input.order_inbox_id && $db.order_inbox.account_id == $acct
          return = {type: "single"}
        } as $row_in

        var $in_id {
          value = $row_in|get:"id":0
        }

        var $in_outcome {
          value = $row_in|get:"outcome":""
        }

        precondition ($in_id != 0 && ($in_outcome == "held" || $in_outcome == "no_route" || $in_outcome == "failed")) {
          error_type = "inputerror"
          error = "Only a held, unrouted or failed order can be tried again. (E-HOOK-008)"
        }

        var $in_source {
          value = $row_in|get:"source_system":""
        }

        var $in_payload {
          value = $row_in|get:"payload":null
        }

        function.run "orders/process" {
          input = {account_id: $acct, source_system: $in_source, order: $in_payload}
        } as $again

        var.update $result {
          value = $again
        }
      }
    }

    var $step {
      value = "orders_admin_" ~ $action
    }

    function.run "ops/log_event" {
      input = {feature: "DEMAND-1", step: $step, outcome: "success", severity: "info", error_code: "", message: "An admin changed the incoming-orders setup or handled an order.", user_id: $input.actor_user_id, account_id: $acct, entity_type: "order_route", entity_id: ($input.route_id ?? 0), correlation_id: "", duration_ms: 0, metadata: {action: $action, source_system: $source, work_item_id: ($input.work_item_id ?? 0), order_inbox_id: ($input.order_inbox_id ?? 0), agent_id: ($input.agent_id ?? 0)}}
    } as $_ev
  }

  response = $result
}
