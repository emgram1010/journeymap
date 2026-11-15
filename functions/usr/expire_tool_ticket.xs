// COP-7 story 03 - end a run ticket early: its expiry is set to now, so usr/tool_caller refuses it from the next call on. Used when a research run finishes. An unknown or empty ticket does nothing. The ticket is never logged or returned.
function "usr/expire_tool_ticket" {
  input {
    text ticket? filters=trim
  }

  stack {
    var $ended {
      value = false
    }

    var $has_ticket {
      value = ($input.ticket != "")
    }

    db.query tool_run_ticket {
      where = $db.tool_run_ticket.ticket == $input.ticket && $has_ticket == true
      return = {type: "single"}
      output = ["id"]
    } as $row

    var $row_id {
      value = $row|get:"id":0
    }

    var $now_ms {
      value = now|to_int
    }

    conditional {
      if ($row_id != 0) {
        db.patch tool_run_ticket {
          field_name = "id"
          field_value = $row_id
          data = {expires_at: $now_ms}
        } as $_patched

        var.update $ended {
          value = true
        }
      }
    }
  }

  response = {ended: $ended}
}
