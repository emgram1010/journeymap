// PLN-4 (US-PLN-4-02) — Change the account's cost settings. Admin only.
//
// Rates are one of the two things PLN-2's access matrix reserves for
// admins (the model catalogue is the other): they change what every
// cost figure in the product says, for everyone in the account.
//
// Costs are computed in the browser from these two values and never
// stored (see costUtils.ts), so changing them re-prices history as well
// as future work. That is intended — there is no cost history in MVP.
//
// Same one-verdict/one-log/one-raise validation shape as PLN-3, and the
// same merged-value rule: a PATCH of one field is validated against the
// stored value of the other.
query "settings" verb=PATCH {
  api_group = "planner"
  auth = "user"

  input {
    text currency_symbol? filters=trim
    decimal human_hourly_rate?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_admin" {
      input = {role: $actor.role}
    }

    db.get planner_settings {
      field_name = "account_id"
      field_value = $actor.account_id
    } as $existing

    precondition ($existing != null) {
      error_type = "notfound"
      error = "Open the planner once before changing its settings."
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $next_symbol {
      value = $existing.currency_symbol
    }

    conditional {
      if ($raw_input|has:"currency_symbol") {
        var.update $next_symbol {
          value = $input.currency_symbol
        }
      }
    }

    var $next_rate {
      value = $existing.human_hourly_rate
    }

    conditional {
      if ($raw_input|has:"human_hourly_rate") {
        var.update $next_rate {
          value = $input.human_hourly_rate
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
      if ($next_symbol == null || $next_symbol == "") {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Pick a currency symbol. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_symbol|strlen) > 3) {
        var.update $reject_code {
          value = "E-VAL-002"
        }

        var.update $reject_msg {
          value = "A currency symbol can be at most 3 characters. (E-VAL-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $next_rate < 0) {
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
            step          : "update_settings"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_settings"
            entity_id     : $existing.id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Settings update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.patch planner_settings {
      field_name = "id"
      field_value = $existing.id
      data = {currency_symbol: $next_symbol, human_hourly_rate: $next_rate, updated_at: "now"}
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-4"
        step          : "update_settings"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_settings"
        entity_id     : $existing.id
        correlation_id: $input.correlation_id
        message       : "Cost settings updated."
      }
    }
  }

  response = {
    currency_symbol  : $updated.currency_symbol
    human_hourly_rate: $updated.human_hourly_rate
  }
}
