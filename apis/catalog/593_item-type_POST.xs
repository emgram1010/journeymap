// CAT-1 (US-CAT-1-03) — Create an item type. Any account member may do
// this (D-1) — only deactivating/deleting one needs an admin.
//
// `unit` is declared as text, not the table's own enum, so an invalid
// value gets THIS endpoint's friendly E-CAT-004 message instead of
// Xano's generic enum-validation error. Omitted (arrives as "",
// CLAUDE.md) defaults to "each" — the sensible default for a brand NEW
// row; PATCH does not carry this default-on-omission behaviour, because
// there an omitted field means "leave it alone," not "use the default."
query "item-type" verb=POST {
  api_group = "catalog"
  auth = "user"

  input {
    text key filters=trim
    text label filters=trim
    text unit? filters=trim|lower
    int default_method_id? filters=min:0
    text size_label? filters=trim
    text external_ref? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "catalog/validate_key_and_label" {
      input = {key: $input.key, label: $input.label}
    } as $kl

    var $unit {
      value = $input.unit
    }

    conditional {
      if ($unit == "") {
        var.update $unit {
          value = "each"
        }
      }
    }

    var $unit_ok {
      value = ($unit == "each" || $unit == "set" || $unit == "pair")
    }

    var $size_ok {
      value = (($input.size_label|strlen) <= 20)
    }

    var $ext_ok {
      value = ((($input.external_ref|strlen) <= 60) && (("/<[a-zA-Z][^>]*>/"|regex_matches:$input.external_ref) == false))
    }

    var $default_method {
      value = null
    }

    var $default_method_ok {
      value = true
    }

    conditional {
      if ($input.default_method_id != 0) {
        db.get method {
          field_name = "id"
          field_value = $input.default_method_id
        } as $default_method

        var.update $default_method_ok {
          value = ($default_method != null && $default_method.account_id == $actor.account_id && $default_method.is_active == true)
        }
      }
    }

    db.query item_type {
      where = $db.item_type.account_id == $actor.account_id && $db.item_type.key == $kl.key_stored
      return = {type: "count"}
    } as $dup_count

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
      if ($reject_code == "" && $dup_count > 0) {
        var.update $reject_code {
          value = "E-CAT-002"
        }

        var.update $reject_msg {
          value = "You already have an item with that id. (E-CAT-002)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : "create_item_type"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "item_type"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Item type create refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.add item_type {
      data = {
        account_id       : $actor.account_id
        key              : $kl.key_stored
        label            : $input.label
        unit             : $unit
        default_method_id: $input.default_method_id
        size_label       : $input.size_label
        external_ref     : $input.external_ref
        is_active        : true
      }
    } as $created

    function.run "ops/log_event" {
      input = {
        feature       : "CAT-1"
        step          : "create_item_type"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "item_type"
        entity_id     : $created.id
        correlation_id: $input.correlation_id
        message       : "Item type created."
        metadata      : {key: $kl.key_stored, unit: $unit}
      }
    }
  }

  response = {item_type: $created}
}
