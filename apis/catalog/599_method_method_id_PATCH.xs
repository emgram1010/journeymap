// CAT-1 (US-CAT-1-03) — Update a method. Same shape as the item-type
// PATCH endpoint — see that file's header for why `key` is absent from
// this input block, and why the admin-gate and format checks are two
// separate preconditions (accessdenied vs inputerror).
query "method/{method_id}" verb=PATCH {
  api_group = "catalog"
  auth = "user"

  input {
    int method_id filters=min:1
    text label? filters=trim
    int sub_journey_map_id? filters=min:0
    bool is_active?
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "catalog/assert_method" {
      input = {account_id: $actor.account_id, method_id: $input.method_id, user_id: $actor.user_id, step: "update_method", correlation_id: $input.correlation_id}
    } as $guard

    var $existing {
      value = $guard.method
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

    var $next_sub_journey_map_id {
      value = $existing.sub_journey_map_id
    }

    conditional {
      if ($raw_input|has:"sub_journey_map_id") {
        var.update $next_sub_journey_map_id {
          value = $input.sub_journey_map_id
        }
      }
    }

    var $next_is_active {
      value = $existing.is_active
    }

    var $is_active_changing {
      value = false
    }

    conditional {
      if ($raw_input|has:"is_active") {
        var.update $next_is_active {
          value = $input.is_active
        }
      }
    }

    conditional {
      if ($next_is_active != $existing.is_active) {
        var.update $is_active_changing {
          value = true
        }
      }
    }

    // ── Precondition A: the admin gate, accessdenied, checked first. ─
    var $admin_reject {
      value = ($is_active_changing == true && $actor.role != "admin")
    }

    conditional {
      if ($admin_reject == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : "update_method"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "method"
            entity_id     : $input.method_id
            correlation_id: $input.correlation_id
            error_code    : "E-CAT-012"
            message       : "Method update refused: admin required to change active status."
          }
        }
      }
    }

    precondition ($admin_reject == false) {
      error_type = "accessdenied"
      error = "Only an account admin can deactivate, reactivate or delete a catalog entry. (E-CAT-012)"
    }

    // ── Precondition B: format/content validation, inputerror. ──────
    function.run "catalog/validate_key_and_label" {
      input = {key: $existing.key, label: $next_label}
    } as $kl

    var $sub_map {
      value = null
    }

    var $sub_map_ok {
      value = true
    }

    conditional {
      if ($next_sub_journey_map_id != 0) {
        db.get journey_map {
          field_name = "id"
          field_value = $next_sub_journey_map_id
        } as $sub_map

        var.update $sub_map_ok {
          value = ($sub_map != null && $sub_map.account_id == $actor.account_id)
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
      if ($kl.ok == false) {
        var.update $reject_code {
          value = $kl.code
        }

        var.update $reject_msg {
          value = $kl.message
        }
      }
    }

    conditional {
      if ($reject_code == "" && $sub_map_ok == false) {
        var.update $reject_code {
          value = "E-CAT-007"
        }

        var.update $reject_msg {
          value = "Pick a map from your own account. (E-CAT-007)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : "update_method"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "method"
            entity_id     : $input.method_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Method update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.patch method {
      field_name = "id"
      field_value = $input.method_id
      data = {
        label             : $next_label
        sub_journey_map_id: $next_sub_journey_map_id
        is_active         : $next_is_active
        updated_at        : "now"
      }
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "CAT-1"
        step          : "update_method"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "method"
        entity_id     : $input.method_id
        correlation_id: $input.correlation_id
        message       : "Method updated."
        metadata      : {is_active: $next_is_active}
      }
    }
  }

  response = {method: $updated}
}
