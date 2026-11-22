// DEMAND-1 story 01 (decision D-11, founder 2026-11-21) — THE ONE DOOR for adding a job to a day that is already live, started or not. It checks who is asking and whether the day may take the job, then runs planner_ops/live_add_attempt (one transaction, add-only) up to three times: a lost race with another add rolls back completely and is simply tried again. Refused, with nothing written: the day is not live (E-DEMAND-001), the day is in the past (E-DEMAND-008), the job is cancelled (E-SCHED-008), the day already took 50 added jobs (E-DEMAND-005), and everything live_add_attempt refuses (no steps, part of the job on another day, no login or needs info, existing work would change). What it never does: publish a draft day, create a day, move or change a block that is already on the day, or touch the publish endpoint and its seal (E-LIVE-007). Each added block is written to plan_change_log as "added", so plan-against-actual shows it was not in the plan. `actor` is planner/resolve_actor's result; callers are orders/place_live (an order) and nothing an AI can reach. Every outcome is an event (feature DEMAND-1, step live_day_add).
function "planner_ops/add_job_to_live_day" {
  input {
    json actor
    int work_item_id filters=min:1
    int timeline_id filters=min:1
    text origin? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    var $actor {
      value = $input.actor
    }

    var $origin {
      value = $input.origin ?? ""
    }

    var $corr {
      value = $input.correlation_id ?? ""
    }

    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Job not found"
    }

    function.run "planner/assert_timeline" {
      input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
    } as $tl_guard

    function.run "planner/assert_same_workspace" {
      input = {workspace_id_a: $job.workspace_id, workspace_id_b: $tl_guard.timeline.workspace_id}
    }

    var $now_ms {
      value = now|to_int
    }

    var $y_ms {
      value = $now_ms - 86400000
    }

    // Yesterday in UTC is the earliest day accepted, so "today" holds in every time zone.
    var $yesterday {
      value = $y_ms|format_timestamp:"Y-m-d":"UTC"
    }

    db.query planner_timeline {
      where = $db.planner_timeline.id == $input.timeline_id && $db.planner_timeline.planned_date >= $yesterday
      return = {type: "count"}
    } as $not_past

    db.query live_day_addition {
      where = $db.live_day_addition.timeline_id == $input.timeline_id
      return = {type: "count"}
    } as $adds_so_far

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($tl_guard.timeline.status != "published") {
        var.update $reject_code {
          value = "E-DEMAND-001"
        }

        var.update $reject_msg {
          value = "That day is not live yet. Publish it first. (E-DEMAND-001)"
        }
      }

      elseif ($not_past == 0) {
        var.update $reject_code {
          value = "E-DEMAND-008"
        }

        var.update $reject_msg {
          value = "That day is in the past, so nothing was added to it. (E-DEMAND-008)"
        }
      }

      elseif ($job.status == "cancelled") {
        var.update $reject_code {
          value = "E-SCHED-008"
        }

        var.update $reject_msg {
          value = "That job is cancelled, so its steps can't be scheduled. (E-SCHED-008)"
        }
      }

      elseif ($adds_so_far >= 50) {
        var.update $reject_code {
          value = "E-DEMAND-005"
        }

        var.update $reject_msg {
          value = "This day already took 50 jobs after it went live, so this one stays in the backlog. (E-DEMAND-005)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {feature: "DEMAND-1", step: "live_day_add", outcome: "rejected", severity: "info", error_code: $reject_code, message: "Adding a job to a live day was refused.", user_id: $actor.user_id, account_id: $actor.account_id, entity_type: "planner_timeline", entity_id: $input.timeline_id, correlation_id: $corr, duration_ms: 0, metadata: {work_item_id: $input.work_item_id, origin: $origin}}
        } as $_rej
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // Up to three attempts. Only a lost race (the database refusing a duplicate
    // version) is tried again; a refusal with a reason is final.
    var $done {
      value = false
    }

    var $res {
      value = {status: ""}
    }

    var $err {
      value = {message: ""}
    }

    var $attempts {
      value = 1
    }

    try_catch {
      try {
        function.run "planner_ops/live_add_attempt" {
          input = {actor: $actor, work_item_id: $input.work_item_id, timeline_id: $input.timeline_id, origin: $origin, correlation_id: $corr}
        } as $a1

        var.update $res {
          value = $a1
        }

        var.update $done {
          value = true
        }
      }

      catch {
        var.update $err {
          value = $error
        }
      }
    }

    var $msg {
      value = ($err|get:"message":"") ?? ""
    }

    var $lost_race {
      value = ($done == false) && ($msg|contains:"Duplicate record")
    }

    conditional {
      if ($lost_race) {
        var.update $attempts {
          value = 2
        }

        try_catch {
          try {
            function.run "planner_ops/live_add_attempt" {
              input = {actor: $actor, work_item_id: $input.work_item_id, timeline_id: $input.timeline_id, origin: $origin, correlation_id: $corr}
            } as $a2

            var.update $res {
              value = $a2
            }

            var.update $done {
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

    var.update $msg {
      value = ($err|get:"message":"") ?? ""
    }

    var.update $lost_race {
      value = ($done == false) && ($attempts == 2) && ($msg|contains:"Duplicate record")
    }

    conditional {
      if ($lost_race) {
        var.update $attempts {
          value = 3
        }

        try_catch {
          try {
            function.run "planner_ops/live_add_attempt" {
              input = {actor: $actor, work_item_id: $input.work_item_id, timeline_id: $input.timeline_id, origin: $origin, correlation_id: $corr}
            } as $a3

            var.update $res {
              value = $a3
            }

            var.update $done {
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

    var.update $msg {
      value = ($err|get:"message":"") ?? ""
    }

    // A refusal that carries its own code is passed on as it is. Anything else
    // (a third lost race, or a fault) gets one plain sentence; the detail goes to the event.
    var $has_code {
      value = $msg|contains:"(E-"
    }

    var $final_msg {
      value = "The job could not be added to the live day. Nothing was changed. Try again. (E-DEMAND-007)"
    }

    var $final_code {
      value = "E-DEMAND-007"
    }

    conditional {
      if ($has_code) {
        var.update $final_msg {
          value = $msg
        }

        var.update $final_code {
          value = ""
        }
      }
    }

    conditional {
      if ($done == false) {
        function.run "ops/log_event" {
          input = {feature: "DEMAND-1", step: "live_day_add", outcome: "failure", severity: "warn", error_code: $final_code, message: "A job was not added to a live day. Nothing was written.", user_id: $actor.user_id, account_id: $actor.account_id, entity_type: "planner_timeline", entity_id: $input.timeline_id, correlation_id: $corr, duration_ms: 0, metadata: {work_item_id: $input.work_item_id, origin: $origin, attempts: $attempts, detail: $msg}}
        } as $_fail
      }
    }

    precondition ($done == true) {
      error_type = "inputerror"
      error = $final_msg
    }

    var $added_refs {
      value = ($res|get:"added_item_refs":null) ?? []
    }

    foreach ($added_refs) {
      each as $ref {
        function.run "live/log_plan_change" {
          input = {timeline_id: $input.timeline_id, item_ref: $ref, change_type: "added", before: null, after: {work_item_id: $input.work_item_id, origin: $origin, added_to_live_day: true}, changed_by: $actor.user_id}
        } as $_chg
      }
    }

    var $status {
      value = ($res|get:"status":"") ?? ""
    }

    var $ev_message {
      value = "A job was added to a live day."
    }

    conditional {
      if ($status == "already_live") {
        var.update $ev_message {
          value = "The job was already on that live day. Nothing was added."
        }
      }
    }

    function.run "ops/log_event" {
      input = {feature: "DEMAND-1", step: "live_day_add", outcome: "success", severity: "info", error_code: "", message: $ev_message, user_id: $actor.user_id, account_id: $actor.account_id, entity_type: "planner_timeline", entity_id: $input.timeline_id, correlation_id: $corr, duration_ms: 0, metadata: {work_item_id: $input.work_item_id, origin: $origin, attempts: $attempts, result: $res}}
    } as $_ok
  }

  response = $res
}
