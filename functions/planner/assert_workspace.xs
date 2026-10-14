// PLN-2 (US-PLN-2-02) — Plan (workspace) tenancy guard.
//
// THE RULE THAT MATTERS: a plan in someone else's account returns exactly
// the same error as a plan that does not exist. Never `accessdenied` —
// that would confirm the row is real and leak that another account holds
// it. Verified byte-identical in FT-PLN-2-04.
function "planner/assert_workspace" {
  input {
    int account_id filters=min:1
    int workspace_id filters=min:1
  }

  stack {
    db.get planner_workspace {
      field_name = "id"
      field_value = $input.workspace_id
    } as $workspace

    // One expression for "missing" and "someone else's" so the two cases
    // cannot drift apart into different messages.
    var $belongs {
      value = ($workspace != null && $workspace.account_id == $input.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Plan not found"
    }
  }

  response = {workspace: $workspace}
}
