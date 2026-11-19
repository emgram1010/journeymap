// COP-9 story 01 — the copilot records which of its skills it used (and which exception fired, if
// any) in this chat or scheduled run. Without this nothing about a skill can be measured: trial
// results and Health's "runs with no skill used" both count copilot_skill_use. Bookkeeping only:
// passes the gate (ticket, switched on, daily cap, audit row) but declares no action type, so it
// never waits for approval. The skill must be this account's and not retired; an exception must be
// one that branches that skill.
tool record_skill_used {
  instructions = "Record which skill from the Playbook you are following for this task (once per task), and the exception's number if one applied. Use the numbers shown in your context."

  input {
    int skill_id {
      description = "The skill's number from the Playbook."
    }

    int exception_skill_id? {
      description = "The exception's number, if one applied. Otherwise 0."
    }

    int conversation_id? {
      description = "The conversation_id from Tool Logging in your context, or 0 in a scheduled run."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "record_skill_used", kind: "write"}
    } as $cop1_gate

    var $account_id {
      value = $cop1_gate.account_id ?? 0
    }

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id == $input.skill_id && $db.copilot_skill.account_id == $account_id && $account_id != 0 && $db.copilot_skill.status != "retired"
      return = {type: "single"}
    } as $skill

    var $skill_found {
      value = $skill|get:"id":0
    }

    precondition ($skill_found != 0) {
      error_type = "inputerror"
      error = "That skill isn't in the Playbook (or it is retired). Use a number shown in your context."
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id == $input.exception_skill_id && $input.exception_skill_id != 0 && $db.copilot_skill.account_id == $account_id && $db.copilot_skill.kind == "exception" && $db.copilot_skill.parent_skill_id == $input.skill_id && $db.copilot_skill.status != "retired"
      return = {type: "single"}
    } as $exc

    var $exc_found {
      value = $exc|get:"id":0
    }

    precondition ($input.exception_skill_id == 0 || $exc_found != 0) {
      error_type = "inputerror"
      error = "That exception doesn't belong to this skill. Record the skill alone, or use the exception shown under it."
    }

    var $was_trial {
      value = (($skill|get:"status":"") == "trial" || ($exc|get:"status":"") == "trial")
    }

    function.run "copilot/skill_trace" {
      input = {ticket: $input.ticket, account_id: $account_id, conversation_id: $input.conversation_id}
    } as $trace

    db.add copilot_skill_use {
      data = {
        account_id             : $account_id
        skill_id               : $skill_found
        exception_skill_id     : $exc_found
        journey_architecture_id: $pin
        copilot_run_id         : $trace.copilot_run_id
        conversation_id        : $trace.conversation_id
        skill_version_no       : ($skill|get:"version_no":0)
        was_trial              : $was_trial
      }
    } as $use
  }

  response = {recorded: true, use_id: $use.id, was_trial: $was_trial}
}
