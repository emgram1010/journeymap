// COP-4 story 01 — the copilot records a goal the owner stated, for the conversation's business, as
// "proposed" (only the owner confirms it). It must repeat the goal back in the owner's terms; the
// target and date are stored exactly as stated, never invented.
tool record_goal {
  instructions = "Record a goal the owner just stated for this business. Repeat it back in one line as goal_text; copy target and target_date exactly as the owner said them (leave empty if not given - never invent). It is saved as 'proposed' until the owner confirms it."

  input {
    text goal_text filters=trim
    text target? filters=trim
    text target_date? filters=trim

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "record_goal", kind: "write"}
    } as $cop1_gate

    // COP-4: these tools work inside ONE business — the conversation's pinned business.
    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    precondition ($pin != 0) {
      error_type = "inputerror"
      error = "This only works in a copilot conversation about one business. (E-COP-045)"
    }

    precondition ($input.goal_text != "") {
      error_type = "inputerror"
      error = "goal_text is required"
    }

    db.add copilot_goal {
      data = {
        account_id             : $cop1_gate.account_id
        journey_architecture_id: $pin
        goal_text              : $input.goal_text
        target                 : $input.target
        target_date            : $input.target_date
        status                 : "proposed"
        created_by_user_id     : $cop1_gate.user_id
        updated_at             : "now"
      }
    } as $goal

    function.run "ops/log_event" {
      input = {
        feature    : "COP-4"
        step       : "goal_recorded"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "The copilot recorded a goal for a business."
        user_id    : $cop1_gate.user_id
        account_id : $cop1_gate.account_id
        entity_type: "copilot_goal"
        entity_id  : $goal.id
        metadata   : {journey_architecture_id: $pin}
      }
    } as $_logged
  }

  response = {goal_id: $goal.id, status: "proposed", goal_text: $goal.goal_text}
}
