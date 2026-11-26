// REPEAT-2 story 03 — May this plan be deleted, and what would go with it? READ-ONLY: it decides and counts, it never writes. The caller has already proved the plan belongs to the caller's account (planner/assert_workspace); the DELETE endpoint also proves the caller is an admin person. A plan may be deleted only when it has NO history. History is any one of: a day that was ever published to live (plan_publication, plan_change_log, live_day_addition), work recorded on its jobs (activity_log) -> E-P3A-001; a job that came from a customer order, an exception link to or from one of its jobs, or an unmatched order line (work_item_origin, work_item_exception, work_item_unmatched_line) -> E-P3A-004; customer orders routed into the plan (order_route) -> E-P3A-005. A draft plan with jobs and slots nobody published CAN be deleted: that is the "wrong repeat, make it again" case, which planner/workspace_has_history (any job = history) could never allow. Returns the counts the confirm shows and whether the plan is a repeated copy (deleting it frees that date for a new repeat). Id lists are seeded with -1 so an `in` never meets an empty list; the seed is only ever read, never deleted. Every condition sits outside any loop and reads a value computed before it.
function "planner/delete_check" {
  input {
    int account_id
    int workspace_id filters=min:1
  }

  stack {
    db.query planner_workspace {
      where = $db.planner_workspace.id == $input.workspace_id && $db.planner_workspace.account_id == $input.account_id
      return = {type: "single"}
    } as $ws

    var $ws_name {
      value = ($ws|get:"name":"") ?? ""
    }

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $people_n

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id"]
    } as $timelines

    var $tl_ids {
      value = [-1]
    }

    foreach ($timelines) {
      each as $tl {
        array.push $tl_ids {
          value = $tl.id
        }
      }
    }

    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $slots_n

    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id
      return = {type: "list"}
      output = ["id"]
    } as $jobs

    var $job_ids {
      value = [-1]
    }

    foreach ($jobs) {
      each as $j {
        array.push $job_ids {
          value = $j.id
        }
      }
    }

    db.query work_task {
      where = $db.work_task.work_item_id in $job_ids
      return = {type: "count"}
    } as $steps_n

    // ── History: any of these and the plan is archived, not deleted ──
    db.query plan_publication {
      where = $db.plan_publication.timeline_id in $tl_ids
      return = {type: "count"}
    } as $published_n

    db.query plan_change_log {
      where = $db.plan_change_log.timeline_id in $tl_ids
      return = {type: "count"}
    } as $changes_n

    db.query live_day_addition {
      where = $db.live_day_addition.timeline_id in $tl_ids
      return = {type: "count"}
    } as $additions_n

    db.query activity_log {
      where = $db.activity_log.work_item_id in $job_ids
      return = {type: "count"}
    } as $log_n

    db.query work_item_origin {
      where = $db.work_item_origin.work_item_id in $job_ids
      return = {type: "count"}
    } as $origin_n

    db.query work_item_exception {
      where = $db.work_item_exception.parent_work_item_id in $job_ids || $db.work_item_exception.child_work_item_id in $job_ids
      return = {type: "count"}
    } as $exception_n

    db.query work_item_unmatched_line {
      where = $db.work_item_unmatched_line.work_item_id in $job_ids
      return = {type: "count"}
    } as $unmatched_n

    db.query order_route {
      where = $db.order_route.workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $route_n

    db.query plan_repeat {
      where = $db.plan_repeat.new_workspace_id == $input.workspace_id
      return = {type: "count"}
    } as $copy_rows

    var $recorded {
      value = $published_n + $changes_n + $additions_n + $log_n
    }

    var $orders {
      value = $origin_n + $exception_n + $unmatched_n
    }

    var $code {
      value = ""
    }

    var $message {
      value = ""
    }

    // Least serious first, so the most serious reason is the one that is left standing.
    conditional {
      if ($route_n > 0) {
        var.update $code {
          value = "E-P3A-005"
        }

        var.update $message {
          value = "Customer orders are routed into this plan. Point them at another plan first, or archive this one. (E-P3A-005)"
        }
      }
    }

    conditional {
      if ($orders > 0) {
        var.update $code {
          value = "E-P3A-004"
        }

        var.update $message {
          value = "This plan holds customer orders or exception work, so it can't be deleted. Archive it instead. (E-P3A-004)"
        }
      }
    }

    conditional {
      if ($recorded > 0) {
        var.update $code {
          value = "E-P3A-001"
        }

        var.update $message {
          value = "This plan has work recorded against it. Archive it instead. (E-P3A-001)"
        }
      }
    }

    var $counts {
      value = {people: $people_n, days: ($timelines|count), jobs: ($jobs|count), steps: $steps_n, slots: $slots_n}
    }

    var $found {
      value = {published: $published_n, changes: $changes_n, live_additions: $additions_n, activity: $log_n, order_jobs: $origin_n, exception_links: $exception_n, unmatched_lines: $unmatched_n, order_routes: $route_n}
    }
  }

  response = {
    allowed          : ($code == "")
    code             : $code
    message          : $message
    name             : $ws_name
    counts           : $counts
    found            : $found
    frees_repeat_date: ($copy_rows > 0)
  }
}
