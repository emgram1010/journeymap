// COP-5 story 01 (handoff 4-B) — the copilot sets or replaces a job's one time window in a plan of
// THIS business. The window is saved by planner_ops/set_time_window - a copy of live endpoint
// 613's rule - so the checks (E-TW-001..006), the write, the race answer and the logging are
// exactly a person's.
// Narrower than a person, on purpose:
//   - only for one business: the chat's, or the one an outside person names (E-COP-045);
//   - only for a job whose plan belongs to that business (copilot/plan_in_business, E-COP-038);
//   - only while none of the job's work is on a LIVE day: a person may change it and re-publish,
//     the copilot may not (E-COP-055) - it tells the owner instead;
//   - a date must be a real calendar date (read back as itself), not just the right shape.
// A job that does not exist answers like 613 does (E-TW-004). Nothing here publishes to live.
tool plan_set_time_window {
  instructions = "Set or replace the one time window of a job (work_item_id) in a plan of this business: when the work may happen. start_date and end_date are YYYY-MM-DD; start_time and end_time are HH:MM in 24-hour time. The window must end after it starts and overlap the plan's dates at least partly. note is optional, 200 characters at most. If any of the job's work is already on a live day, this is refused: tell the owner what you would change instead. A cancelled job is refused. This never publishes anything to live."

  input {
    int work_item_id filters=min:1 {
      description = "The job whose time window to set."
    }

    text start_date filters=trim {
      description = "YYYY-MM-DD."
    }

    text start_time filters=trim {
      description = "HH:MM, 24-hour."
    }

    text end_date filters=trim {
      description = "YYYY-MM-DD."
    }

    text end_time filters=trim {
      description = "HH:MM, 24-hour."
    }

    text note? filters=trim {
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
      value = "Set the time window of job #" ~ ($input.work_item_id|to_text) ~ " to " ~ $input.start_date ~ " " ~ $input.start_time ~ " - " ~ $input.end_date ~ " " ~ $input.end_time
    }

    // COP-5 story 01 (2026-11-16): a change to a day that is already live is its own action type,
    // plan_live_change, which always waits for the owner (locked). copilot/live_target answers only
    // for the caller's own account, so it reveals nothing about anyone else's days.
    function.run "copilot/live_target" {
      input = {ticket: $input.ticket, timeline_id: 0, planner_task_id: 0, work_task_id: 0, work_item_id: $input.work_item_id}
    } as $live_target

    var $act_type {
      value = ((($live_target.live ?? false) == true) ? "plan_live_change" : "plan_draft")
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_set_time_window", kind: "write", act_type: $act_type, act_payload: {work_item_id: $input.work_item_id, start_date: $input.start_date, start_time: $input.start_time, end_date: $input.end_date, end_time: $input.end_time, note: $input.note}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_set_time_window"}
    } as $_plan_ok

    var $start_ok {
      value = ("/^[0-9]{4}-[01][0-9]-[0-3][0-9]$/"|regex_matches:$input.start_date)
    }

    var $end_ok {
      value = ("/^[0-9]{4}-[01][0-9]-[0-3][0-9]$/"|regex_matches:$input.end_date)
    }

    precondition ($start_ok == true && $end_ok == true) {
      error_type = "inputerror"
      error = "Give the date as YYYY-MM-DD."
    }

    // Final review R10: the shape alone lets "2026-02-31" through. A real date reads back as itself.
    var $start_back {
      value = ($input.start_date|to_timestamp:"UTC")|format_timestamp:"Y-m-d":"UTC"
    }

    var $end_back {
      value = ($input.end_date|to_timestamp:"UTC")|format_timestamp:"Y-m-d":"UTC"
    }

    precondition ($start_back == $input.start_date && $end_back == $input.end_date) {
      error_type = "inputerror"
      error = "That date does not exist. Give a real calendar date as YYYY-MM-DD."
    }

    // The job -> its plan.
    db.query work_item {
      where = $db.work_item.id == $input.work_item_id
      return = {type: "single"}
      output = ["id", "workspace_id"]
    } as $job

    var $job_id {
      value = ($job|get:"id":0) ?? 0
    }

    var $job_workspace {
      value = ($job|get:"workspace_id":0) ?? 0
    }

    precondition ($job_id != 0 && $job_workspace != 0) {
      error_type = "notfound"
      error = "That job isn't available any more. (E-TW-004)"
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

    // The copilot changes draft work only: if any of this job is on a live day, the owner decides.
    function.run "jobs/time_window_live_refs" {
      input = {work_item_id: $input.work_item_id}
    } as $live_now

    var $is_live {
      value = (($live_now|get:"live":false) ?? false) == true
    }

    precondition ($is_live == false || $act_type == "plan_live_change") {
      error_type = "accessdenied"
      error = "That day is already live. Only the owner changes a live day - tell them what you would change. (E-COP-055)"
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    function.run "planner_ops/set_time_window" {
      input = {
        actor         : $actor
        work_item_id  : $input.work_item_id
        start_date    : $input.start_date
        start_time    : $input.start_time
        end_date      : $input.end_date
        end_time      : $input.end_time
        note          : $input.note
        correlation_id: ""
      }
    } as $saved

    var $window {
      value = $saved|get:"time_window":null
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
    work_item_id: $input.work_item_id
    time_window : $window
    created     : $was_created
  }
}
