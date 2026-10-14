// PLN-2 (US-PLN-2-02) — Timeline tenancy guard.
//
// Same two-get chain as assert_agent: the timeline reaches its account
// through `workspace_id → planner_workspace.account_id`. Missing and
// cross-account both return "Timeline not found".
function "planner/assert_timeline" {
  input {
    int account_id filters=min:1
    int timeline_id filters=min:1
  }

  stack {
    db.get planner_timeline {
      field_name = "id"
      field_value = $input.timeline_id
    } as $timeline

    var $workspace_id {
      value = 0
    }

    conditional {
      if ($timeline != null) {
        var.update $workspace_id {
          value = $timeline.workspace_id
        }
      }
    }

    db.get planner_workspace {
      field_name = "id"
      field_value = $workspace_id
    } as $workspace

    var $belongs {
      value = ($timeline != null && $workspace != null && $workspace.account_id == $input.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Timeline not found"
    }
  }

  response = {timeline: $timeline, workspace: $workspace}
}
