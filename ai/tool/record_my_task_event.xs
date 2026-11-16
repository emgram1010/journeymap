// COP-5 story 03 — the copilot records work on a task that is ITS OWN: start, finish, block,
// unblock, skip, reopen, or a note. The event goes through log/record_task_event - the same
// function the performer app's endpoint (563) calls - so the status rules, the activity log and
// plan-vs-actual are exactly a person's. source is "ai".
// Narrower than a person, on purpose (decision D-6, how an AI may do work):
//   - only in a copilot conversation about one business, and the job's map must be in it;
//   - only a task whose scheduled slot is on a PUBLISHED day and whose effective assignee (the
//     slot's own override, else the day's person) is a plan person linked to the caller. An
//     unassigned or unscheduled task is NOT the copilot's (a person may record those; it may not);
//   - the caller needs the Execution grant, like any performer (usr/assert_module_access).
// Every miss answers "Task not found"; not-yours answers E-COP-054.
tool record_my_task_event {
  instructions = "Record an event on one of YOUR tasks (work_task_id from list_my_tasks): event_type is started, completed, blocked, unblocked, skipped, reopened or note. blocked needs reason_code (waiting_on_someone, missing_information, something_went_wrong or other) and a short note. If you cannot complete a task, block it with a reason and tell the owner - never guess. You cannot record anything on a task assigned to someone else."

  input {
    int work_task_id filters=min:1
    text event_type filters=trim|lower
    text reason_code? filters=trim
    text note? filters=trim

    int approval_id? {
      description = "Leave 0. Only when the owner approved a waiting action: its item number, sent with exactly the approved input."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // Final review R1: the tool declares its action type, so the owner's level for it is really
    // applied (runs on its own / runs then tells you / waits for you). The summary is what the
    // owner reads; the payload is this tool's exact input, never the ticket.
    var $act_summary {
      value = "Record '" ~ $input.event_type ~ "' on its task #" ~ ($input.work_task_id|to_text)
    }

    // Final review R2: marking its own work done or skipped is its own action type (work_complete),
    // which waits for the owner unless the owner loosens it. An AI's word alone never closes a task.
    var $act_type {
      value = "work_update"
    }

    conditional {
      if ($input.event_type == "completed" || $input.event_type == "skipped") {
        var.update $act_type {
          value = "work_complete"
        }
      }
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "record_my_task_event", kind: "write", act_type: $act_type, act_payload: {work_task_id: $input.work_task_id, event_type: $input.event_type, reason_code: $input.reason_code, note: $input.note}, act_summary: $act_summary, act_approval_id: $input.approval_id}
    } as $cop1_gate

    var $act_action_id {
      value = $cop1_gate.action_id ?? 0
    }

    var $act_account_id {
      value = $cop1_gate.account_id ?? 0
    }

    // Everything from here runs inside a try, so a refusal or a failed write is reported to the
    // approval list (copilot/action_close) before it is passed on unchanged.
    var $act_error {
      value = null
    }

    try_catch {
      try {
        group {
          stack {

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    precondition ($pin != 0 && $caller_user != 0 && $caller_account != 0) {
      error_type = "inputerror"
      error = "This only works in a copilot conversation about one business. (E-COP-045)"
    }

    // The task -> its job -> the pinned version -> the map.
    db.query work_task {
      where = $db.work_task.id == $input.work_task_id
      return = {type: "single"}
      output = ["id", "work_item_id"]
    } as $task

    var $job_id {
      value = ($task|get:"work_item_id":0) ?? 0
    }

    db.query work_item {
      where = $db.work_item.id == $job_id && $job_id != 0
      return = {type: "single"}
      output = ["id", "account_id", "journey_map_version_id"]
    } as $job

    var $job_account {
      value = ($job|get:"account_id":0) ?? 0
    }

    var $version_id {
      value = ($job|get:"journey_map_version_id":0) ?? 0
    }

    db.query journey_map_version {
      where = $db.journey_map_version.id == $version_id && $version_id != 0
      return = {type: "single"}
      output = ["id", "journey_map_id"]
    } as $version

    var $map_id {
      value = ($version|get:"journey_map_id":0) ?? 0
    }

    db.query journey_map {
      where = $db.journey_map.id == $map_id && $map_id != 0
      return = {type: "single"}
      output = ["id", "account_id", "journey_architecture"]
    } as $map

    var $map_arch {
      value = ($map|get:"journey_architecture":0) ?? 0
    }

    precondition ($map_id != 0 && $job_account == $caller_account) {
      error_type = "notfound"
      error = "Task not found"
    }

    precondition ($map_arch == $pin) {
      error_type = "accessdenied"
      error = "That belongs to another business. This conversation works on one business only; switch business to work on it. (E-COP-038)"
    }

    // Is it mine? The slot this task is scheduled on, its day, and the effective assignee.
    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id == $input.work_task_id
      return = {type: "single"}
      output = ["id", "planner_task_id"]
    } as $link

    var $slot_id {
      value = ($link|get:"planner_task_id":0) ?? 0
    }

    db.query planner_task {
      where = $db.planner_task.id == $slot_id && $slot_id != 0
      return = {type: "single"}
      output = ["id", "timeline_id", "assignee_agent_id"]
    } as $slot

    var $timeline_id {
      value = ($slot|get:"timeline_id":0) ?? 0
    }

    var $override_agent {
      value = ($slot|get:"assignee_agent_id":0) ?? 0
    }

    db.query planner_timeline {
      where = $db.planner_timeline.id == $timeline_id && $timeline_id != 0
      return = {type: "single"}
      output = ["id", "agent_id", "status"]
    } as $day

    var $day_agent {
      value = ($day|get:"agent_id":0) ?? 0
    }

    var $day_status {
      value = ($day|get:"status":"") ?? ""
    }

    var $eff_agent {
      value = $day_agent
    }

    conditional {
      if ($override_agent != 0) {
        var.update $eff_agent {
          value = $override_agent
        }
      }
    }

    db.query planner_agent {
      where = $db.planner_agent.id == $eff_agent && $eff_agent != 0
      return = {type: "single"}
      output = ["id", "user_id"]
    } as $assignee

    var $assignee_user {
      value = ($assignee|get:"user_id":0) ?? 0
    }

    var $is_mine {
      value = ($assignee_user != 0 && $assignee_user == $caller_user && $day_status == "published")
    }

    conditional {
      if ($is_mine == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-5"
            step       : "record_my_task_event"
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-COP-054"
            message    : "The copilot tried to record work on a task that is not assigned to it on a published day."
            user_id    : $caller_user
            account_id : $caller_account
            entity_type: "work_task"
            entity_id  : $input.work_task_id
            metadata   : {event_type: $input.event_type, day_status: $day_status}
          }
        } as $_not_mine_logged
      }
    }

    precondition ($is_mine == true) {
      error_type = "accessdenied"
      error = "That task isn't assigned to you on a published day, so you can't record work on it. (E-COP-054)"
    }

    // Like any performer, the caller needs the Execution grant.
    function.run "usr/assert_module_access" {
      input = {actor_user_id: $caller_user, module: "execution", or_module: "", step: "tool/record_my_task_event"}
    } as $_exec_ok

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    security.create_uuid as $event_uuid

    function.run "log/record_task_event" {
      input = {
        actor          : $actor
        work_task_id   : $input.work_task_id
        event_type     : $input.event_type
        reason_code    : $input.reason_code
        note           : $input.note
        client_event_id: $event_uuid
        correlation_id : ""
        source         : "ai"
        soft           : false
        system_note    : false
      }
    } as $recorded

    var $was_rejected {
      value = (($recorded|get:"rejected":false) ?? false) == true
    }

    var $reject_text {
      value = ($recorded|get:"message":"") ?? ""
    }

    precondition ($was_rejected == false) {
      error_type = "inputerror"
      error = $reject_text
    }
          }
        }
      }

      catch {
        var.update $act_error {
          value = $error
        }
      }
    }

    // How it ended goes to the approval list; any error is then passed on with its own kind.
    function.run "copilot/action_close" {
      input = {action_id: $act_action_id, account_id: $act_account_id, error: $act_error}
    } as $_act_closed
  }

  response = {
    work_task_id: $input.work_task_id
    event_type  : $input.event_type
    from        : ($recorded|get:"from":"")
    to          : ($recorded|get:"to":"")
    job_status  : ($recorded|get:"job_status":"")
  }
}
