// Update the current account's profile and AI context. Admin-only.
query "account/me" verb=PATCH {
  api_group = "journey-map"
  auth = "user"

  input {
    // Company display name
    text name?

    // General company description (public bio)
    text description?

    // Office / HQ location
    text location?

    // Freeform context for the AI agent — industry, customer types, team names, terminology
    text ai_context?
  }

  stack {
    // Resolve the authenticated user
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id", "role"]
    } as $user

    precondition ($user.account_id != null) {
      error_type = "notfound"
      error = "No account linked to this user"
    }

    precondition ($user.role == "admin") {
      error_type = "accessdenied"
      error = "Only account admins can update account settings"
    }

    // Collect only the fields that were actually provided
    util.get_all_input as $inputs

    // Apply the update
    db.patch account {
      field_name = "id"
      field_value = $user.account_id
      data = $inputs|filter_empty_text:""
    } as $updated_account

    // Return full account with role so the UI doesn't need a second fetch
    var $response {
      value = $updated_account|set:"role":$user.role
    }
  }

  response = $response
  guid = "account_me_PATCH_v1"
}
