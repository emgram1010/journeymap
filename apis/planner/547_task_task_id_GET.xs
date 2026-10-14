// PLN-7 (US-PLN-7-06) — One task, with its derived fields.
//
// The derived values come from the same planner/derive_tasks call the
// list uses, filtered to this task, rather than a second
// implementation — a task's start time depends on every task before it
// in the same container, so it cannot be computed from the row alone.
//
// The filtering loop branches on the LOOP ITEM (`$t.id == ...`), which
// is safe; branching on a variable updated earlier in the same
// iteration would silently lose the write (CLAUDE.md).
query "task/{task_id}" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int task_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_task" {
      input = {account_id: $actor.account_id, task_id: $input.task_id}
    } as $guard

    function.run "planner/derive_tasks" {
      input = {workspace_id: $guard.workspace.id, timeline_id: $guard.task.timeline_id}
    } as $view

    var $found {
      value = null
    }

    foreach ($view.tasks) {
      each as $t {
        conditional {
          if ($t.id == $input.task_id) {
            var.update $found {
              value = $t
            }
          }
        }
      }
    }
  }

  response = $found
}
