// Signup and retrieve an authentication token
//
// 2026-10-14 — a signup now creates its OWN account and makes the new user
// its admin (self-serve tenancy, founder's decision). Before this, signup
// created a user with no account at all, and every downstream record
// faithfully inherited the resulting zero: architecture.account_id 0,
// journey_map.account_id 0. That silently disabled everything
// account-scoped for new users — most visibly the GOV-1 feature flags
// (`ops/feature_enabled` treats account_id 0 as "no account, flag off"),
// so `publish_gate` and `required_fields_ui` could never be turned on for
// them.
//
// WHY ADMIN, NOT MEMBER: `role == "admin"` is what gates editing your own
// account's settings (api 134) and reading its event log (api 17). A
// self-serve signup that produced a "member" would create a workspace
// nobody could administer.
//
// The account and the user are written in one transaction — a half-done
// signup that leaves an orphan account, or a user with no account, is
// exactly the state this change exists to prevent.
query "auth/signup" verb=POST {
  api_group = "Authentication"

  input {
    text name?
    email email? filters=trim|lower
    text password?
  }

  stack {
    // Check if a user record with that email exists
    db.get user {
      field_name = "email"
      field_value = $input.email
    } as $existing_user

    // Verify that the email being used to sign up is unique
    precondition ($existing_user == null) {
      error_type = "accessdenied"
      error = "This account is already in use."
    }

    // Signup only collects a person's name, so that is the best available
    // label for their workspace. An admin can rename it in settings (134).
    var $account_name {
      value = "My workspace"
    }

    conditional {
      if ($input.name != null && $input.name != "") {
        var.update $account_name {
          value = $input.name ~ "'s workspace"
        }
      }
    }

    db.transaction {
      description = "A signup's account and its first user are created together or not at all"
      stack {
        db.add account {
          enforce_hidden_fields = false
          data = {
            created_at: "now"
            name      : $account_name
          }
        } as $account

        db.add user {
          enforce_hidden_fields = false
          data = {
            created_at: "now"
            name      : $input.name
            email     : $input.email
            password  : $input.password
            role      : "admin"
            account_id: $account.id
          }
        } as $user
      }
    }

    // Create an authentiction token
    security.create_auth_token {
      table = "user"
      extras = {}
      expiration = 86400
      id = $user.id
    } as $authToken

    // Create an event log for signup.
    // metadata is ids only: this used to pass the whole $user record, which
    // put the hashed password into the event log. Logs never carry
    // credentials (OBS-1's rule, applied here while this line was open).
    function.run "Getting Started Template/create_event_log" {
      input = {
        user_id   : $user.id
        account_id: $account.id
        action    : "signup"
        metadata  : {user_id: $user.id, account_id: $account.id}
      }
    } as $event_log
  }

  response = {authToken: $authToken, user_id: $user.id}
  tags = ["xano:quick-start"]
}
