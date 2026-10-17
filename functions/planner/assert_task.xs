// PLN-2 (US-PLN-2-02) — Task tenancy guard.
//
// A task carries `workspace_id` directly (it may sit in the backlog with
// `timeline_id = 0`), so the chain is task → plan → account. It must NOT
// go through the timeline: a backlog task has none.
function "planner/assert_task" {
  input {
    int account_id filters=min:1
    int task_id filters=min:1
  }

  stack {
    db.get planner_task {
      field_name = "id"
      field_value = $input.task_id
    } as $task

    var $workspace_id {
      value = 0
    }

    conditional {
      if ($task != null) {
        var.update $workspace_id {
          value = $task.workspace_id
        }
      }
    }

    db.get planner_workspace {
      field_name = "id"
      field_value = $workspace_id
    } as $workspace

    var $belongs {
      value = ($task != null && $workspace != null && $workspace.account_id == $input.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Task not found"
    }
  }

  response = {task: $task, workspace: $workspace}
}
