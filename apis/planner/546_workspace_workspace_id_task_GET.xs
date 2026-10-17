// PLN-7 — The tasks of one container: a timeline, or the backlog.
//
// Omitting `timeline_id` (or sending 0) returns the backlog.
// Every task comes back with its derived fields from the one shared
// implementation in planner/derive_tasks, so the list, the single
// read and PLN-8's hydrate can never disagree about a start time.
query "workspace/{workspace_id}/task" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    int timeline_id?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "planner/derive_tasks" {
      input = {workspace_id: $input.workspace_id, timeline_id: $input.timeline_id}
    } as $view
  }

  response = {
    timeline_id: $input.timeline_id
    is_backlog : ($input.timeline_id == 0)
    tasks      : $view.tasks
  }
}
