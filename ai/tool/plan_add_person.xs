// COP-5 story 01 — the copilot adds someone to a plan: a named column (a person, or an AI agent)
// with a daily capacity. The row is written by planner_ops/create_agent — the same rule the
// planner's own endpoint (535) holds — so the name, capacity and colour rules and the events are
// exactly a person's.
// Narrower than a person, on purpose:
//   - only in a copilot conversation about one business, and the plan must be in it
//     (copilot/plan_in_business, the one rule);
//   - no colour and no model are passed: the colour is the next free palette colour, and a model
//     is an admin's choice;
//   - the new row never has a login (user_id 0). Linking a login is an admin's action, elsewhere.
// The tool always sends an explicit capacity (8 when its own input is 0) with the "was sent" flag
// true, so the function's capacity rule (more than 0, at most 24, E-PLN-009) always sees a number.
tool plan_add_person {
  instructions = "Add a named column to a plan (workspace_id): name (up to 60 characters, unique in the plan), kind (person or ai; leave empty for person) and daily_capacity_hours (more than 0 and at most 24; 0 or empty means the default of 8). Returns agent_id, name, kind and daily_capacity_hours. This only adds a name to the plan so work can be scheduled for them. It does NOT give that person a login and does NOT link one - only an admin links logins. Never add yourself (the copilot) to a plan. It never sets a colour or a model, and it never publishes anything to live."

  input {
    int workspace_id filters=min:1 {
      description = "The plan to add the person to."
    }

    text name filters=trim {
      description = "The name shown on the plan, up to 60 characters. Must not already be used in this plan."
    }

    text kind? filters=trim|lower {
      description = "person or ai. Leave empty for person."
    }

    decimal daily_capacity_hours? {
      description = "Hours of work per day, more than 0 and at most 24. 0 or empty = 8."
    }

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
      value = "Add " ~ $input.name ~ " to plan #" ~ ($input.workspace_id|to_text)
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "plan_add_person", kind: "write", act_type: "plan_draft", act_payload: {workspace_id: $input.workspace_id, name: $input.name, kind: $input.kind, daily_capacity_hours: $input.daily_capacity_hours}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_add_person"}
    } as $_plan_ok

    // Is this plan in this business? The one rule, in one place.
    function.run "copilot/plan_in_business" {
      input = {account_id: $caller_account, workspace_id: $input.workspace_id, architecture_id: $pin, user_id: $caller_user}
    } as $plan_check

    var $plan_reason {
      value = $plan_check.reason ?? ""
    }

    var $plan_ok {
      value = ($plan_check.ok == true)
    }

    precondition ($plan_reason != "not_found") {
      error_type = "notfound"
      error = "Plan not found"
    }

    precondition ($plan_ok == true) {
      error_type = "accessdenied"
      error = "That plan isn't part of this business. This conversation works on one business only. (E-COP-038)"
    }

    // kind: empty = person. Anything else but person / ai is refused here, in plain words.
    precondition ($input.kind == "" || $input.kind == "person" || $input.kind == "ai") {
      error_type = "inputerror"
      error = "kind has to be person or ai (leave it empty for person)."
    }

    var $kind {
      value = "person"
    }

    conditional {
      if ($input.kind == "ai") {
        var.update $kind {
          value = "ai"
        }
      }
    }

    // Always an explicit capacity: 8 when the tool's own input is 0 (= not given).
    var $capacity {
      value = 8
    }

    conditional {
      if ($input.daily_capacity_hours != 0) {
        var.update $capacity {
          value = $input.daily_capacity_hours
        }
      }
    }

    function.run "planner/resolve_actor" {
      input = {user_id: $caller_user}
    } as $actor

    function.run "planner_ops/create_agent" {
      input = {
        actor                   : $actor
        workspace_id            : $input.workspace_id
        name                    : $input.name
        kind                    : $kind
        color                   : ""
        has_color               : false
        daily_capacity_hours    : $capacity
        has_daily_capacity_hours: true
        model_id                : 0
        has_model_id            : false
        correlation_id          : ""
      }
    } as $created

    var $agent_row {
      value = $created.agent
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
    agent_id            : $agent_row.id
    name                : $agent_row.name
    kind                : $agent_row.kind
    daily_capacity_hours: $agent_row.daily_capacity_hours
  }
}
