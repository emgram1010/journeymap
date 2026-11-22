// COP-5 story 03 — the copilot records work on a task that is ITS OWN: start, finish, block,
// unblock, skip, reopen, or a note. The event goes through log/record_task_event - the same
// function the performer app's endpoint (563) calls - so the status rules, the activity log and
// plan-vs-actual are exactly a person's. source is "ai".
// Narrower than a person, on purpose (decision D-6, how an AI may do work):
//   - only in a copilot conversation about one business, and the job's map must be in it;
//   - only a task on a PUBLISHED day that the frozen publication gives to a plan person linked to
//     the caller (R8: the same answer list_my_tasks and the performer app give). An
//     unassigned or unscheduled task is NOT the copilot's (a person may record those; it may not);
//   - the caller needs the Execution grant, like any performer (usr/assert_module_access).
// Every miss answers "Task not found"; not-yours answers E-COP-054.
tool record_my_task_event {
  instructions = "Record an event on one of YOUR tasks (work_task_id from list_my_tasks): event_type is started, completed, blocked, unblocked, skipped, reopened or note. blocked needs reason_code (waiting_on_someone, missing_information, something_went_wrong or other) and a short note. If you cannot complete a task, block it with a reason and tell the owner - never guess. You can only record completed after doing real work on the task with your other tools; otherwise it is refused (E-COP-075) - then explain to the owner, do not retry. You cannot record anything on a task assigned to someone else. From an outside assistant, pass journey_architecture_id."

  input {
    int work_task_id filters=min:1
    text event_type filters=trim|lower
    text reason_code? filters=trim
    text note? filters=trim

    int approval_id? {
      description = "Leave 0. Only when the owner approved a waiting action: its item number, sent with exactly the approved input."
    }

    int journey_architecture_id? {
      description = "Only for an outside assistant (no ticket): the business (architecture id) to work in. Leave 0 in a copilot chat: the chat's business is used."
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

    // COP-8 story 01: "done" from the copilot means it did some work. The rule lives in
    // copilot/work_done_check (an AI identity needs at least one other allowed tool call since the
    // task started). It runs BEFORE the gate, so a completion that will be refused never reaches
    // the owner's Approvals list as a "waiting" item, and before any write. People pass; "skipped"
    // is not checked. The check never throws; anything it cannot judge comes back not ok (fails closed).
    var $work_done_ok {
      value = true
    }

    conditional {
      if ($input.event_type == "completed") {
        var.update $work_done_ok {
          value = false
        }

        function.run "copilot/work_done_check" {
          input = {ticket: $input.ticket, work_task_id: $input.work_task_id}
        } as $work_done

        var.update $work_done_ok {
          value = ($work_done.ok == true)
        }
      }
    }

    precondition ($work_done_ok == true) {
      error_type = "inputerror"
      error = "The copilot can't mark this task done yet: it hasn't done any work on it. It needs to use at least one tool for the task first, or a person can mark it done. (E-COP-075)"
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "record_my_task_event", kind: "write", act_type: $act_type, act_payload: {work_task_id: $input.work_task_id, event_type: $input.event_type, reason_code: $input.reason_code, note: $input.note}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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

    var $gate_pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    var $gate_via {
      value = $cop1_gate.via ?? ""
    }

    var $gate_context {
      value = $cop1_gate.context ?? ""
    }

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    function.run "copilot/work_business" {
      input = {pin: $gate_pin, via: $gate_via, context: $gate_context, named: $input.journey_architecture_id, account_id: $caller_account}
    } as $work_biz

    var $pin {
      value = $work_biz.business ?? 0
    }

    precondition ($pin != 0 && $caller_user != 0 && $caller_account != 0) {
      error_type = "inputerror"
      error = "This needs one business: use it in a copilot chat about a business or, from an outside assistant, pass journey_architecture_id. (E-COP-045)"
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

    // Is it mine? The slot this task is scheduled on and its day (to find the publication).
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

    db.query planner_timeline {
      where = $db.planner_timeline.id == $timeline_id && $timeline_id != 0
      return = {type: "single"}
      output = ["id", "agent_id", "status", "planned_date"]
    } as $day

    var $day_status {
      value = ($day|get:"status":"") ?? ""
    }

    // Final review R8 (2026-11-16): "is this task mine" has ONE answer - the frozen publication,
    // the same one list_my_tasks, scheduled runs and the performer app read
    // (perform/collect_published_items). A slot dragged onto or off the copilot after the day went
    // live, and not re-published, no longer gives two answers. The live slot is used only to find
    // which day's publication to read.
    var $day_date {
      value = (($day|get:"planned_date":"") ?? "")|to_text
    }

    var $pub_wt_ids {
      value = [-1]
    }

    conditional {
      if ($day_date != "" && $day_status == "published") {
        function.run "perform/resolve_agents" {
          input = {account_id: $caller_account, user_id: $caller_user}
        } as $resolved

        function.run "perform/collect_published_items" {
          input = {account_id: $caller_account, date: $day_date, agent_ids: $resolved.agent_ids}
        } as $collected

        foreach ($collected.items) {
          each as $pi {
            foreach ($pi.work_task_ids) {
              each as $pw {
                array.push $pub_wt_ids {
                  value = $pw
                }
              }
            }
          }
        }
      }
    }

    db.query work_task {
      where = $db.work_task.id == $input.work_task_id && $db.work_task.id in $pub_wt_ids
      return = {type: "count"}
    } as $in_publication

    var $is_mine {
      value = ($in_publication > 0 && $day_status == "published")
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
