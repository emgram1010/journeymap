// DEMAND-1 story 03 — what an admin (a person) sees about incoming orders: the routing rules (has_key says whether a key exists; the key and its hash are never returned), the orders from the last 7 days that need a person (no route, held, failed, refused), the jobs flagged "order changed" or "order cancelled", and counts for the last 24 hours by outcome. For same-day orders (decision D-11) each rule also carries live_agent_id (its same-day member, 0 = off), `agents` lists the members of the account's plans (id, name, plan, has_login) and `waiting` lists order jobs dated yesterday or later that are not on any day yet, so a person can put one onto its live day. Only the caller's account. Order numbers and ids only; no customer details are stored at all.
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

    // Each rule's same-day member. Every rule is seeded with 0 first, so a rule with no
    // row reads 0 (a variable-key lookup ignores its default).
    var $live_by_route {
      value = {}
    }

    var $rkey {
      value = ""
    }

    foreach ($route_rows) {
      each as $r0 {
        var.update $rkey {
          value = "k:" ~ ($r0.id|to_text)
        }

        var.update $live_by_route {
          value = $live_by_route|set:$rkey:0
        }
      }
    }

    db.query order_route_live_day {
      where = $db.order_route_live_day.account_id == $acct
      return = {type: "list"}
    } as $live_rows

    foreach ($live_rows) {
      each as $lr {
        var.update $rkey {
          value = "k:" ~ ($lr.route_id|to_text)
        }

        var.update $live_by_route {
          value = $live_by_route|set:$rkey:$lr.agent_id
        }
      }
    }

    var $routes {
      value = []
    }

    var $live_agent {
      value = 0
    }

    foreach ($route_rows) {
      each as $r {
        var.update $rkey {
          value = "k:" ~ ($r.id|to_text)
        }

        var.update $live_agent {
          value = ($live_by_route|get:$rkey:null) ?? 0
        }

        array.push $routes {
          value = {route_id: $r.id, source_system: $r.source_system, match_fulfilment: $r.match_fulfilment, workspace_id: $r.workspace_id, journey_map_id: $r.journey_map_id, is_enabled: $r.is_enabled, live_agent_id: $live_agent, has_key: ($r.key_hash != "")}
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

    db.query planner_agent {
      where = $db.planner_agent.workspace_id in $plan_ids
      sort = {planner_agent.name: "asc"}
      return = {type: "list"}
      output = ["id", "name", "workspace_id", "user_id"]
    } as $agent_rows

    var $agents {
      value = []
    }

    foreach ($agent_rows) {
      each as $ag {
        array.push $agents {
          value = {agent_id: $ag.id, name: $ag.name, workspace_id: $ag.workspace_id, has_login: ($ag.user_id != 0)}
        }
      }
    }

    // Order jobs dated yesterday (UTC) or later that are not on any day yet.
    var $y_ms {
      value = $now_ms - 86400000
    }

    var $yesterday {
      value = $y_ms|format_timestamp:"Y-m-d":"UTC"
    }

    db.query work_item_origin {
      where = $db.work_item_origin.account_id == $acct && $db.work_item_origin.work_item_id != 0 && $db.work_item_origin.starts_on >= $yesterday
      sort = {work_item_origin.starts_on: "asc"}
      return = {type: "list"}
    } as $recent

    var $recent_jobs {
      value = [-1]
    }

    var $on_day {
      value = {}
    }

    var $jkey {
      value = ""
    }

    foreach ($recent) {
      each as $ro {
        array.push $recent_jobs {
          value = $ro.work_item_id
        }

        var.update $jkey {
          value = "k:" ~ ($ro.work_item_id|to_text)
        }

        var.update $on_day {
          value = $on_day|set:$jkey:0
        }
      }
    }

    db.query work_task {
      where = $db.work_task.work_item_id in $recent_jobs
      return = {type: "list"}
      output = ["id", "work_item_id"]
    } as $recent_tasks

    var $recent_task_ids {
      value = [-1]
    }

    var $job_of_task {
      value = {}
    }

    var $tkey {
      value = ""
    }

    foreach ($recent_tasks) {
      each as $rt {
        array.push $recent_task_ids {
          value = $rt.id
        }

        var.update $tkey {
          value = "k:" ~ ($rt.id|to_text)
        }

        var.update $job_of_task {
          value = $job_of_task|set:$tkey:$rt.work_item_id
        }
      }
    }

    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id in $recent_task_ids
      return = {type: "list"}
      output = ["id", "work_task_id"]
    } as $recent_links

    var $link_job {
      value = 0
    }

    var $seen_n {
      value = 0
    }

    foreach ($recent_links) {
      each as $rl {
        var.update $tkey {
          value = "k:" ~ ($rl.work_task_id|to_text)
        }

        var.update $link_job {
          value = ($job_of_task|get:$tkey:null) ?? 0
        }

        var.update $jkey {
          value = "k:" ~ ($link_job|to_text)
        }

        var.update $seen_n {
          value = (($on_day|get:$jkey:null) ?? 0) + 1
        }

        var.update $on_day {
          value = $on_day|set:$jkey:$seen_n
        }
      }
    }

    var $staged_waiting {
      value = []
    }

    var $placed_n {
      value = 0
    }

    foreach ($recent) {
      each as $rw {
        var.update $jkey {
          value = "k:" ~ ($rw.work_item_id|to_text)
        }

        var.update $placed_n {
          value = ($on_day|get:$jkey:null) ?? 0
        }

        array.push $staged_waiting {
          value = {work_item_id: $rw.work_item_id, source_system: $rw.source_system, order_number: $rw.order_number, starts_on: $rw.starts_on, fulfilment: $rw.fulfilment, is_free: ($placed_n == 0)}
        }
      }
    }

    var $waiting {
      value = []
    }

    foreach ($staged_waiting) {
      each as $sw {
        conditional {
          if ($sw.is_free == true) {
            array.push $waiting {
              value = {work_item_id: $sw.work_item_id, source_system: $sw.source_system, order_number: $sw.order_number, starts_on: $sw.starts_on, fulfilment: $sw.fulfilment}
            }
          }
        }
      }
    }
  }

  response = {routes: $routes, needs_person: $needs_person, flagged: $flagged, last_24_hours: $counts, plans: $plans, plan_maps: $plan_maps, agents: $agents, waiting: $waiting}
}
