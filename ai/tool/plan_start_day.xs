// COP-5 story 01 — the copilot starts a day's plan for one person in a plan of THIS business.
// The day is made by planner_ops/create_timeline - the same function the planner's own endpoint
// (538) is being moved onto - so the checks, the "already exists is not an error" answer, the
// race handling and the logging are exactly a person's.
// Narrower than a person, on purpose:
//   - only for one business: the chat's, or the one an outside person names (E-COP-045);
//   - only in a plan that belongs to that business (copilot/plan_in_business, E-COP-038);
//   - it never sets a status: a new day is always a draft, and nothing here publishes to live.
// A day that already exists is returned with created:false and is NOT changed - also when that
// day is already published (the tool changed nothing, so there is nothing to refuse).
tool plan_start_day {
  instructions = "Start a day's plan for one person in a plan of this business: give the plan (workspace_id), the person (agent_id, who must be in that plan) and the date (planned_date, YYYY-MM-DD). start_time is HH:MM in 24-hour time; leave it empty for the default 08:00. If that person already has a day on that date, you get the existing day back with created false and nothing is changed - check its status before adding to it, because you can only change draft days. A date outside the plan's dates is allowed and comes back with out_of_window true. A new day is always a draft: this never publishes anything to live and never sets a status."

  input {
    int workspace_id filters=min:1 {
      description = "The plan the day belongs to."
    }

    int agent_id filters=min:1 {
      description = "The person in that plan whose day this is."
    }

    text planned_date filters=trim {
      description = "YYYY-MM-DD."
    }

    text start_time? filters=trim {
      description = "HH:MM, 24-hour. Leave empty for the default 08:00."
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
    // Final review R1: the tool declares its action type, so the owner's level for it is really
    // applied (runs on its own / runs then tells you / waits for you). The summary is what the
    // owner reads; the payload is this tool's exact input, never the ticket.
    var $act_summary {
      value = "Start a day on " ~ $input.planned_date ~ " in plan #" ~ ($input.workspace_id|to_text)
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_start_day", kind: "write", act_type: "plan_draft", act_payload: {workspace_id: $input.workspace_id, agent_id: $input.agent_id, planned_date: $input.planned_date, start_time: $input.start_time}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_start_day"}
    } as $_plan_ok

    var $date_ok {
      value = ("/^[0-9]{4}-[01][0-9]-[0-3][0-9]$/"|regex_matches:$input.planned_date)
    }

    precondition ($date_ok == true) {
      error_type = "inputerror"
      error = "Give the date as YYYY-MM-DD."
    }

    // Final review R10: the shape alone let "2026-02-31" through, and the database quietly moved
    // it to 3 March. A real calendar date reads back as itself.
    var $date_back {
      value = ($input.planned_date|to_timestamp:"UTC")|format_timestamp:"Y-m-d":"UTC"
    }

    precondition ($date_back == $input.planned_date) {
      error_type = "inputerror"
      error = "That date does not exist. Give a real calendar date as YYYY-MM-DD."
    }

    // Is this plan part of this business? The one rule, in one place.
    function.run "copilot/plan_in_business" {
      input = {account_id: $caller_account, workspace_id: $input.workspace_id, architecture_id: $pin, user_id: $caller_user}
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

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    var $has_start_time {
      value = ($input.start_time != "")
    }

    function.run "planner_ops/create_timeline" {
      input = {
        actor         : $actor
        workspace_id  : $input.workspace_id
        agent_id      : $input.agent_id
        planned_date  : $input.planned_date
        start_time    : $input.start_time
        has_start_time: $has_start_time
        has_status    : false
        correlation_id: ""
      }
    } as $made

    var $day {
      value = $made|get:"timeline":null
    }

    var $day_id {
      value = ($day|get:"id":0) ?? 0
    }

    // Never answer "done" with no day: the shared function swallows a failed insert (the race
    // case) and re-reads, so a write that failed for another reason would come back empty.
    precondition ($day_id != 0) {
      error_type = "inputerror"
      error = "The day could not be started. Check the date and try again."
    }

    var $day_date {
      value = ($day|get:"planned_date":"") ?? ""
    }

    var $day_status {
      value = ($day|get:"status":"") ?? ""
    }

    var $was_created {
      value = (($made|get:"created":false) ?? false) == true
    }

    var $is_out_of_window {
      value = (($made|get:"out_of_window":false) ?? false) == true
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
    timeline_id  : $day_id
    created      : $was_created
    planned_date : $day_date
    status       : $day_status
    out_of_window: $is_out_of_window
  }
}
