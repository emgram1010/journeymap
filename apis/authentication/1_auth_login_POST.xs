// Login and retrieve an authentication token
//
// FOUND 2026-10-15 (E2E-1's supportability drill): this logged the
// WHOLE user record — hashed password included — into event_log on
// every single login. Same class of bug already fixed on signup
// (2026-10-14); this one, auth/me, and reset/update-password were
// missed at the time. metadata is ids only now, same pattern.
query "auth/login" verb=POST {
  api_group = "Authentication"

  input {
    email email? filters=trim|lower
    text password?
  }

  stack {
    // Get the user record via email
    db.get user {
      field_name = "email"
      field_value = $input.email
      output = [
        "id"
        "created_at"
        "name"
        "email"
        "password"
        "account_id"
        "role"
      ]
    } as $user
  
    // Check to make sure a user with that email exists
    precondition ($user != null) {
      error_type = "accessdenied"
      error = "Invalid Credentials."
    }
  
    // Check that the password matches the hashed password
    security.check_password {
      text_password = $input.password
      hash_password = $user.password
    } as $pass_result
  
    // Verify that the password check passed
    precondition ($pass_result) {
      error_type = "accessdenied"
      error = "Invalid Credentials."
    }
  
    // Create an authentication token
    security.create_auth_token {
      table = "user"
      extras = {}
      expiration = 86400
      id = $user.id
    } as $authToken
  
    // Create an event log for login. ids only — never the user record.
    function.run "Getting Started Template/create_event_log" {
      input = {
        user_id   : $user.id
        account_id: $user.account_id
        action    : "login"
        metadata  : {user_id: $user.id, account_id: $user.account_id}
      }
    } as $event_log
  }

  response = {authToken: $authToken, user_id: $user.id}
  tags = ["xano:quick-start"]
}