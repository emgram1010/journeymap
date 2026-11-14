// Moves the caller into an existing account. PLATFORM ADMIN ONLY.
//
// SEC-2 (US-SEC-2-02, 2026-11-14) — LOCKED, NOT DELETED.
// This came with the Xano starter template and let ANY signed-in user move
// themselves into ANY account by sending its number: no invite, no admin
// check. Proven live on 2026-11-14 — a test user in account 8 called this
// with account 9 and could immediately list account 9's people. It also
// returned the caller's whole user record (password hash included) and
// wrote the same record into the event log.
//
// Nothing in any frontend, tool or function calls it (checked), and the
// event log shows no real user ever did. It is kept, behind the platform
// admin guard, because a lock can be lifted and a delete cannot (D-2).
// PADM-1 story 08 builds the proper, scoped way to place a person.
//
// The response is SHAPED and the event carries ids only.
query "user/join_account" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The ID of the account to move into.
    int account_id
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id"]
    } as $user

    precondition ($user != null) {
      error_type = "notfound"
      error = "Authenticated user not found."
    }

    // Logs its own refusal (E-OBS-001) before throwing.
    function.run "ops/require_platform_admin" {
      input = {
        user_id       : $auth.id
        what          : "action"
        feature       : "SEC-2"
        step          : "join_account"
        account_id    : $user.account_id
        correlation_id: ""
      }
    } as $_admin

    db.get account {
      field_name = "id"
      field_value = $input.account_id
      output = ["id"]
    } as $account

    precondition ($account != null) {
      error_type = "notfound"
      error = "Account not found."
    }

    db.edit user {
      field_name = "id"
      field_value = $user.id
      enforce_hidden_fields = false
      data = {account_id: $input.account_id}
    } as $updated_user

    function.run "ops/log_event" {
      input = {
        feature       : "SEC-2"
        step          : "join_account"
        outcome       : "success"
        severity      : "info"
        user_id       : $user.id
        account_id    : $account.id
        entity_type   : "user"
        entity_id     : $user.id
        correlation_id: ""
        error_code    : ""
        message       : "A platform admin moved themselves into an account."
        duration_ms   : 0
        metadata      : {from_account_id: $user.account_id, to_account_id: $account.id}
      }
    } as $_logged
  }

  response = {id: $updated_user.id, account_id: $updated_user.account_id}
  tags = ["xano:quick-start"]
}
