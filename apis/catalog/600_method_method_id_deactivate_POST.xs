// CAT-1 (US-CAT-1-03) — Convenience endpoint: always sets is_active =
// false. Admin-only (D-1, E-CAT-012). Same shape as the item-type
// deactivate endpoint.
query "method/{method_id}/deactivate" verb=POST {
  api_group = "catalog"
  auth = "user"

  input {
    int method_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "catalog/assert_method" {
      input = {account_id: $actor.account_id, method_id: $input.method_id, user_id: $actor.user_id, step: "deactivate_method", correlation_id: $input.correlation_id}
    } as $guard

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($actor.role != "admin") {
        var.update $reject_code {
          value = "E-CAT-012"
        }

        var.update $reject_msg {
          value = "Only an account admin can deactivate, reactivate or delete a catalog entry. (E-CAT-012)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : "deactivate_method"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "method"
            entity_id     : $input.method_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Method deactivate refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "accessdenied"
      error = $reject_msg
    }

    db.patch method {
      field_name = "id"
      field_value = $input.method_id
      data = {
        is_active : false
        updated_at: "now"
      }
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "CAT-1"
        step          : "deactivate_method"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "method"
        entity_id     : $input.method_id
        correlation_id: $input.correlation_id
        message       : "Method deactivated."
      }
    }
  }

  response = {method: $updated}
}
