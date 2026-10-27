// See the users that belong to the same account as the authenticated user
query "account/my_team_members" verb=GET {
  api_group = "Members & Accounts"
  auth = "user"

  input {
  }

  stack {
    // Get the authenticated user record
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "created_at", "name", "email", "phone", "account_id", "role"]
    } as $user
  
    // Check that the user record matches the authenticated user
    precondition ($user.id == $auth.id) {
      error_type = "accessdenied"
    }
  
    // Get the users that belong to the same account as the authenticated user
    //
    // USR-1 (2026-10-22): `role` added to the output. It was missing, which is
    // why no Team page could exist — the column has been populated since the
    // product was built and `auth/me` already returns it for the caller's own
    // record, but this list dropped it for everyone else.
    //
    // Deliberately NOT joined to `user_status`. Whether someone is switched
    // off lives in its own side table with its own endpoint (`GET
    // user_status`), so this response changes by exactly one added field and
    // nothing that reads it today can break.
    db.query user {
      where = $db.user.account_id == $user.account_id
      return = {type: "list"}
      output = ["id", "created_at", "name", "email", "phone", "account_id", "role"]
    } as $team_members
  }

  response = $team_members
  tags = ["xano:quick-start"]
}