// COP-5 story 01 - "Changing a day that is already live waits for me". A planner tool calls this BEFORE its gate call, to choose its action type: plan_live_change (waits for the owner) when the target is on a live day, else plan_draft. Finds the caller from the ticket with usr/tool_caller - the same identity check the gate makes - and answers live=true ONLY for a target in the caller's own account, so a foreign id can never be probed (anything unknown or foreign is live=false and the tool's own checks then refuse it as before). Give ONE of: timeline_id (a day), planner_task_id (a slot), work_task_id (a scheduled step), work_item_id (a job - live if any of it is on a live day, jobs/time_window_live_refs). Never throws; returns nothing but the yes/no.
function "copilot/live_target" {
  input {
    text ticket? filters=trim
    int timeline_id?
    int planner_task_id?
    int work_task_id?
    int work_item_id?
  }

  stack {
    var $live {
      value = false
    }

    try_catch {
      try {
        function.run "usr/tool_caller" {
          input = {ticket: $input.ticket}
        } as $who

        var $account_id {
          value = (($who.allowed ?? false) == true) ? ($who.account_id ?? 0) : 0
        }

        // A step -> its slot.
        db.query planner_task_work_task {
          where = $db.planner_task_work_task.work_task_id == $input.work_task_id && $input.work_task_id != 0
          return = {type: "single"}
          output = ["planner_task_id"]
        } as $link

        var $slot_id {
          value = (($input.planner_task_id != 0) ? $input.planner_task_id : (($link|get:"planner_task_id":0) ?? 0))
        }

        // A slot -> its day.
        db.query planner_task {
          where = $db.planner_task.id == $slot_id && $slot_id != 0
          return = {type: "single"}
          output = ["timeline_id"]
        } as $slot

        var $day_id {
          value = (($input.timeline_id != 0) ? $input.timeline_id : (($slot|get:"timeline_id":0) ?? 0))
        }

        db.query planner_timeline {
          where = $db.planner_timeline.id == $day_id && $day_id != 0
          return = {type: "single"}
          output = ["id", "workspace_id", "status"]
        } as $day

        var $ws_id {
          value = ($day|get:"workspace_id":0) ?? 0
        }

        db.query planner_workspace {
          where = $db.planner_workspace.id == $ws_id && $ws_id != 0
          return = {type: "single"}
          output = ["account_id"]
        } as $ws

        var $day_live {
          value = ($account_id != 0) && ((($ws|get:"account_id":0) ?? 0) == $account_id) && ((($day|get:"status":"") ?? "") == "published")
        }

        // A job -> live if any of it sits on a live day.
        db.query work_item {
          where = $db.work_item.id == $input.work_item_id && $input.work_item_id != 0
          return = {type: "single"}
          output = ["account_id"]
        } as $job

        var $job_mine {
          value = ($account_id != 0) && ($input.work_item_id != 0) && ((($job|get:"account_id":0) ?? 0) == $account_id)
        }

        var $job_live {
          value = false
        }

        conditional {
          if ($job_mine == true) {
            function.run "jobs/time_window_live_refs" {
              input = {work_item_id: $input.work_item_id}
            } as $refs

            var.update $job_live {
              value = (($refs|get:"live":false) ?? false) == true
            }
          }
        }

        var.update $live {
          value = ($day_live == true) || ($job_live == true)
        }
      }

      catch {
        var.update $live {
          value = false
        }
      }
    }
  }

  response = {live: $live}
}
