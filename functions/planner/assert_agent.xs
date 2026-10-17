// PLN-2 (US-PLN-2-02) — Agent tenancy guard.
//
// An agent carries no account of its own; it reaches one through its
// plan (`workspace_id → planner_workspace.account_id`). Two gets, never
// a loop — US-PLN-2-02 forbids an N+1 here.
//
// The `$workspace_id` var starts at 0 and is only filled when the agent
// exists, so a missing agent looks up workspace 0 (which never matches)
// instead of erroring on a null field. Same shape in assert_timeline and
// assert_task.
function "planner/assert_agent" {
  input {
    int account_id filters=min:1
    int agent_id filters=min:1
  }

  stack {
    db.get planner_agent {
      field_name = "id"
      field_value = $input.agent_id
    } as $agent

    var $workspace_id {
      value = 0
    }

    conditional {
      if ($agent != null) {
        var.update $workspace_id {
          value = $agent.workspace_id
        }
      }
    }

    db.get planner_workspace {
      field_name = "id"
      field_value = $workspace_id
    } as $workspace

    var $belongs {
      value = ($agent != null && $workspace != null && $workspace.account_id == $input.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Agent not found"
    }
  }

  response = {agent: $agent, workspace: $workspace}
}
