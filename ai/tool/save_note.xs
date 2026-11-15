// COP-4 story 06 — the copilot saves a short fact or preference the owner told it, for the
// conversation's business only. Never secrets, logins or customer details. The owner can see,
// edit and remove every note in "What the copilot knows".
tool save_note {
  instructions = "Save a short fact or preference the owner told you about THIS business (e.g. 'we never book on Sundays'), so you follow it in later conversations. One line. Never store passwords, logins, card numbers or customer contact details."

  input {
    text note filters=trim

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "save_note", kind: "write"}
    } as $cop1_gate

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

  response = {note_id: $saved.id, note: $saved.note}
}
