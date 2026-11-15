// COP-1 story 01 (2026-11-15) — the signed-in person's account copilot, if it has one: which user
// it is, its name, its daily cap, and whether it is switched on. Feeds the Team page "AI" label.
// Absence of a user_status row means switched on (USR-1).
query "account/copilot" verb=GET {
  api_group = "Members & Accounts"
  auth = "user"

  input {
  }

  stack {
    db.query user {
      where = $db.user.id == $auth.id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $me

    var $account_id {
      value = $me|get:"account_id":0
    }

    db.query ai_identity {
      where = ($account_id != 0) && ($db.ai_identity.account_id == $account_id)
      return = {type: "single"}
    } as $row

    var $copilot_user_id {
      value = $row|get:"user_id":0
    }

    var $name {
      value = $row|get:"name":""
    }

    var $daily_cap {
      value = $row|get:"daily_cap":0
    }

    db.query user_status {
      where = ($copilot_user_id != 0) && ($db.user_status.user_id == $copilot_user_id)
      return = {type: "single"}
    } as $status_row

    var $is_active {
      value = $status_row|get:"is_active":true
    }

    var $has_copilot {
      value = ($copilot_user_id != 0)
    }
  }

  response = {
    has_copilot: $has_copilot
    user_id    : $copilot_user_id
    name       : $name
    daily_cap  : $daily_cap
    is_active  : $is_active
  }
}
