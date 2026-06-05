// Returns the account record for the currently authenticated user.
// If the user has no account yet, one is auto-created and they are made admin.
query "account/me" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    // Resolve the authenticated user
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "name", "account_id", "role"]
    } as $user
  
    // Track resolved account_id and role separately so we can update them if needed
    var $resolved_account_id {
      value = $user.account_id
    }
  
    var $resolved_role {
      value = $user.role
    }
  
    // Auto-provision an account if the user has none
    conditional {
      if ($user.account_id == null) {
        db.add account {
          enforce_hidden_fields = false
          data = {name: $user.name, created_at: "now"}
        } as $new_account
      
        db.patch user {
          field_name = "id"
          field_value = $user.id
          data = {account_id: $new_account.id, role: "admin"}
        } as $patched_user
      
        var.update $resolved_account_id {
          value = $new_account.id
        }
      
        var.update $resolved_role {
          value = "admin"
        }
      }
    }
  
    // Fetch the account record
    db.get account {
      field_name = "id"
      field_value = $resolved_account_id
      output = ["id", "name", "description", "location", "ai_context"]
    } as $account
  
    // Attach the user's role so the frontend can gate edit access
    var $account_with_role {
      value = $account|set:"role":$resolved_role
    }
  }

  response = $account_with_role
  guid = "account_me_GET_v1"
}