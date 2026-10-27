// CAT-1 (US-CAT-1-03) — Update an item type.
//
// `key` is DELIBERATELY ABSENT from this input block (D-2: never
// editable after creation — rates and lines reference it by key). If a
// client sends "key" in the body, there is no $input.key to read, so it
// is silently ignored; nothing downstream can act on a value that was
// never bound.
//
// Any member may edit label/unit/default_method/size/external_ref.
// Changing is_active (either direction) needs an admin (D-1, E-CAT-012)
// — same admin-gate shape as PLAN-2's E-PLAN-013, but scoped to the ONE
// field that matters here. TWO PRECONDITIONS, not one: format problems
// are inputerror (422); the admin-gate is accessdenied (403) — folding
// them into a single precondition would give the wrong status code for
// whichever reason didn't win the race.
//
// util.get_raw_input + |has is required here, not optional: an omitted
// optional text/int input is indistinguishable from "" / 0 using $input
// alone (CLAUDE.md), so "not sent, keep existing" has to be read from
// the raw body instead.
query "item-type/{item_type_id}" verb=PATCH {
  api_group = "catalog"
  auth = "user"

  input {
    int item_type_id filters=min:1
    text label? filters=trim
    text unit? filters=trim|lower
    int default_method_id? filters=min:0
    text size_label? filters=trim
    text external_ref? filters=trim
    bool is_active?
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "catalog/assert_item_type" {
      input = {account_id: $actor.account_id, item_type_id: $input.item_type_id, user_id: $actor.user_id, step: "update_item_type", correlation_id: $input.correlation_id}
    } as $guard

    var $existing {
      value = $guard.item
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

    var $next_unit {
      value = $existing.unit
    }

    conditional {
      if ($raw_input|has:"unit") {
        var.update $next_unit {
          value = $input.unit
        }
      }
    }

    var $next_default_method_id {
      value = $existing.default_method_id
    }

    conditional {
      if ($raw_input|has:"default_method_id") {
        var.update $next_default_method_id {
          value = $input.default_method_id
        }
      }
    }

    var $next_size_label {
      value = $existing.size_label
    }

    conditional {
      if ($raw_input|has:"size_label") {
        var.update $next_size_label {
          value = $input.size_label
        }
      }
    }

    var $next_external_ref {
      value = $existing.external_ref
    }

    conditional {
      if ($raw_input|has:"external_ref") {
        var.update $next_external_ref {
          value = $input.external_ref
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

    // ── Precondition A: the admin gate, checked first (matches the
    // agent_profile endpoints' own precedence: permission before
    // format), accessdenied not inputerror. ─────────────────────────
    var $admin_reject {
      value = ($is_active_changing == true && $actor.role != "admin")
    }

    conditional {
      if ($admin_reject == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : "update_item_type"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "item_type"
            entity_id     : $input.item_type_id
            correlation_id: $input.correlation_id
            error_code    : "E-CAT-012"
            message       : "Item type update refused: admin required to change active status."
          }
        }
      }
    }

    precondition ($admin_reject == false) {
      error_type = "accessdenied"
      error = "Only an account admin can deactivate, reactivate or delete a catalog entry. (E-CAT-012)"
    }

    // ── Precondition B: format/content validation, inputerror. ──────
    // key check is a no-op: $existing.key was already validated at
    // creation and is never re-sent, so only the label half of this can
    // ever fail here.
    function.run "catalog/validate_key_and_label" {
      input = {key: $existing.key, label: $next_label}
    } as $kl

    var $unit_ok {
      value = ($next_unit == "each" || $next_unit == "set" || $next_unit == "pair")
    }

    var $size_ok {
      value = (($next_size_label|strlen) <= 20)
    }

    var $ext_ok {
      value = ((($next_external_ref|strlen) <= 60) && (("/<[a-zA-Z][^>]*>/"|regex_matches:$next_external_ref) == false))
    }

    var $default_method {
      value = null
    }

    var $default_method_ok {
      value = true
    }

    conditional {
      if ($next_default_method_id != 0) {
        db.get method {
          field_name = "id"
          field_value = $next_default_method_id
        } as $default_method

        var.update $default_method_ok {
          value = ($default_method != null && $default_method.account_id == $actor.account_id && $default_method.is_active == true)
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
      if ($reject_code == "" && $unit_ok == false) {
        var.update $reject_code {
          value = "E-CAT-004"
        }

        var.update $reject_msg {
          value = "Pick a unit: each, set or pair. (E-CAT-004)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $size_ok == false) {
        var.update $reject_code {
          value = "E-CAT-009"
        }

        var.update $reject_msg {
          value = "Keep the size label short, up to 20 characters. (E-CAT-009)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $ext_ok == false) {
        var.update $reject_code {
          value = "E-CAT-010"
        }

        var.update $reject_msg {
          value = "Keep the external reference up to 60 characters, with no HTML. (E-CAT-010)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $default_method_ok == false) {
        var.update $reject_code {
          value = "E-CAT-011"
        }

        var.update $reject_msg {
          value = "Pick an active method from your own account, or leave it blank. (E-CAT-011)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : "update_item_type"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "item_type"
            entity_id     : $input.item_type_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Item type update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.patch item_type {
      field_name = "id"
      field_value = $input.item_type_id
      data = {
        label            : $next_label
        unit             : $next_unit
        default_method_id: $next_default_method_id
        size_label       : $next_size_label
        external_ref     : $next_external_ref
        is_active        : $next_is_active
        updated_at       : "now"
      }
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "CAT-1"
        step          : "update_item_type"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "item_type"
        entity_id     : $input.item_type_id
        correlation_id: $input.correlation_id
        message       : "Item type updated."
        metadata      : {is_active: $next_is_active}
      }
    }
  }

  response = {item_type: $updated}
}
