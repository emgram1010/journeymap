// COP-5 story 01 — the copilot tells a plan to accept one map (so jobs of that kind of work can
// be planned in it). The rule is planner_ops/accept_maps - the same function endpoint 570
// (POST /workspace/{workspace_id}/map) is being moved onto - so the checks, error codes and the
// activity log are exactly a person's. Append-only and idempotent: a map the plan already accepts
// is skipped, not refused.
// Narrower than a person, on purpose:
//   - only in a copilot conversation about one business;
//   - the map must be in the caller's account and in that business (journey/tool_gate);
//   - the plan must be in the caller's account and in that business (copilot/plan_in_business:
//     every map it already accepts is in this business, or it is empty and the caller made it).
// The server refuses a map with no published version (E-PLAN-004). The copilot never publishes one.
tool plan_accept_map {
  instructions = "Make a plan accept one map, so work from that map can be planned in it. workspace_id is the plan (from plan_create or a plan you were given); journey_map_id is ONE map per call - call again for each further map. The map must be in this business and must already have a published version: a person publishes versions, you never do, and the server refuses a map that is not published yet - if that happens, tell the owner which map needs publishing. Accepting a map the plan already accepts is harmless. This never removes a map, never creates jobs or days, and never publishes anything to live."

  input {
    int workspace_id filters=min:1
    int journey_map_id filters=min:1

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
      value = "Let plan #" ~ ($input.workspace_id|to_text) ~ " plan work from map #" ~ ($input.journey_map_id|to_text)
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_accept_map", kind: "write", act_type: "plan_draft", act_payload: {workspace_id: $input.workspace_id, journey_map_id: $input.journey_map_id}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_accept_map"}
    } as $_plan_ok

    // The one rule for "is this plan in this business".
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

    var $one_map {
      value = []
    }

    array.push $one_map {
      value = $input.journey_map_id
    }

    function.run "planner_ops/accept_maps" {
      input = {
        actor         : $actor
        workspace_id  : $input.workspace_id
        map_ids       : $one_map
        correlation_id: ""
      }
    } as $accepted
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
    workspace_id  : $input.workspace_id
    journey_map_id: $input.journey_map_id
    accepted      : true
  }
}
