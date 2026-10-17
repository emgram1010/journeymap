// GOV-1 (US-GOV-1-03, standard S9) — Archive guard.
//
// Call this before writing to anything archivable (a plan instance, a
// plan template, a role, a map). Archiving is how this product deletes
// things that have history, so "archived" must block writes everywhere,
// not just on the screen that archived it.
//
// GOV-1 standards: S9 (archive instead of delete). See docs/data-standards.md.
function "guards/assert_not_archived" {
  description = "Throws unless the entity is still active (not archived)."

  input {
    bool is_archived
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
      value = "assert_not_archived"
    }

    conditional {
      if ($input.step != null && $input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    var $active {
      value = ($input.is_archived != true)
    }

    conditional {
      if ($active == false) {
        function.run "ops/log_event" {
          input = {
            feature       : $log_feature
            step          : $log_step
            outcome       : "rejected"
            severity      : "info"
            error_code    : "E-GOV-004"
            message       : "Write refused: this record is archived."
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : $input.entity_type
            entity_id     : $input.entity_id
            correlation_id: $input.correlation_id
          }
        } as $_logged
      }
    }

    precondition ($active) {
      error_type = "inputerror"
      error = "This has been archived, so it can't be changed. (E-GOV-004)"
    }
  }

  response = {ok: true}
}
