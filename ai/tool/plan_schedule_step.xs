// COP-5 story 01 — the copilot puts one job step onto a day in a plan of THIS business.
// The slot is made by planner_ops/schedule_work_task - the same function the planner's own
// endpoint (560) is being moved onto - so the checks (same plan, not already scheduled, job not
// cancelled, duration 1..1440), the writes and the logging are exactly a person's.
// Narrower than a person, on purpose:
//   - only in a copilot conversation about one business (E-COP-045);
//   - only on a day whose plan belongs to that business (copilot/plan_in_business, E-COP-038);
//   - only on a DRAFT day: a published day is the owner's to change (E-COP-055);
//   - it cannot hand the step to someone other than the day's person (assignee is always 0).
// A day that does not exist answers "Day not found". Nothing here publishes to live.
tool plan_schedule_step {
  instructions = "Put one job step (work_task_id) onto one person's day (timeline_id, from plan_start_day) in a plan of this business. The step then belongs to that day's person; you cannot give it to someone else here. duration_minutes is how long to set aside, 1 to 1440; leave it 0 to use the step's expected time. Only draft days can be changed: a day that is already live is refused, so tell the owner what you would change instead. A step that is already on the schedule, or whose job is cancelled, is refused. This never publishes anything to live."

  input {
    int work_task_id filters=min:1 {
      description = "The job step to schedule."
    }

    int timeline_id filters=min:1 {
      description = "The day to put it on. Must be a draft day."
    }

    int duration_minutes? {
      description = "Minutes to set aside, 1 to 1440. Leave 0 to use the step's expected time."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "plan_schedule_step", kind: "write"}
    } as $cop1_gate

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
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_schedule_step"}
    } as $_plan_ok

    // The day -> its plan and its status.
    db.query planner_timeline {
      where = $db.planner_timeline.id == $input.timeline_id
      return = {type: "single"}
      output = ["id", "workspace_id", "status"]
    } as $day

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
    precondition ($day_status != "published") {
      error_type = "accessdenied"
      error = "That day is already live. Only the owner changes a live day - tell them what you would change. (E-COP-055)"
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    var $has_duration {
      value = ($input.duration_minutes != 0)
    }

    function.run "planner_ops/schedule_work_task" {
      input = {
        actor               : $actor
        work_task_id        : $input.work_task_id
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

    var $expected_minutes {
      value = ($scheduled|get:"expected_minutes":0) ?? 0
    }

    var $scheduled_minutes {
      value = ($scheduled|get:"scheduled_minutes":0) ?? 0
    }
  }

  response = {
    planner_task_id  : $slot_id
    work_task_id     : $input.work_task_id
    timeline_id      : $input.timeline_id
    expected_minutes : $expected_minutes
    scheduled_minutes: $scheduled_minutes
  }
}
