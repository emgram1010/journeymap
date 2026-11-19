// COP-5 story 01 — the copilot creates a new, empty plan in the caller's account. The rule is
// planner_ops/create_workspace - the same function endpoint 523 (POST /workspace) is being moved
// onto - so names, dates, error codes and the activity log are exactly a person's.
// Only in a copilot conversation about one business. There is no existing plan to check: the new
// plan is created BY the caller, and that is what lets the other plan tools touch it while it
// still accepts no map (copilot/plan_in_business: an empty plan is allowed only for its creator).
// Token rates are not offered here: both has_ flags are false, so the defaults apply.
tool plan_create {
  instructions = "Create a new, empty plan. name is required (80 characters at most, and not a name another plan in this account already has). planning_window_start and planning_window_end are dates as YYYY-MM-DD; leave either empty to keep the default (start = today, end = 13 days after today); the end cannot be before the start. Returns workspace_id - use it with plan_accept_map to say which maps the plan works from. This only creates a draft plan: it never adds maps, people, days or jobs, and it never publishes anything to live."

  input {
    text name filters=trim

    text planning_window_start? filters=trim {
      description = "YYYY-MM-DD. Leave empty for the default (today)."
    }

    text planning_window_end? filters=trim {
      description = "YYYY-MM-DD. Leave empty for the default (13 days after today)."
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
      value = "Create a new plan: " ~ $input.name
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_create", kind: "write", act_type: "plan_draft", act_payload: {name: $input.name, planning_window_start: $input.planning_window_start, planning_window_end: $input.planning_window_end}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_create"}
    } as $_plan_ok

    // The endpoint's date inputs are typed, so a malformed date never reached its rule. The
    // function takes text, so the shape is checked here before it is handed over.
    var $start_ok {
      value = ($input.planning_window_start == "") || ("/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/"|regex_matches:$input.planning_window_start)
    }

    var $end_ok {
      value = ($input.planning_window_end == "") || ("/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/"|regex_matches:$input.planning_window_end)
    }

    precondition ($start_ok && $end_ok) {
      error_type = "inputerror"
      error = "Give each date as YYYY-MM-DD, or leave it empty for the default."
    }

    // Final review R10: a real calendar date reads back as itself ("2026-02-31" does not).
    var $start_probe {
      value = (($input.planning_window_start != "") ? $input.planning_window_start : "2000-01-01")
    }

    var $end_probe {
      value = (($input.planning_window_end != "") ? $input.planning_window_end : "2000-01-01")
    }

    var $start_back {
      value = ($start_probe|to_timestamp:"UTC")|format_timestamp:"Y-m-d":"UTC"
    }

    var $end_back {
      value = ($end_probe|to_timestamp:"UTC")|format_timestamp:"Y-m-d":"UTC"
    }

    precondition ($start_back == $start_probe && $end_back == $end_probe) {
      error_type = "inputerror"
      error = "That date does not exist. Give a real calendar date as YYYY-MM-DD."
    }

    var $has_start {
      value = ($input.planning_window_start != "")
    }

    var $has_end {
      value = ($input.planning_window_end != "")
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    function.run "planner_ops/create_workspace" {
      input = {
        actor                       : $actor
        name                        : $input.name
        planning_window_start       : $input.planning_window_start
        has_planning_window_start   : $has_start
        planning_window_end         : $input.planning_window_end
        has_planning_window_end     : $has_end
        input_tokens_per_minute     : 0
        has_input_tokens_per_minute : false
        output_tokens_per_minute    : 0
        has_output_tokens_per_minute: false
        correlation_id              : ""
      }
    } as $created

    var $plan {
      value = $created.workspace
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
    workspace_id         : ($plan|get:"id":0)
    name                 : ($plan|get:"name":"")
    planning_window_start: ($plan|get:"planning_window_start":"")
    planning_window_end  : ($plan|get:"planning_window_end":"")
  }
}
