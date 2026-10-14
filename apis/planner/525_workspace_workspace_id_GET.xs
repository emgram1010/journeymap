// PLN-3 (US-PLN-3-02) — Read one plan, with the same four counts the
// list shows.
//
// Tenancy is planner/assert_workspace's job: a plan in another account
// returns the same "not found" as a plan that never existed, so this
// endpoint cannot be used to probe which ids are real.
//
// Archived plans ARE readable (P3A-1 makes them read-only, not
// invisible) — they are only hidden from the default list.
query "workspace/{workspace_id}" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "planner/workspace_counts" {
      input = {workspace_id: $input.workspace_id}
    } as $counts
  }

  response = {
    workspace: $guard.workspace
    counts   : $counts
  }
}
