// COP-9 stories 01/04 — which scheduled run or chat a skill tool call came from, so a version
// ("the run it came from") and a "skill used" row can point back to it. The run comes from the
// ticket itself (copilot_run_ticket, written by run_for_business - the same lookup the gate uses
// for tool_call_run); a chat's conversation id is accepted only if it is a copilot chat in this
// account. Never throws: anything unknown is 0. Ids only - the ticket text is never returned.
function "copilot/skill_trace" {
  input {
    text ticket? filters=trim
    int account_id?
    int conversation_id?
  }

  stack {
    db.query tool_run_ticket {
      where = $db.tool_run_ticket.ticket == $input.ticket && $input.ticket != ""
      return = {type: "single"}
      output = ["id"]
    } as $t

    var $ticket_id {
      value = $t|get:"id":0
    }

    db.query copilot_run_ticket {
      where = $db.copilot_run_ticket.tool_run_ticket_id == $ticket_id && $ticket_id != 0
      return = {type: "single"}
      output = ["id", "copilot_run_id"]
    } as $rt

    var $run_id {
      value = $rt|get:"copilot_run_id":0
    }

    db.query copilot_conversation {
      where = $db.copilot_conversation.agent_conversation_id == $input.conversation_id && $input.conversation_id != 0 && $db.copilot_conversation.account_id == $input.account_id
      return = {type: "single"}
      output = ["id", "agent_conversation_id"]
    } as $cc

    var $conv_id {
      value = $cc|get:"agent_conversation_id":0
    }
  }

  response = {copilot_run_id: $run_id, conversation_id: $conv_id}
}
