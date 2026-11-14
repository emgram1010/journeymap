// See an account's details: your own, or any account if you are a platform admin.
//
// SEC-2 (US-SEC-2-03, 2026-11-14).
// The starter-template version had NO sign-in at all. Proven live on
// 2026-11-14: a request with no token returned an account's name,
// description, location and its private AI context, for any number sent.
//
// Now: signed-in only, and scoped. Somebody else's account answers "not
// found" — the same answer as an account that does not exist — because
// "that exists but is not yours" confirms the number is real.
//
// `account_id` is optional. An omitted int arrives as `0` (never null), and
// no real account is 0, so 0 means "my own account".
query "account/details" verb=GET {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The account to read. Omit for your own.
    int account_id?
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id", "is_platform_admin"]
    } as $me

    precondition ($me != null) {
      error_type = "accessdenied"
      error = "We couldn't find your user record. (E-USR-010)"
    }

    var $target_id {
      value = $me.account_id
    }

    conditional {
      if ($input.account_id != 0) {
        var.update $target_id {
          value = $input.account_id
        }
      }
    }

    var $allowed {
      value = ($target_id == $me.account_id) || ($me.is_platform_admin == true)
    }

    conditional {
      if ($allowed == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "SEC-2"
            step          : "account_details"
            outcome       : "rejected"
            severity      : "warn"
            user_id       : $me.id
            account_id    : $me.account_id
            entity_type   : "account"
            entity_id     : $target_id
            correlation_id: ""
            error_code    : ""
            message       : "Refused: someone asked for the details of an account that is not theirs."
            duration_ms   : 0
            metadata      : {asked_for_account_id: $target_id}
          }
        } as $_denied
      }
    }

    precondition ($allowed) {
      error_type = "notfound"
      error = "Account not found."
    }

    db.get account {
      field_name = "id"
      field_value = $target_id
    } as $account_details

    precondition ($account_details != null) {
      error_type = "notfound"
      error = "Account not found."
    }
  }

  response = $account_details
  tags = ["xano:quick-start"]
}
