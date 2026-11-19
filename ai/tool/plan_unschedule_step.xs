// COP-5 story 01 (handoff 4-B) — the copilot takes a job step back off a DRAFT day in a plan of
// THIS business. Released by planner_ops/unschedule_step - a copy of live endpoint 576's rule -
// so the whole card the slot holds goes back to "waiting for a day", with the same checks
// (E-SCHED-006/007), the same write and the same logging as a person's click.
// Narrower than a person, on purpose:
//   - only for one business: the chat's, or the one an outside person names (E-COP-045);
//   - only for a step whose plan belongs to that business (copilot/plan_in_business, E-COP-038);
//   - only on a DRAFT day (epic governance): a live day is refused with E-COP-055 before the
//     shared rule's own E-SCHED-006 is reached.
// A step that is not on any day is not an error (already_unscheduled true). Nothing is deleted
// except the claim on the day; nothing here publishes to live.
tool plan_unschedule_step {
  instructions = "Take one job step (work_task_id) back off its day in a plan of this business. The whole card it is part of (that job's steps on the same slot) goes back to waiting for a day; the job and its steps are kept. Only draft days can be changed: a step on a day that is already live is refused, so tell the owner what you would change instead. A card that has work recorded on it is refused. A step that is not on any day comes back with already_unscheduled true and nothing changed. This never publishes anything to live."

  input {
    int work_task_id filters=min:1 {
      description = "The job step to take off its day."
    }

    int approval_id? {
      description = "Leave 0. Only when the owner approved a waiting action: its item number, sent with exactly the approved input."
    }

    int journey_architecture_id? {
      description = "Only for an outside assistant (no ticket): the business (architecture id) to plan in. Leave 0 in a copilot chat: the chat's business is used."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // The tool declares its action type, so the owner's level for it is really applied. The
    // summary is what the owner reads; the payload is this tool's exact input, never the ticket.
    var $act_summary {
      value = "Take job step #" ~ ($input.work_task_id|to_text) ~ " off its day"
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_unschedule_step", kind: "write", act_type: "plan_draft", act_payload: {work_task_id: $input.work_task_id}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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

    // COP-14 story 03: the chat's business, or (outside door, signed in by token) the one the person
    // named - checked by the gate to be in their account. The ONE rule: copilot/work_business.
    var $gate_pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    var $gate_via {
      value = $cop1_gate.via ?? ""
    }

    function.run "copilot/work_business" {
      input = {pin: $gate_pin, via: $gate_via, named: $input.journey_architecture_id}
    } as $work_biz

    var $pin {
      value = $work_biz.business ?? 0
    }

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    precondition ($pin != 0 && $caller_user != 0 && $caller_account != 0) {
      error_type = "inputerror"
      error = "This needs one business: use it in a copilot chat about a business or, from an outside assistant, pass journey_architecture_id. (E-COP-045)"
    }

    // Like any planner, the caller needs the Planner grant.
    function.run "usr/assert_module_access" {
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_unschedule_step"}
    } as $_plan_ok

    // The step -> its job -> its plan.
    db.query work_task {
      where = $db.work_task.id == $input.work_task_id
      return = {type: "single"}
      output = ["id", "work_item_id"]
    } as $wt

    var $wt_job {
      value = ($wt|get:"work_item_id":0) ?? 0
    }

    db.query work_item {
      where = $db.work_item.id == $wt_job
      return = {type: "single"}
      output = ["id", "workspace_id"]
    } as $job

    var $job_workspace {
      value = ($job|get:"workspace_id":0) ?? 0
    }

    precondition ($wt_job != 0 && $job_workspace != 0) {
      error_type = "notfound"
      error = "Step not found"
    }

    // Is that plan part of this business? The one rule, in one place.
    function.run "copilot/plan_in_business" {
      input = {account_id: $caller_account, workspace_id: $job_workspace, architecture_id: $pin, user_id: $caller_user}
    } as $plan_check

    var $plan_ok {
      value = (($plan_check|get:"ok":false) ?? false) == true
    }

    var $plan_reason {
      value = ($plan_check|get:"reason":"") ?? ""
    }

    precondition ($plan_ok == true || $plan_reason != "not_found") {
      error_type = "notfound"
      error = "Plan not found"
    }

    precondition ($plan_ok == true) {
      error_type = "accessdenied"
      error = "That plan isn't part of this business. This conversation works on one business only. (E-COP-038)"
    }

    // The step's slot -> its day. Not scheduled at all finds no rows and passes (the shared rule
    // answers already_unscheduled).
    db.query planner_task_work_task {
      where = $db.planner_task_work_task.work_task_id == $input.work_task_id
      return = {type: "single"}
      output = ["id", "planner_task_id"]
    } as $link

    var $slot_id {
      value = ($link|get:"planner_task_id":0) ?? 0
    }

    db.query planner_task {
      where = $db.planner_task.id == $slot_id
      return = {type: "single"}
      output = ["id", "timeline_id"]
    } as $slot

    var $slot_day {
      value = ($slot|get:"timeline_id":0) ?? 0
    }

    db.query planner_timeline {
      where = $db.planner_timeline.id == $slot_day
      return = {type: "single"}
      output = ["id", "status"]
    } as $day

    var $day_status {
      value = ($day|get:"status":"") ?? ""
    }

    // The copilot edits draft days only.
    precondition ($day_status != "published") {
      error_type = "accessdenied"
      error = "That day is already live. Only the owner changes a live day - tell them what you would change. (E-COP-055)"
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    function.run "planner_ops/unschedule_step" {
      input = {actor: $actor, work_task_id: $input.work_task_id, correlation_id: ""}
    } as $removed

    var $already {
      value = (($removed|get:"already_unscheduled":false) ?? false) == true
    }

    var $released_ids {
      value = ($removed|get:"released_work_task_ids":[]) ?? []
    }

    var $released_count {
      value = ($removed|get:"released_count":0) ?? 0
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
    work_task_id          : $input.work_task_id
    already_unscheduled   : $already
    released_work_task_ids: $released_ids
    released_count        : $released_count
  }
}
