// COP-4 story 06 — the copilot saves a short fact or preference the owner told it, for the
// conversation's business only. Never secrets, logins or customer details. The owner can see,
// edit and remove every note in "What the copilot knows".
tool save_note {
  instructions = "Save a short fact or preference the owner told you about THIS business (e.g. 'we never book on Sundays'), so you follow it in later conversations. One line. Never store passwords, logins, card numbers or customer contact details."

  input {
    text note filters=trim

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
    var $act_note_head {
      value = $input.note|substr:0:160
    }

    var $act_summary {
      value = "Save a note: " ~ $act_note_head
    }

    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "save_note", kind: "write", act_type: "note_internal", act_payload: {note: $input.note}, act_summary: $act_summary, act_approval_id: $input.approval_id}
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

    // COP-4: these tools work inside ONE business — the conversation's pinned business.
    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    precondition ($pin != 0) {
      error_type = "inputerror"
      error = "This only works in a copilot conversation about one business. (E-COP-045)"
    }

    var $note_len {
      value = $input.note|strlen
    }

    precondition ($input.note != "" && $note_len <= 500) {
      error_type = "inputerror"
      error = "A note is one short line (up to 500 characters)."
    }

    db.add copilot_note {
      data = {
        account_id             : $cop1_gate.account_id
        journey_architecture_id: $pin
        note                   : $input.note
        created_by_user_id     : $cop1_gate.user_id
        updated_at             : "now"
      }
    } as $saved
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

  response = {note_id: $saved.id, note: $saved.note}
}
