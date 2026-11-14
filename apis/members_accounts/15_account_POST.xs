// Creates an account. PLATFORM ADMIN ONLY, and the caller STAYS where they are.
//
// SEC-2 (US-SEC-2-02, 2026-11-14) — LOCKED, NOT DELETED.
// The starter-template version let ANY signed-in user create an account and
// moved them into it as its admin. Proven live on 2026-11-14: the only admin
// of a test account called this and walked out, leaving that account with
// nobody in charge — straight past USR-1's "an account always has an admin"
// rule. It also wrote the caller's whole user record into the event log.
//
// Two changes:
//   1. Platform admin only (`ops/require_platform_admin`, which logs its own
//      refusal).
//   2. It no longer moves the caller. With the guard in place the only person
//      who can call this is the founder, and moving the founder out of their
//      own account on every call would be a trap, not a feature.
//
// Signing up does NOT come through here — `auth/signup` creates its own
// account in its own transaction — so new customers are unaffected.
// PADM-1 story 04 builds the real "create an account with its first admin".
query account verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The name of the new account.
    text name filters=trim

    // A brief description of the new account (optional).
    text description? filters=trim

    // The primary location of the new account (optional).
    text location? filters=trim
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

    function.run "ops/require_platform_admin" {
      input = {
        user_id       : $auth.id
        what          : "action"
        feature       : "SEC-2"
        step          : "create_account"
        account_id    : $user.account_id
        correlation_id: ""
      }
    } as $_admin

    precondition ($input.name != "") {
      error_type = "inputerror"
      error = "An account needs a name."
    }

    db.add account {
      enforce_hidden_fields = false
      data = {
        name       : $input.name
        description: $input.description
        location   : $input.location
        created_at : "now"
      }
    } as $new_account

    function.run "ops/log_event" {
      input = {
        feature       : "SEC-2"
        step          : "create_account"
        outcome       : "success"
        severity      : "info"
        user_id       : $user.id
        account_id    : $new_account.id
        entity_type   : "account"
        entity_id     : $new_account.id
        correlation_id: ""
        error_code    : ""
        message       : "A platform admin created an account."
        duration_ms   : 0
        metadata      : {created_by_user_id: $user.id}
      }
    } as $_logged
  }

  response = {account: {id: $new_account.id, name: $new_account.name}}
  tags = ["xano:quick-start"]
}
