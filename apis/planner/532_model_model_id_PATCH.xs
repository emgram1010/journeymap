// PLN-4 (US-PLN-4-04) — Change a model's name or prices. Admin only.
//
// `model_key` is IMMUTABLE. Sending a different one is rejected rather
// than ignored, so a client that thinks it renamed a key finds out it
// did not. Sending the SAME key is fine — a UI that echoes the whole
// object back should not be punished for it.
//
// The key matters because "reset to defaults" (US-PLN-4-06) matches
// seeded models by key. Let the key change and a seeded model quietly
// becomes unrecognisable to reset.
//
// Editing a seeded (non-custom) model IS allowed — US-PLN-4-04 is
// explicit about this, and it matches the UI, where every price field
// is editable. Prices drift; the catalogue has to be able to follow.
query "model/{model_id}" verb=PATCH {
  api_group = "planner"
  auth = "user"

  input {
    int model_id filters=min:1
    text model_key? filters=trim|lower
    text label? filters=trim
    decimal input_per_1m?
    decimal output_per_1m?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_admin" {
      input = {role: $actor.role}
    }

    function.run "planner/assert_model" {
      input = {account_id: $actor.account_id, model_id: $input.model_id}
    } as $guard

    var $existing {
      value = $guard.model
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $next_label {
      value = $existing.label
    }

    conditional {
      if ($raw_input|has:"label") {
        var.update $next_label {
          value = $input.label
        }
      }
    }

    var $next_input {
      value = $existing.input_per_1m
    }

    conditional {
      if ($raw_input|has:"input_per_1m") {
        var.update $next_input {
          value = $input.input_per_1m
        }
      }
    }

    var $next_output {
      value = $existing.output_per_1m
    }

    conditional {
      if ($raw_input|has:"output_per_1m") {
        var.update $next_output {
          value = $input.output_per_1m
        }
      }
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if (($raw_input|has:"model_key") && $input.model_key != $existing.model_key) {
        var.update $reject_code {
          value = "E-PLN-005"
        }

        var.update $reject_msg {
          value = "A model's id can't be changed after it's created. Add a new model instead. (E-PLN-005)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_label == null || $next_label == "")) {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Give the model a name. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_input < 0 || $next_output < 0)) {
        var.update $reject_code {
          value = "E-PLN-003"
        }

        var.update $reject_msg {
          value = "This has to be zero or more. (E-PLN-003)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-4"
            step          : "update_model"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_model"
            entity_id     : $input.model_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Model update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.patch planner_model {
      field_name = "id"
      field_value = $input.model_id
      data = {
        label        : $next_label
        input_per_1m : $next_input
        output_per_1m: $next_output
        updated_at   : "now"
      }
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-4"
        step          : "update_model"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_model"
        entity_id     : $input.model_id
        correlation_id: $input.correlation_id
        message       : "Model prices updated."
      }
    }
  }

  response = {model: $updated}
}
