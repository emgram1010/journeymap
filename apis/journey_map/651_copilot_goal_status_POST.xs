// COP-4 story 01 — an account admin confirms a goal the copilot recorded, or marks it done or
// dropped. Only a person moves a goal out of "proposed".
query "copilot/goal_status" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int goal_id?
    text status? filters=trim|lower
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/goal_status"
        entity_id    : 0
      }
    } as $admin_user

    var $account_id {
      value = $admin_user.account_id
    }

    var $status_ok {
      value = ($input.status == "confirmed" || $input.status == "done" || $input.status == "dropped" || $input.status == "proposed")
    }

    precondition ($status_ok) {
      error_type = "inputerror"
      error = "Choose confirmed, done or dropped. (E-COP-050)"
    }

    db.query copilot_goal {
      where = $db.copilot_goal.id == $input.goal_id
      return = {type: "single"}
    } as $goal

    precondition ($input.goal_id != 0 && ($goal|get:"account_id":0) == $account_id) {
      error_type = "notfound"
      error = "We couldn't find that item. (E-COP-029)"
    }

    db.patch copilot_goal {
      field_name = "id"
      field_value = $input.goal_id
      data = {status: $input.status, updated_at: "now"}
    } as $_patched

    function.run "ops/log_event" {
      input = {
        feature    : "COP-4"
        step       : "goal_status_changed"
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "The owner changed a goal's status."
        user_id    : $auth.id
        account_id : $account_id
        entity_type: "copilot_goal"
        entity_id  : $input.goal_id
        metadata   : {from: ($goal|get:"status":""), to: $input.status}
      }
    } as $_logged
  }

  response = {goal_id: $input.goal_id, status: $input.status}
  tags = ["cop-4"]
}
