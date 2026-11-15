// COP-2 story 03 — the menu badge: how many copilot actions are waiting for this account, and how
// many "runs, then tells you" actions are not yet seen. Two count queries on indexed
// (account_id, status), nothing else, so it is cheap to call from every screen. Any signed-in
// person in the account may read the count; deciding stays admin-only. A person in no account
// gets zeros.
query "copilot/actions_count" verb=GET {
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

    db.query copilot_action {
      where = $db.copilot_action.account_id == $account_id && $account_id != 0 && $db.copilot_action.status == "waiting"
      return = {type: "count"}
    } as $waiting

    db.query copilot_action {
      where = $db.copilot_action.account_id == $account_id && $account_id != 0 && $db.copilot_action.status == "told"
      return = {type: "count"}
    } as $unseen
  }

  response = {waiting: $waiting, unseen: $unseen}
  tags = ["cop-2"]
}
