// CAT-1 (US-CAT-1-03) — Create a method. Any account member may do
// this (D-1) — only deactivating/deleting one needs an admin.
//
// `role_id` is NOT exposed here (MVP scope, CAT-1 epic Non-Goals):
// ROLE-1's actor_role table doesn't exist yet and the settings screen
// (US-CAT-1-04) has no role picker either. Every method is created
// with role_id = 0; ROLE-1 adds the way to set it later.
query "method" verb=POST {
  api_group = "catalog"
  auth = "user"

  input {
    text key filters=trim
    text label filters=trim
    int sub_journey_map_id? filters=min:0
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "catalog/validate_key_and_label" {
      input = {key: $input.key, label: $input.label}
    } as $kl

    var $sub_map {
      value = null
    }

    var $sub_map_ok {
      value = true
    }

    conditional {
      if ($input.sub_journey_map_id != 0) {
        db.get journey_map {
          field_name = "id"
          field_value = $input.sub_journey_map_id
        } as $sub_map

        var.update $sub_map_ok {
          value = ($sub_map != null && $sub_map.account_id == $actor.account_id)
        }
      }
    }

    db.query method {
      where = $db.method.account_id == $actor.account_id && $db.method.key == $kl.key_stored
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
      if ($reject_code == "" && $dup_count > 0) {
        var.update $reject_code {
          value = "E-CAT-008"
        }

        var.update $reject_msg {
          value = "You already have a method with that id. (E-CAT-008)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : "create_method"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "method"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Method create refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.add method {
      data = {
        account_id        : $actor.account_id
        key               : $kl.key_stored
        label             : $input.label
        sub_journey_map_id: $input.sub_journey_map_id
        role_id           : 0
        is_active         : true
      }
    } as $created

    function.run "ops/log_event" {
      input = {
        feature       : "CAT-1"
        step          : "create_method"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "method"
        entity_id     : $created.id
        correlation_id: $input.correlation_id
        message       : "Method created."
        metadata      : {key: $kl.key_stored}
      }
    }
  }

  response = {method: $created}
}
