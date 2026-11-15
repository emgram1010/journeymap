// COP-2 story 04 — the owner marks a "runs, then tells you" action as seen (told → seen). Admin of
// the same account only; anything else answers "not found" (E-COP-029). Seeing an already-seen
// item is a no-op success.
query "copilot/action_seen" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    int action_id
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/action_seen"
        entity_id    : $input.action_id
      }
    } as $admin_user

    db.query copilot_action {
      where = $db.copilot_action.id == $input.action_id
      return = {type: "single"}
      output = ["id", "account_id", "status"]
    } as $act

    var $act_id {
      value = $act|get:"id":0
    }

    var $act_account {
      value = $act|get:"account_id":0
    }

    var $status {
      value = $act|get:"status":""
    }

    precondition ($act_id != 0 && $act_account == $admin_user.account_id && ($status == "told" || $status == "seen")) {
      error_type = "notfound"
      error = "We couldn't find that item. (E-COP-029)"
    }

    conditional {
      if ($status == "told") {
        db.patch copilot_action {
          field_name = "id"
          field_value = $act_id
          data = {status: "seen", updated_at: "now"}
        } as $_seen
      }
    }
  }

  response = {action_id: $act_id, status: "seen"}
  tags = ["cop-2"]
}
