// GOV-1 (US-GOV-1-03, standard S9) — State guard.
//
// Call this before an action that only makes sense in certain states:
// editing a draft timeline, cancelling an open job, publishing a map
// that is still a draft. Keeps "what state must this be in" out of
// every endpoint's own inline logic.
//
// `allowed_states` is a comma-separated list, e.g. "draft,needs_info".
// A list rather than an array input because an optional array input
// arrives empty-but-not-null in XanoScript, which makes "was this
// provided" ambiguous (see CLAUDE.md, verified constraints).
//
// GOV-1 standards: S9 (explicit state rules). See docs/data-standards.md.
function "guards/assert_state" {
  description = "Throws unless the entity's current state is one of the allowed states."

  input {
    text current_state filters=trim
    text allowed_states filters=trim {
      description = "Comma-separated list of states this action permits, e.g. \"draft,needs_info\"."
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
      value = "assert_state"
    }

    conditional {
      if ($input.step != null && $input.step != "") {
        var.update $log_step {
          value = $input.step
        }
      }
    }

    var $allowed_list {
      value = $input.allowed_states|split:","
    }

    var $is_allowed {
      value = false
    }

    foreach ($allowed_list) {
      each as $allowed {
        conditional {
          if (($allowed|trim) == $input.current_state) {
            var.update $is_allowed {
              value = true
            }
          }
        }
      }
    }

    conditional {
      if ($is_allowed == false) {
        function.run "ops/log_event" {
          input = {
            feature       : $log_feature
            step          : $log_step
            outcome       : "rejected"
            severity      : "info"
            error_code    : "E-GOV-003"
            message       : "State check failed: found \"" ~ $input.current_state ~ "\", needed one of \"" ~ $input.allowed_states ~ "\"."
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : $input.entity_type
            entity_id     : $input.entity_id
            correlation_id: $input.correlation_id
          }
        } as $_logged
      }
    }

    precondition ($is_allowed) {
      error_type = "inputerror"
      error = "This can't be done while it's in its current state. (E-GOV-003)"
    }
  }

  response = {ok: true}
}
