// PLN-4 (US-PLN-4-03) — Add a custom model to the account's catalogue.
// Admin only.
//
// `is_custom` is set by the server, never accepted from input: it is
// what tells "reset to defaults" which rows it may recreate and which
// it must leave alone (US-PLN-4-06). A client that could set it could
// make a custom model vanish on the next reset. Confirmed live:
// posting `is_custom: false` still produced a custom row.
//
// `model_key` is a slug and is immutable once created (US-PLN-4-04) —
// agents reference models by id, but the key is what the seed/reset
// logic matches on, so letting it change would break reset-defaults.
// The `lower` filter makes ids case-insensitive, so "GPT-X" and "gpt-x"
// collide as the same id rather than becoming two rows.
query "model" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    text model_key filters=trim|lower
    text label filters=trim
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

    db.query planner_model {
      where = $db.planner_model.account_id == $actor.account_id && $db.planner_model.model_key == $input.model_key
      return = {type: "count"}
    } as $key_clash

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($input.model_key == null || $input.model_key == "") {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Give the model an id. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($input.label == null || $input.label == "")) {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Give the model a name. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ("/^[a-z0-9][a-z0-9._-]*$/"|regex_matches:$input.model_key) == false) {
        var.update $reject_code {
          value = "E-VAL-004"
        }

        var.update $reject_msg {
          value = "A model id can only use lowercase letters, numbers, dots, dashes and underscores. (E-VAL-004)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($input.input_per_1m < 0 || $input.output_per_1m < 0)) {
        var.update $reject_code {
          value = "E-PLN-003"
        }

        var.update $reject_msg {
          value = "This has to be zero or more. (E-PLN-003)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $key_clash > 0) {
        var.update $reject_code {
          value = "E-PLN-004"
        }

        var.update $reject_msg {
          value = "You already have a model with this id. (E-PLN-004)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-4"
            step          : "create_model"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_model"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Model create refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.add planner_model {
      data = {
        account_id   : $actor.account_id
        model_key    : $input.model_key
        label        : $input.label
        input_per_1m : $input.input_per_1m
        output_per_1m: $input.output_per_1m
        is_custom    : true
      }
    } as $model

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-4"
        step          : "create_model"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_model"
        entity_id     : $model.id
        correlation_id: $input.correlation_id
        message       : "Custom model added."
      }
    }
  }

  response = {model: $model}
}
