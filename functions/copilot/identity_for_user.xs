// COP-1 story 01 — "is this user an AI identity, and what is its daily cap?" The one place that answers it. Absence of an ai_identity row means a person. Never throws.
function "copilot/identity_for_user" {
  input {
    int user_id
  }

  stack {
    db.query ai_identity {
      where = $db.ai_identity.user_id == $input.user_id
      return = {type: "single"}
    } as $row

    var $identity_id {
      value = $row|get:"id":0
    }

    var $daily_cap {
      value = $row|get:"daily_cap":0
    }

    var $account_id {
      value = $row|get:"account_id":0
    }

    var $name {
      value = $row|get:"name":""
    }

    var $is_ai {
      value = ($identity_id != 0)
    }
  }

  response = {
    is_ai      : $is_ai
    identity_id: $identity_id
    account_id : $account_id
    daily_cap  : $daily_cap
    name       : $name
  }
}
