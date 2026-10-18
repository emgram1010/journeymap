// O4 (2026-10-17) — Take a job step back off the schedule.
//
// Built on the founder's instruction to execute the gap list, which is
// the approval CLAUDE.md requires for a delete. It is the least
// destructive one in the planner: the job, the step and the agreed
// work all survive — only the claim on somebody's day is released, and
// the step goes straight back to "waiting for a day".
//
// WHY IT WAS MISSING. SCHED-1 built `POST work_task/{id}/schedule` and
// nothing to undo it. That was survivable while jobs were created by
// API call; GAP-FIX W1 put a Schedule button in front of a planner and
// turned it into a one-way door. A mis-placed step could be MOVED to
// another day but never taken off, because `backlog_work` decides
// "unscheduled" purely by absence from `planner_task_work_task`.
//
// TWO REFUSALS, both the same shape as the deletes already live.
// (First written as E-SCHED-002/003 — both were already taken, by the
// duration check and the concurrent-edit check. Caught by grepping the
// catalog before wiring the UI, not by anything failing.)
//
//   E-SCHED-006  the day is PUBLISHED. LIVE-1 froze that day and handed
//                it to someone; the publication snapshot and every
//                activity_log row still name this slot. Same reasoning
//                as E-P3A-003 on deleting a published timeline.
//   E-SCHED-007  the step has been WORKED ON. Checked two ways, because
//                either alone has a hole: the live status (anything but
//                not_started means it moved) AND any activity_log row
//                (a note can be left on a step nobody has started, and
//                that note is evidence the slot existed).
//
// Everything else — a draft day, an untouched step — unschedules.
query "work_task/{work_task_id}/schedule" verb=DELETE {
  api_group = "planner"
  auth = "user"

  input {
    int work_task_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get work_task {
      field_name = "id"
      field_value = $input.work_task_id
    } as $wt

    precondition ($wt != null) {
      error_type = "notfound"
      error = "Step not found"
    }

    db.get work_item {
      field_name = "id"
      field_value = $wt.work_item_id
    } as $job

    // Tenancy reads as "not found", never "forbidden", so ids from
    // another account can't be probed — same answer 560 gives.
    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Step not found"
    }

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $job.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "SCHED-1"
        step       : "unschedule_block"
        entity_type: "work_task"
        entity_id  : $input.work_task_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    db.get planner_task_work_task {
      field_name = "work_task_id"
      field_value = $input.work_task_id
    } as $link

    // Not scheduled at all is NOT an error. Two planners clicking
    // "Unschedule" on the same step both get the outcome they wanted,
    // and `already_unscheduled` says which one did the work — the same
    // idempotent shape as the cancel-job endpoint's
    // `was_already_cancelled`.
    var $has_link {
      value = ($link != null)
    }

    var $timeline_status {
      value = ""
    }

    conditional {
      if ($has_link == true) {
        db.get planner_task {
          field_name = "id"
          field_value = $link.planner_task_id
        } as $slot

        db.get planner_timeline {
          field_name = "id"
          field_value = $slot.timeline_id
        } as $tl

        var.update $timeline_status {
          value = ($tl.status ?? "")
        }
      }
    }

    db.query activity_log {
      where = $db.activity_log.work_task_id == $input.work_task_id
      return = {type: "count"}
    } as $activity_count

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($has_link == true && $timeline_status == "published") {
        var.update $reject_code {
          value = "E-SCHED-006"
        }

        var.update $reject_msg {
          value = "That day is already live, so this step can't be taken off it. (E-SCHED-006)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $has_link == true && ($wt.status != "not_started" || $activity_count > 0)) {
        var.update $reject_code {
          value = "E-SCHED-007"
        }

        var.update $reject_msg {
          value = "Work has already been recorded on this step, so it can't be unscheduled. (E-SCHED-007)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "SCHED-1"
            step          : "unschedule_block"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Unschedule refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    function.run "planner/unschedule_work_task" {
      input = {workspace_id: $job.workspace_id, work_task_id: $input.work_task_id}
    } as $removed

    function.run "ops/log_event" {
      input = {
        feature       : "SCHED-1"
        step          : "unschedule_block"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "work_task"
        entity_id     : $input.work_task_id
        correlation_id: $input.correlation_id
        message       : "Job step returned to the backlog."
        metadata      : {
          workspace_id   : $job.workspace_id
          work_item_id   : $wt.work_item_id
          removed_slot_id: $removed.removed_slot_id
          container      : $removed.container
          was_linked     : $has_link
        }
      }
    }
  }

  response = {
    work_task_id         : $input.work_task_id
    already_unscheduled  : ($has_link == false)
    removed_slot_id      : $removed.removed_slot_id
    container            : $removed.container
  }
}
