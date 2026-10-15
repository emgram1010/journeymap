// Get the user record belonging to the authentication token
//
// FOUND 2026-10-15 (E2E-1): logged the whole user record (name, email)
// into event_log on every session check — this fires on every page
// load, the highest-volume call in the whole app. ids only now, same
// fix as auth/login.
query "auth/me" verb=GET {
  api_group = "Authentication"
  auth = "user"

  input {
  }

  stack {
    // Get the user record based on the auth ID
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "created_at", "name", "email", "account_id", "role", "is_platform_admin"]
    } as $user
  
    // Create an event log for get user record. ids only.
    function.run "Getting Started Template/create_event_log" {
      input = {
        user_id   : $user.id
        account_id: $user.account_id
        action    : "get_auth_user"
        metadata  : {user_id: $user.id, account_id: $user.account_id}
      }
    } as $event_log
  }

  response = $user
  tags = ["xano:quick-start"]
}