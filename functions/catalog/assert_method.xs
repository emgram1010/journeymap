// CAT-1 — Tenancy guard for a single method id. Same shape as
// catalog/assert_item_type; see that file's header for why the logging
// happens HERE (before the throw unwinds the endpoint's own stack) and
// why existence (notfound) and ownership (accessdenied, E-CAT-006) are
// two separate checks rather than one folded-together notfound.
function "catalog/assert_method" {
  input {
    int account_id filters=min:1
    int method_id filters=min:1
    int user_id filters=min:1
    text step filters=trim
    text correlation_id? filters=trim
  }

  stack {
    db.get method {
      field_name = "id"
      field_value = $input.method_id
    } as $method

    precondition ($method != null) {
      error_type = "notfound"
      error = "Method not found"
    }

    conditional {
      if ($method.account_id != $input.account_id) {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : $input.step
            outcome       : "rejected"
            severity      : "warn"
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "method"
            entity_id     : $input.method_id
            correlation_id: $input.correlation_id
            error_code    : "E-CAT-006"
            message       : "Cross-account access refused."
          }
        }
      }
    }

    precondition ($method.account_id == $input.account_id) {
      error_type = "accessdenied"
      error = "You can't change another account's catalog. (E-CAT-006)"
    }
  }

  response = {method: $method}
}
