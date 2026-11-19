// COP-5 story 01 (handoff 4-B) — the copilot pins the start time of one scheduled slot on a draft
// day in a plan of THIS business. Stored by planner_ops/set_start_override - a copy of live
// endpoint 617's rule - so the checks (E-SCHED-009/010/011), the write, the race answer and the
// logging are exactly a person's.
// Narrower than a person, on purpose:
//   - only for one business: the chat's, or the one an outside person names (E-COP-045);
//   - only for a slot whose plan belongs to that business (copilot/plan_in_business, E-COP-038);
//   - only on a DRAFT day: a live day is the owner's to change (E-COP-055).
// A slot that does not exist answers "Task not found", like 617. Nothing here publishes to live.
tool plan_set_start_time {
  instructions = "Pin the start time of one scheduled slot (planner_task_id, the slot on a day - see plan_schedule_step / plan_schedule_card) in a plan of this business. start_time is HH:MM in 24-hour time. reason is optional, 200 characters at most. Later work on that day flows on from it. A slot that is not on a day yet is refused. Only draft days can be changed: a day that is already live is refused, so tell the owner what you would change instead. This never publishes anything to live."

  input {
    int planner_task_id filters=min:1 {
      description = "The scheduled slot to pin."
    }

    text start_time filters=trim {
      description = "HH:MM, 24-hour."
    }

    text reason? filters=trim {
      description = "Optional, up to 200 characters."
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
      value = "Start slot #" ~ ($input.planner_task_id|to_text) ~ " at " ~ $input.start_time
    }

    // COP-5 story 01 (2026-11-16): a change to a day that is already live is its own action type,
    // plan_live_change, which always waits for the owner (locked). copilot/live_target answers only
    // for the caller's own account, so it reveals nothing about anyone else's days.
    function.run "copilot/live_target" {
      input = {ticket: $input.ticket, timeline_id: 0, planner_task_id: $input.planner_task_id, work_task_id: 0, work_item_id: 0}
    } as $live_target

    var $act_type {
      value = ((($live_target.live ?? false) == true) ? "plan_live_change" : "plan_draft")
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_set_start_time", kind: "write", act_type: $act_type, act_payload: {planner_task_id: $input.planner_task_id, start_time: $input.start_time, reason: $input.reason}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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

    var $gate_context {
      value = $cop1_gate.context ?? ""
    }

    var $gate_account {
      value = $cop1_gate.account_id ?? 0
    }

    function.run "copilot/work_business" {
      input = {pin: $gate_pin, via: $gate_via, context: $gate_context, named: $input.journey_architecture_id, account_id: $gate_account}
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
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_set_start_time"}
    } as $_plan_ok

    // The slot -> its plan and its day.
    db.query planner_task {
      where = $db.planner_task.id == $input.planner_task_id
      return = {type: "single"}
      output = ["id", "workspace_id", "timeline_id"]
    } as $slot

    var $slot_id {
      value = ($slot|get:"id":0) ?? 0
    }

    var $slot_workspace {
      value = ($slot|get:"workspace_id":0) ?? 0
    }

    var $slot_day {
      value = ($slot|get:"timeline_id":0) ?? 0
    }

    precondition ($slot_id != 0 && $slot_workspace != 0) {
      error_type = "notfound"
      error = "Task not found"
    }

    // Is that plan part of this business? The one rule, in one place.
    function.run "copilot/plan_in_business" {
      input = {account_id: $caller_account, workspace_id: $slot_workspace, architecture_id: $pin, user_id: $caller_user}
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

    // The copilot edits draft days only. A slot with no day (0) finds no row and passes on to
    // the shared function, which refuses it with E-SCHED-010 like 617.
    db.query planner_timeline {
      where = $db.planner_timeline.id == $slot_day
      return = {type: "single"}
      output = ["id", "status"]
    } as $day

    var $day_status {
      value = ($day|get:"status":"") ?? ""
    }

    precondition ($day_status != "published" || $act_type == "plan_live_change") {
      error_type = "accessdenied"
      error = "That day is already live. Only the owner changes a live day - tell them what you would change. (E-COP-055)"
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    function.run "planner_ops/set_start_override" {
      input = {
        actor          : $actor
        planner_task_id: $input.planner_task_id
        start_time     : $input.start_time
        reason         : $input.reason
        correlation_id : ""
      }
    } as $saved

    var $saved_start {
      value = ($saved|get:"start_override":"") ?? ""
    }

    var $was_created {
      value = (($saved|get:"created":false) ?? false) == true
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
    planner_task_id: $input.planner_task_id
    start_time     : $saved_start
    created        : $was_created
  }
}
