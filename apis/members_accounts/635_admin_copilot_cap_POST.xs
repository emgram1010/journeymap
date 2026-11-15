// COP-1 story 05 (2026-11-15) — an account admin sets the copilot's daily cap: the most AI tool
// calls it may make per UTC day. 0 pauses it for the rest of every day until raised.
query "admin/copilot_cap" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    int daily_cap
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "admin/copilot_cap"
      }
    } as $admin_user

    var $cap_ok {
      value = ($input.daily_cap >= 0 && $input.daily_cap <= 100000)
    }

    precondition ($cap_ok) {
      error_type = "inputerror"
      error = "The daily limit must be a whole number from 0 to 100000. (E-COP-009)"
    }

    db.query ai_identity {
      where = $db.ai_identity.account_id == $admin_user.account_id
      return = {type: "single"}
    } as $row

    var $identity_id {
      value = $row|get:"id":0
    }

    precondition ($identity_id != 0) {
      error_type = "notfound"
      error = "This account does not have a copilot yet. (E-COP-008)"
    }

    db.patch ai_identity {
      field_name = "id"
      field_value = $identity_id
      data = {daily_cap: $input.daily_cap, updated_at: "now"}
    } as $patched

    function.run "ops/log_event" {
      input = {
        feature    : "COP-1"
        step       : "copilot_cap"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "Copilot daily limit changed."
        user_id    : $admin_user.id
        account_id : $admin_user.account_id
        entity_type: "ai_identity"
        entity_id  : $identity_id
        metadata   : {daily_cap: $input.daily_cap}
      }
    } as $_logged
  }

  response = {
    user_id  : $patched.user_id
    daily_cap: $patched.daily_cap
  }
}
