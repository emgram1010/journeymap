// DEMAND-1 story 01 (decision D-11) — try to put an order's job onto the live day it is for. Never throws: it answers placed true or false with one plain sentence, so an order is never lost because its day could not take it (the job then simply stays in the backlog). Steps: find the order's row (work_item_origin) and its routing rule (the given route_id, or the rule that matches the order's system, plan and fulfilment type); read that rule's same-day member (order_route_live_day; none = off); find that member's day for the order's start date; when the day is live, hand the job to planner_ops/add_job_to_live_day, which holds every rule. The work is done in the name of actor_user_id, or the person who made the routing rule when that is 0.
function "orders/place_live" {
  input {
    int account_id
    int work_item_id
    int route_id?
    int actor_user_id?
  }

  stack {
    var $acct {
      value = $input.account_id
    }

    var $placed {
      value = false
    }

    var $reason {
      value = ""
    }

    var $detail {
      value = ""
    }

    var $timeline_id {
      value = 0
    }

    var $result {
      value = {status: ""}
    }

    db.query work_item_origin {
      where = $db.work_item_origin.account_id == $acct && $db.work_item_origin.work_item_id == $input.work_item_id && $input.work_item_id != 0
      return = {type: "single"}
    } as $origin

    var $origin_id {
      value = $origin|get:"id":0
    }

    var $source {
      value = ($origin|get:"source_system":"") ?? ""
    }

    var $fulfilment {
      value = ($origin|get:"fulfilment":"") ?? ""
    }

    var $starts_on {
      value = ($origin|get:"starts_on":"") ?? ""
    }

    db.query work_item {
      where = $db.work_item.id == $input.work_item_id && $db.work_item.account_id == $acct
      return = {type: "single"}
      output = ["id", "workspace_id"]
    } as $job

    var $plan_id {
      value = $job|get:"workspace_id":0
    }

    // The routing rule: the one given, else exact fulfilment match, else the catch-all.
    db.query order_route {
      where = $db.order_route.account_id == $acct && $db.order_route.source_system == $source && $db.order_route.workspace_id == $plan_id && $plan_id != 0
      return = {type: "list"}
    } as $routes

    var $given_id {
      value = 0
    }

    var $exact_id {
      value = 0
    }

    var $any_id {
      value = 0
    }

    var $hit {
      value = 0
    }

    var $want_route {
      value = $input.route_id ?? 0
    }

    foreach ($routes) {
      each as $r {
        var.update $hit {
          value = ($r.id == $want_route && $want_route != 0)|to_int
        }

        var.update $given_id {
          value = $given_id + (($r.id - $given_id) * $hit)
        }

        var.update $hit {
          value = ($r.match_fulfilment == $fulfilment && $fulfilment != "")|to_int
        }

        var.update $exact_id {
          value = $exact_id + (($r.id - $exact_id) * $hit)
        }

        var.update $hit {
          value = ($r.match_fulfilment == "")|to_int
        }

        var.update $any_id {
          value = $any_id + (($r.id - $any_id) * $hit)
        }
      }
    }

    var $route_id {
      value = $given_id
    }

    conditional {
      if ($route_id == 0) {
        var.update $route_id {
          value = $exact_id
        }
      }
    }

    conditional {
      if ($route_id == 0) {
        var.update $route_id {
          value = $any_id
        }
      }
    }

    db.query order_route {
      where = $db.order_route.id == $route_id && $route_id != 0
      return = {type: "single"}
    } as $route

    var $route_user {
      value = $route|get:"created_by_user_id":0
    }

    db.query order_route_live_day {
      where = $db.order_route_live_day.route_id == $route_id && $route_id != 0
      return = {type: "single"}
    } as $live_row

    var $agent_id {
      value = $live_row|get:"agent_id":0
    }

    db.query planner_agent {
      where = $db.planner_agent.id == $agent_id && $agent_id != 0
      return = {type: "single"}
      output = ["id", "name", "workspace_id"]
    } as $agent

    var $agent_name {
      value = ($agent|get:"name":"") ?? ""
    }

    // An empty date must never reach the date column: a sentinel that matches no day.
    var $date_q {
      value = (($starts_on != "") ? $starts_on : "0001-01-01")
    }

    db.query planner_timeline {
      where = $db.planner_timeline.agent_id == $agent_id && $db.planner_timeline.planned_date == $date_q && $db.planner_timeline.workspace_id == $plan_id && $agent_id != 0
      return = {type: "single"}
    } as $day

    var $day_id {
      value = $day|get:"id":0
    }

    var $day_status {
      value = ($day|get:"status":"") ?? ""
    }

    var $who {
      value = $input.actor_user_id ?? 0
    }

    conditional {
      if ($who == 0) {
        var.update $who {
          value = $route_user
        }
      }
    }

    conditional {
      if ($origin_id == 0 || $plan_id == 0) {
        var.update $reason {
          value = "not_an_order"
        }

        var.update $detail {
          value = "That job did not come from an order, so it was left where it is."
        }
      }

      elseif ($agent_id == 0) {
        var.update $reason {
          value = "off"
        }

        var.update $detail {
          value = "Same-day orders are switched off for this routing rule, so the job is in the backlog."
        }
      }

      elseif ($starts_on == "") {
        var.update $reason {
          value = "no_date"
        }

        var.update $detail {
          value = "The order has no start date, so the job is in the backlog."
        }
      }

      elseif ($day_id == 0 || $day_status != "published") {
        var.update $reason {
          value = "no_live_day"
        }

        var.update $detail {
          value = $agent_name ~ " has no live day on " ~ $starts_on ~ ", so the job is in the backlog."
        }
      }

      elseif ($who == 0) {
        var.update $reason {
          value = "no_actor"
        }

        var.update $detail {
          value = "Nobody is named on this routing rule, so the job is in the backlog."
        }
      }
    }

    var $err {
      value = {message: ""}
    }

    conditional {
      if ($reason == "") {
        var.update $timeline_id {
          value = $day_id
        }

        try_catch {
          try {
            function.run "planner/resolve_actor" {
              input = {user_id: $who}
            } as $actor

            function.run "planner_ops/add_job_to_live_day" {
              input = {actor: $actor, work_item_id: $input.work_item_id, timeline_id: $day_id, origin: "order", correlation_id: ""}
            } as $added

            var.update $result {
              value = $added
            }

            var.update $placed {
              value = true
            }
          }

          catch {
            var.update $err {
              value = $error
            }
          }
        }
      }
    }

    var $err_msg {
      value = ($err|get:"message":"") ?? ""
    }

    conditional {
      if ($reason == "" && $placed == true) {
        var.update $reason {
          value = "placed"
        }

        var.update $detail {
          value = "Added to the end of " ~ $agent_name ~ "'s live day on " ~ $starts_on ~ "."
        }
      }

      elseif ($reason == "") {
        var.update $reason {
          value = "refused"
        }

        var.update $detail {
          value = "The job is in the backlog. " ~ $err_msg
        }
      }
    }
  }

  response = {placed: $placed, reason: $reason, detail: $detail, timeline_id: $timeline_id, agent_id: $agent_id, result: $result}
}
