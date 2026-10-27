// CAT-1 (US-CAT-1-03) — Convenience endpoint: always sets is_active =
// false. Admin-only (D-1, E-CAT-012). PATCH can do the same thing by
// sending is_active, but this is the one-click path the settings
// screen's Deactivate button uses.
query "item-type/{item_type_id}/deactivate" verb=POST {
  api_group = "catalog"
  auth = "user"

  input {
    int item_type_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "catalog/assert_item_type" {
      input = {account_id: $actor.account_id, item_type_id: $input.item_type_id, user_id: $actor.user_id, step: "deactivate_item_type", correlation_id: $input.correlation_id}
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
            step          : "deactivate_item_type"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "item_type"
            entity_id     : $input.item_type_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Item type deactivate refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "accessdenied"
      error = $reject_msg
    }

    db.patch item_type {
      field_name = "id"
      field_value = $input.item_type_id
      data = {
        is_active : false
        updated_at: "now"
      }
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "CAT-1"
        step          : "deactivate_item_type"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "item_type"
        entity_id     : $input.item_type_id
        correlation_id: $input.correlation_id
        message       : "Item type deactivated."
      }
    }
  }

  response = {item_type: $updated}
}
