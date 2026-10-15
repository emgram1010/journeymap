// Allows user to update the password in the password reset flow
//
// FOUND 2026-10-15 (E2E-1): logged the whole user record — including
// the BRAND-NEW hashed password, written moments earlier in this same
// call — into event_log every time someone changes their password.
// The worst-timed instance of this bug (same class already fixed on
// signup; auth/login, auth/me and reset/magic-link-login fixed the
// same session). ids only now.
query "reset/update_password" verb=POST {
  api_group = "Authentication"
  auth = "user"

  input {
    text password? filters=trim|min:8
    text confirm_password? filters=trim
  }

  stack {
    // Check that the password inputs are matching
    precondition ($input.password == $input.confirm_password) {
      error = "Passwords do not match!"
    }
  
    // Get user record based on the id of the auth token
    db.get user {
      field_name = "id"
      field_value = $auth.id
    } as $user
  
    // Check that the user record id matches the auth id
    precondition ($user.id == $auth.id) {
      error_type = "accessdenied"
    }
  
    // Update user record with the new password
    db.edit user {
      field_name = "id"
      field_value = $auth.id
      enforce_hidden_fields = false
      data = {password: $input.password}
    } as $user
  
    // Create event log. ids only — never the user record (it carries
    // the password just set, above).
    function.run "Getting Started Template/create_event_log" {
      input = {
        user_id   : $user.id
        account_id: $user.account_id
        action    : "reset_password"
        metadata  : {user_id: $user.id, account_id: $user.account_id}
      }
    } as $event_log
  }

  response = {}
    |set:"message":({}
      |set:"success":"true"
      |set:"message":"Password updated"
    )
  tags = ["xano:quick-start"]
}