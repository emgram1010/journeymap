// Create a new Journey Architecture.
// owner_user is always derived from the authenticated user — never accepted from input.
// title defaults to "Untitled Journey Architecture" when blank or omitted.
// status defaults to "draft" when omitted.
query journey_architecture verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    text title? filters=trim
    text description? filters=trim
    enum status? {
      values = ["draft", "active", "archived"]
    }
  
    int account_id? {
      table = "account"
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
  
    db.add journey_architecture {
      data = {
        created_at : "now"
        updated_at : "now"
        title      : $title
        description: $input.description
        status     : $status
        owner_user : $auth.id
        account_id : $input.account_id
      }
    } as $model
  }

  response = $model
}