// DEMAND-1 story 03 — what an admin (a person) sees about incoming orders: the routing rules (has_key says whether a key exists; the key and its hash are never returned), the orders from the last 7 days that need a person (no route, held, failed, refused), the jobs flagged "order changed" or "order cancelled", and counts for the last 24 hours by outcome. Only the caller's account. Order numbers and ids only; no customer details are stored at all.
function "orders/overview" {
  input {
    int actor_user_id
  }

  stack {
    function.run "aim/assert_admin_person" {
      input = {actor_user_id: $input.actor_user_id, step: "orders_overview"}
    } as $admin

    var $acct {
      value = $admin.account_id
    }

    db.query order_route {
      where = $db.order_route.account_id == $acct
      sort = {order_route.source_system: "asc"}
      return = {type: "list"}
    } as $route_rows

    var $routes {
      value = []
    }

    foreach ($route_rows) {
      each as $r {
        array.push $routes {
          value = {route_id: $r.id, source_system: $r.source_system, match_fulfilment: $r.match_fulfilment, workspace_id: $r.workspace_id, journey_map_id: $r.journey_map_id, is_enabled: $r.is_enabled, has_key: ($r.key_hash != "")}
        }
      }
    }

    var $now_ms {
      value = now|to_int
    }

    var $week_ago {
      value = $now_ms - 604800000
    }

    var $day_ago {
      value = $now_ms - 86400000
    }

    db.query order_inbox {
      where = $db.order_inbox.account_id == $acct && $db.order_inbox.created_at >= $week_ago
      sort = {order_inbox.id: "desc"}
      return = {type: "list"}
    } as $inbox

    var $needs_person {
      value = []
    }

    var $counts {
      value = {created: 0, updated: 0, duplicate: 0, flagged: 0, no_route: 0, held: 0, refused: 0, failed: 0}
    }

    var $n {
      value = 0
    }

    var $ck {
      value = ""
    }

    foreach ($inbox) {
      each as $i {
        conditional {
          if ($i.outcome == "no_route" || $i.outcome == "held" || $i.outcome == "failed" || $i.outcome == "refused") {
            array.push $needs_person {
              value = {order_inbox_id: $i.id, source_system: $i.source_system, order_number: $i.order_number, external_id: $i.external_id, outcome: $i.outcome, detail: $i.detail, received_at: $i.created_at}
            }
          }
        }

        conditional {
          if ($i.created_at >= $day_ago) {
            var.update $ck {
              value = $i.outcome
            }

            var.update $n {
              value = (($counts|get:$ck:null) ?? 0) + 1
            }

            var.update $counts {
              value = $counts|set:$ck:$n
            }
          }
        }
      }
    }

    db.query work_item_origin {
      where = $db.work_item_origin.account_id == $acct && $db.work_item_origin.order_flag != "none" && $db.work_item_origin.order_flag != "" && $db.work_item_origin.work_item_id != 0
      return = {type: "list"}
    } as $flag_rows

    var $flagged {
      value = []
    }

    foreach ($flag_rows) {
      each as $f {
        array.push $flagged {
          value = {work_item_id: $f.work_item_id, source_system: $f.source_system, order_number: $f.order_number, order_flag: $f.order_flag, starts_on: $f.starts_on}
        }
      }
    }

    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $acct && $db.planner_workspace.is_archived == false
      sort = {planner_workspace.name: "asc"}
      return = {type: "list"}
      output = ["id", "name"]
    } as $plans

    var $plan_ids {
      value = [-1]
    }

    foreach ($plans) {
      each as $pl {
        array.push $plan_ids {
          value = $pl.id
        }
      }
    }

    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id in $plan_ids
      return = {type: "list"}
      output = ["id", "workspace_id", "journey_map_id"]
    } as $plan_maps
  }

  response = {routes: $routes, needs_person: $needs_person, flagged: $flagged, last_24_hours: $counts, plans: $plans, plan_maps: $plan_maps}
}
