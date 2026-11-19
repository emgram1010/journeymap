// COP-13 part B — the copilot asks to re-do the current request on the stronger, dearer model
// (Opus 5.5; about twice the price per word of the standard Sonnet 5.5). Order matters:
//   1. who is asking (usr/tool_caller) and a one-line reason (1-200 characters);
//   2. the daily cap: at most 5 step-up requests per account in 24 hours, counted from event_log
//      (copilot.step_up.requested). Over it: refused with E-COP-094 BEFORE anything waits for the owner.
//      Re-sending an approved item (approval_id) is not a new request: not counted, never capped;
//   3. the approval gate (journey/tool_gate, action type step_up_model, default "waits for you"):
//      waiting = E-COP-020, nothing changes; declined or expired = the gate's own refusal;
//   4. allowed (own / tell, or an approved item re-sent with approval_id): logs copilot.step_up.granted
//      against the conversation. The chat endpoint (643) sees that event for this turn and re-runs the
//      same turn on the strong copy ("Emgram Copilot Strong"), which has no request_step_up tool.
// Every outcome is logged; the reason text never contains customer data (the copilot is told one line).
tool request_step_up {
  instructions = "Ask to re-do the CURRENT request on the stronger, dearer model. Only for a task that is clearly too hard on the standard model (long reasoning over many steps, many maps at once, or you tried and it went wrong) - never for everyday work. reason: ONE plain line saying why (no customer names or details). conversation_id: from Tool Logging. If it says the request is waiting for the owner, tell them and carry on as well as you can. If it is refused (declined, expired, or the daily limit), carry on with the standard model and say so. If it is allowed, finish your answer briefly: the same request is re-done on the stronger model straight after."

  input {
    text reason? filters=trim {
      description = "One line: why this task needs the stronger model."
    }

    int conversation_id? {
      description = "The conversation_id from Tool Logging in your context."
    }

    int approval_id? {
      description = "Leave 0. Only when the owner approved a waiting step-up: its item number, sent with exactly the approved input."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. Pass it exactly as given."
    }
  }

  stack {
    var $reason_len {
      value = $input.reason|strlen
    }

    precondition (($reason_len < 1 || $reason_len > 200) == false) {
      error_type = "inputerror"
      error = "Say in one line (up to 200 characters) why this task needs the stronger model."
    }

    function.run "usr/tool_caller" {
      input = {ticket: $input.ticket}
    } as $caller

    var $account_id {
      value = $caller.account_id ?? 0
    }

    var $cutoff {
      value = (now|to_int) - 86400000
    }

    db.query event_log {
      where = $db.event_log.account_id == $account_id && $account_id != 0 && $db.event_log.step == "copilot.step_up.requested" && $db.event_log.created_at >= $cutoff
      return = {type: "count"}
    } as $today

    var $cap {
      value = 5
    }

    conditional {
      if ($today >= $cap && $input.approval_id == 0) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-13"
            step       : "copilot.step_up.capped"
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-COP-094"
            message    : "A step-up to the stronger model was refused: the daily limit is reached."
            user_id    : $caller.user_id
            account_id : $account_id
            entity_type: "agent_conversation"
            entity_id  : $input.conversation_id
            metadata   : {requests_last_24h: $today, cap: $cap}
          }
        } as $_capped_logged
      }
    }

    precondition ($today < $cap || $input.approval_id != 0) {
      error_type = "inputerror"
      error = "The daily limit for using the stronger model is reached, so I'll carry on with the standard one. (E-COP-094)"
    }

    conditional {
      if ($input.approval_id == 0) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-13"
            step       : "copilot.step_up.requested"
            outcome    : "success"
            severity   : "info"
            error_code : ""
            message    : "The copilot asked to use the stronger model."
            user_id    : $caller.user_id
            account_id : $account_id
            entity_type: "agent_conversation"
            entity_id  : $input.conversation_id
            metadata   : {reason: $input.reason}
          }
        } as $_requested_logged
      }
    }

    var $act_summary {
      value = "Use the stronger model (Opus 5.5, about twice the price per word of the standard Sonnet 5.5) to re-do this request: " ~ $input.reason
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "request_step_up", kind: "write", act_type: "step_up_model", act_payload: {conversation_id: $input.conversation_id, reason: $input.reason}, act_summary: $act_summary, act_approval_id: $input.approval_id}
    } as $cop1_gate

    var $act_action_id {
      value = $cop1_gate.action_id ?? 0
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-13"
        step       : "copilot.step_up.granted"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "The copilot may use the stronger model for this request."
        user_id    : $caller.user_id
        account_id : $account_id
        entity_type: "agent_conversation"
        entity_id  : $input.conversation_id
        metadata   : {level: $cop1_gate.action_level, approval_id: $input.approval_id}
      }
    } as $_granted_logged

    function.run "copilot/action_close" {
      input = {action_id: $act_action_id, account_id: $account_id, error: null}
    } as $_act_closed
  }

  response = {allowed: true, note: "Finish your answer briefly; the same request is re-done on the stronger model straight after."}
}
