// GOV-1 (US-GOV-1-03, standard S4) — Ownership guard.
//
// Call this before reading or writing anything that belongs to an
// account. The CALLER does the db read (it already has the row) and
// passes the two account ids in; the guard stays generic and adds no
// extra query.
//
// Every refusal logs a `rejected` event through ops/log_event before it
// throws, so a denied action shows up on the Health page exactly like a
// broken one does.
//
// GOV-1 standards: S4 (tenancy). See docs/data-standards.md.
function "guards/assert_owns" {
  description = "Throws accessdenied unless the entity's account matches the caller's account."

  input {
    int entity_account_id {
      description = "account_id on the row being touched."
    }

    int caller_account_id {
      description = "account_id of the authenticated caller."
    }

    text feature? filters=trim {
      description = "Epic code of the caller, for the logged event (e.g. 'JOB-1')."
    }

    text step? filters=trim {
      description = "Step within that feature (e.g. 'add_job')."
    }

    text entity_type? filters=trim
    int entity_id?
    int user_id?
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
      value = "assert_owns"
    }

    conditional {
      if ($input.step != null && $input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    var $owns {
      value = ($input.caller_account_id != 0 && $input.entity_account_id == $input.caller_account_id)
      description = "account_id 0 means 'no account', which can never own anything."
    }

    conditional {
      if ($owns == false) {
        function.run "ops/log_event" {
          input = {
            feature       : $log_feature
            step          : $log_step
            outcome       : "rejected"
            severity      : "warn"
            error_code    : "E-GOV-001"
            message       : "Ownership check failed: the row belongs to a different account."
            user_id       : $input.user_id
            account_id    : $input.caller_account_id
            entity_type   : $input.entity_type
            entity_id     : $input.entity_id
            correlation_id: $input.correlation_id
          }
        } as $_logged
      }
    }

    precondition ($owns) {
      error_type = "accessdenied"
      error = "You don't have access to this. (E-GOV-001)"
    }
  }

  response = {ok: true}
}
