// Generate a long-lived API token scoped for external automation tools (n8n, Make.com).
// The token is a standard Xano auth token with a 1-year expiration.
// External tools use it as a Bearer token on the snapshot GET and exception inbound endpoints.
// Token is shown once in the response — the user must copy it. It cannot be retrieved again.
// To revoke: the token expires naturally (1 year) or the user generates a new one.
// NOTE: This is the same token type as a user session — it grants access to all user-scoped
// journey-map endpoints. A fine-grained scope system is planned for v2.
query "automation_api_token/generate" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    // Optional label for the token (e.g. "Marcus's n8n", "Production Make")
    text label? filters=trim
  }

  stack {
    // Verify the requesting user exists
    db.get user {
      field_name = "id"
      field_value = $auth.id
    } as $user
  
    precondition ($user != null) {
      error_type = "notfound"
      error = "User not found"
    }
  
    // Generate a 1-year auth token (365 days = 31536000 seconds)
    security.create_auth_token {
      table = "user"
      extras = {}
      expiration = 31536000
      id = $auth.id
    } as $api_token
  }

  response = {
    token     : $api_token
    label     : $input.label
    expires_in: "365 days"
    user_id   : $auth.id
    warning   : "Copy this token now. It cannot be retrieved again. Use it as a Bearer token in your n8n or Make.com automation credentials."
  }

  guid = "rCkEv3sFbYwTjNMhQolK6gPqIXu"
}