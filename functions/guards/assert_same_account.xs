// GOV-1 (US-GOV-1-03, standard S4) — Cross-account link guard.
//
// Call this before connecting two records (a job to a plan, a lens to a
// role, a task to a timeline). Stops a picker that offered an option
// from another account from quietly creating a cross-tenant link.
//
// GOV-1 standards: S4 (tenancy). See docs/data-standards.md.
function "guards/assert_same_account" {
  description = "Throws accessdenied unless both entities belong to the same (non-zero) account."

  input {
    int first_account_id
    int second_account_id
    text feature? filters=trim
    text step? filters=trim
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
      value = "assert_same_account"
    }

    conditional {
      if ($input.step != null && $input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    var $same {
      value = ($input.first_account_id != 0 && $input.first_account_id == $input.second_account_id)
    }

    conditional {
      if ($same == false) {
        function.run "ops/log_event" {
          input = {
            feature       : $log_feature
            step          : $log_step
            outcome       : "rejected"
            severity      : "warn"
            error_code    : "E-GOV-002"
            message       : "Cross-account link refused: the two records belong to different accounts."
            user_id       : $input.user_id
            account_id    : $input.first_account_id
            entity_type   : $input.entity_type
            entity_id     : $input.entity_id
            correlation_id: $input.correlation_id
          }
        } as $_logged
      }
    }

    precondition ($same) {
      error_type = "accessdenied"
      error = "Those two things belong to different accounts, so they can't be linked. (E-GOV-002)"
    }
  }

  response = {ok: true}
}
