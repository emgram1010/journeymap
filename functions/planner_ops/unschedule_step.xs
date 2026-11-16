// COP-5 story 01 (handoff 4-B) — THE ONE PLACE a job step (and the whole card
// its slot holds) is taken back off the schedule: O4 / BLK-1's rule, copied
// from live endpoint 576 (`DELETE work_task/{work_task_id}/schedule`) so the
// copilot's `plan_unschedule_step` tool releases a slot through exactly the
// same checks, writes and logging as a person's click. Until 576 is switched
// onto this function (handoff 4-C, not approved), the rule exists twice.
//
// Same answers as 576: "Step not found" for a missing or other-account step;
// not scheduled at all is NOT an error (already_unscheduled true); E-SCHED-006
// the day is published; E-SCHED-007 any step of the card was worked on (live
// status or any activity_log row). The job, steps and agreed work survive -
// only the claim on the day is released (planner/unschedule_work_task).
//
// `actor` is planner/resolve_actor's result: {user_id, account_id, role}.
function "planner_ops/unschedule_step" {
  input {
    json actor
    int work_task_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    var $actor {
      value = $input.actor
    }

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
    // another account can't be probed - same answer 560 gives.
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

    // Not scheduled at all is NOT an error: `already_unscheduled` says so.
    var $has_link {
      value = ($link != null)
    }

    var $timeline_status {
      value = ""
    }

    // Every step the slot covers. Seeded with -1 so the `in` clauses
    // below are never handed an empty array (CLAUDE.md).
    var $card_ids {
      value = [-1]
    }

    conditional {
      if ($has_link) {
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

        db.query planner_task_work_task {
          where = $db.planner_task_work_task.planner_task_id == $link.planner_task_id
          return = {type: "list"}
        } as $siblings

        foreach ($siblings) {
          each as $sib {
            array.push $card_ids {
              value = $sib.work_task_id
            }
          }
        }
      }
    }

    db.query activity_log {
      where = $db.activity_log.work_task_id in $card_ids
      return = {type: "count"}
    } as $activity_count

    db.query work_task {
      where = $db.work_task.id in $card_ids && $db.work_task.status != "not_started"
      return = {type: "count"}
    } as $moved_count

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($has_link && $timeline_status == "published") {
        var.update $reject_code {
          value = "E-SCHED-006"
        }

        var.update $reject_msg {
          value = "That day is already live, so this step can't be taken off it. (E-SCHED-006)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $has_link && ($moved_count > 0 || $activity_count > 0)) {
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
        message       : "Card returned to the backlog."
        metadata      : {
          workspace_id   : $job.workspace_id
          work_item_id   : $wt.work_item_id
          removed_slot_id: $removed.removed_slot_id
          container      : $removed.container
          was_linked     : $has_link
          released_count : $removed.released_count
        }
      }
    }
  }

  response = {
    work_task_id          : $input.work_task_id
    already_unscheduled   : ($has_link == false)
    removed_slot_id       : $removed.removed_slot_id
    container             : $removed.container
    released_work_task_ids: $removed.released_work_task_ids
    released_count        : $removed.released_count
  }
}
