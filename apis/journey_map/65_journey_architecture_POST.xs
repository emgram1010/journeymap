// Create a new Journey Architecture.
// owner_user is always derived from the authenticated user — never accepted from input.
// title defaults to "Untitled Journey Architecture" when blank or omitted.
// status defaults to "draft" when omitted.
//
// 2026-10-14 — account_id is now derived from the creator's own user record
// instead of being accepted as input. Two reasons:
//   1. The client never sent it, and an omitted optional int arrives as 0, so
//      every architecture was created account-less. Everything beneath it
//      (maps, and so every account-scoped feature flag) inherited that zero.
//   2. Taking it from input was a tenancy hole: a caller could have put an
//      architecture inside someone else's account. owner_user was already
//      derived from the token for exactly this reason; account_id now matches.
query journey_architecture verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    text title? filters=trim
    text description? filters=trim
    enum status? {
      values = ["draft", "active", "archived"]
    }
  }

  stack {
    var $title {
      value = "Untitled Journey Architecture"
    }
  
    var $status {
      value = "draft"
    }
  
    conditional {
      if ($input.title != null && $input.title != "") {
        var.update $title {
          value = $input.title
        }
      }
    }
  
    conditional {
      if ($input.status != null) {
        var.update $status {
          value = $input.status
        }
      }
    }
  
    db.get user {
      field_name = "id"
      field_value = $auth.id
    } as $creator

    precondition ($creator != null) {
      error_type = "accessdenied"
      error = "Access denied"
    }

    db.add journey_architecture {
      enforce_hidden_fields = false
      data = {
        created_at : "now"
        updated_at : "now"
        title      : $title
        description: $input.description
        status     : $status
        owner_user : $auth.id
        account_id : $creator.account_id
      }
    } as $model
  }

  response = $model
}