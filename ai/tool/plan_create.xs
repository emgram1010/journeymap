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

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "plan_create", kind: "write"}
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

  response = {
    workspace_id         : ($plan|get:"id":0)
    name                 : ($plan|get:"name":"")
    planning_window_start: ($plan|get:"planning_window_start":"")
    planning_window_end  : ($plan|get:"planning_window_end":"")
  }
}
