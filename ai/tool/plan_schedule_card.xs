// COP-5 story 01 (handoff 4-B) — the copilot puts a whole card (one job's unscheduled steps for
// one actor row, lens_key) onto a DRAFT day in a plan of THIS business. The slot is made by
// planner_ops/schedule_card - a copy of live endpoint 583's rule - so the checks (E-BLK-001,
// E-SCHED-001/002/008, E-COP-059 for a switched-off copilot's column), the writes and the
// logging are exactly a person's.
// Narrower than a person, on purpose:
//   - only in a copilot conversation about one business (E-COP-045);
//   - only on a day whose plan belongs to that business (copilot/plan_in_business, E-COP-038);
//   - only on a DRAFT day: a published day is the owner's to change (E-COP-055);
//   - it cannot hand the card to someone other than the day's person (assignee is always 0).
// A day that does not exist answers "Day not found". Nothing here publishes to live.
tool plan_schedule_card {
  instructions = "Put a whole card onto one person's day (timeline_id) in a plan of this business: every step of one job (work_item_id) for one row of its map (lens_key, the row's key), in the map's stage order, as one slot. The card then belongs to that day's person; you cannot give it to someone else here. duration_minutes is how long to set aside, 1 to 1440; leave it 0 to use the card's expected time. Only draft days can be changed: a day that is already live is refused, so tell the owner what you would change instead. A card with any step already on the schedule, with no steps, or whose job is cancelled, is refused. This never publishes anything to live. If over_capacity is true, tell the owner that day is over that person's capacity by over_by_minutes minutes; do not move or remove work yourself."

  input {
    int work_item_id filters=min:1 {
      description = "The job whose card to schedule."
    }

    text lens_key filters=trim {
      description = "The map row (actor) key of the card."
    }

    int timeline_id filters=min:1 {
      description = "The day to put it on. Must be a draft day."
    }

    int duration_minutes? {
      description = "Minutes to set aside, 1 to 1440. Leave 0 to use the card's expected time."
    }

    int approval_id? {
      description = "Leave 0. Only when the owner approved a waiting action: its item number, sent with exactly the approved input."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // The tool declares its action type, so the owner's level for it is really applied. The
    // summary is what the owner reads; the payload is this tool's exact input, never the ticket.
    var $act_summary {
      value = "Put job #" ~ ($input.work_item_id|to_text) ~ " (" ~ $input.lens_key ~ ") on day #" ~ ($input.timeline_id|to_text)
    }

    // COP-5 story 01 (2026-11-16): a change to a day that is already live is its own action type,
    // plan_live_change, which always waits for the owner (locked). copilot/live_target answers only
    // for the caller's own account, so it reveals nothing about anyone else's days.
    function.run "copilot/live_target" {
      input = {ticket: $input.ticket, timeline_id: $input.timeline_id, planner_task_id: 0, work_task_id: 0, work_item_id: 0}
    } as $live_target

    var $act_type {
      value = ((($live_target.live ?? false) == true) ? "plan_live_change" : "plan_draft")
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "plan_schedule_card", kind: "write", act_type: $act_type, act_payload: {work_item_id: $input.work_item_id, lens_key: $input.lens_key, timeline_id: $input.timeline_id, duration_minutes: $input.duration_minutes}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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

    // Like any planner, the caller needs the Planner grant.
    function.run "usr/assert_module_access" {
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_schedule_card"}
    } as $_plan_ok

    // The day -> its plan and its status.
    db.query planner_timeline {
      where = $db.planner_timeline.id == $input.timeline_id
      return = {type: "single"}
      output = ["id", "workspace_id", "status", "agent_id"]
    } as $day

    var $day_agent {
      value = ($day|get:"agent_id":0) ?? 0
    }

    var $day_id {
      value = ($day|get:"id":0) ?? 0
    }

    var $day_workspace {
      value = ($day|get:"workspace_id":0) ?? 0
    }

    var $day_status {
      value = ($day|get:"status":"") ?? ""
    }

    precondition ($day_id != 0 && $day_workspace != 0) {
      error_type = "notfound"
      error = "Day not found"
    }

    // Is that plan part of this business? The one rule, in one place.
    function.run "copilot/plan_in_business" {
      input = {account_id: $caller_account, workspace_id: $day_workspace, architecture_id: $pin, user_id: $caller_user}
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

    // The copilot edits draft days only.
    precondition ($day_status != "published" || $act_type == "plan_live_change") {
      error_type = "accessdenied"
      error = "That day is already live. Only the owner changes a live day - tell them what you would change. (E-COP-055)"
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    var $has_duration {
      value = ($input.duration_minutes != 0)
    }

    // The shared rule also refuses a switched-off copilot's column (assert_agent_assignable).
    function.run "planner_ops/schedule_card" {
      input = {
        actor               : $actor
        work_item_id        : $input.work_item_id
        lens_key            : $input.lens_key
        timeline_id         : $input.timeline_id
        duration_minutes    : $input.duration_minutes
        has_duration_minutes: $has_duration
        assignee_agent_id   : 0
        correlation_id      : ""
      }
    } as $scheduled

    var $slot {
      value = $scheduled|get:"planner_task":null
    }

    var $slot_id {
      value = ($slot|get:"id":0) ?? 0
    }

    var $step_ids {
      value = ($scheduled|get:"work_task_ids":[]) ?? []
    }

    var $step_count {
      value = ($scheduled|get:"step_count":0) ?? 0
    }

    var $expected_minutes {
      value = ($scheduled|get:"expected_minutes":0) ?? 0
    }

    var $scheduled_minutes {
      value = ($scheduled|get:"scheduled_minutes":0) ?? 0
    }

    // "Respects capacity" (same as plan_schedule_step): add up the day and compare with that
    // person's daily capacity. A WARNING only; the copilot reports it and moves nothing.
    db.query planner_task {
      where = $db.planner_task.timeline_id == $input.timeline_id
      return = {type: "list"}
      output = ["id", "duration_minutes"]
    } as $day_slots

    var $day_planned {
      value = 0
    }

    foreach ($day_slots) {
      each as $ds {
        var.update $day_planned {
          value = $day_planned + ($ds.duration_minutes ?? 0)
        }
      }
    }

    db.query planner_agent {
      where = $db.planner_agent.id == $day_agent && $day_agent != 0
      return = {type: "single"}
      output = ["id", "daily_capacity_hours"]
    } as $day_person

    // An untouched decimal is 0, not null (CLAUDE.md): 0 means "not set", and the screen uses 8.
    var $cap_hours {
      value = ($day_person|get:"daily_capacity_hours":0) ?? 0
    }

    conditional {
      if ($cap_hours == 0) {
        var.update $cap_hours {
          value = 8
        }
      }
    }

    var $cap_minutes {
      value = $cap_hours * 60
    }

    var $over_capacity {
      value = $day_planned > $cap_minutes
    }

    var $over_by {
      value = 0
    }

    conditional {
      if ($over_capacity == true) {
        var.update $over_by {
          value = $day_planned - $cap_minutes
        }
      }
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
    planner_task_id     : $slot_id
    work_item_id        : $input.work_item_id
    lens_key            : $input.lens_key
    timeline_id         : $input.timeline_id
    work_task_ids       : $step_ids
    step_count          : $step_count
    expected_minutes    : $expected_minutes
    scheduled_minutes   : $scheduled_minutes
    day_planned_minutes : $day_planned
    day_capacity_minutes: $cap_minutes
    over_capacity       : $over_capacity
    over_by_minutes     : $over_by
  }
}
