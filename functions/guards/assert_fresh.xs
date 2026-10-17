// GOV-1 (US-GOV-1-03, standard S12) — Stale-write guard.
//
// Call this before an edit that could silently overwrite someone else's
// change: the caller sends the `updated_at` it last saw, and this
// refuses the write if the row has moved on since.
//
// NOT WIRED UP YET. S12 / US-GOV-1-08 is deferred while there is a
// single planner, so no endpoint calls this today. It is built now so
// that turning concurrency control on later is a one-line change at
// each call site rather than a new design. Leave it unused until then.
//
// GOV-1 standards: S12 (concurrent edits detected). See docs/data-standards.md.
function "guards/assert_fresh" {
  description = "Throws unless the caller's expected updated_at matches the row's current updated_at."

  input {
    text expected_updated_at filters=trim {
      description = "The updated_at the caller last saw. Compared as text so any timestamp format round-trips unchanged."
    }

    text current_updated_at filters=trim {
      description = "The row's updated_at right now."
    }

    text feature? filters=trim
    text step? filters=trim
    text entity_type? filters=trim
    int entity_id?
    int user_id?
    int account_id?
    text correlation_id? filters=trim
  }

  stack {
    var $log_feature {
      value = "GOV-1"
    }

    conditional {
      if ($input.feature != null && $input.feature != "") {
        var.update $log_feature {
          value = $input.feature
        }
      }
    }

    var $log_step {
      value = "assert_fresh"
    }

    conditional {
      if ($input.step != null && $input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    var $fresh {
      value = ($input.expected_updated_at == $input.current_updated_at)
    }

    conditional {
      if ($fresh == false) {
        function.run "ops/log_event" {
          input = {
            feature       : $log_feature
            step          : $log_step
            outcome       : "rejected"
            severity      : "info"
            error_code    : "E-GOV-005"
            message       : "Stale write refused: the row changed after this screen loaded it."
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : $input.entity_type
            entity_id     : $input.entity_id
            correlation_id: $input.correlation_id
          }
        } as $_logged
      }
    }

    precondition ($fresh) {
      error_type = "inputerror"
      error = "Someone else changed this. Reload to see the latest. (E-GOV-005)"
    }
  }

  response = {ok: true}
}
