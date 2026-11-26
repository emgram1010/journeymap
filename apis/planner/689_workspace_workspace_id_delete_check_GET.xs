// REPEAT-2 story 04 — "May this plan be deleted, and what would go?" for the screen's confirm. Read-only: all of the answer comes from planner/delete_check (the same function the DELETE endpoint obeys), so the confirm can never promise something the delete refuses. Any planner may ask; another account's plan is "Plan not found". It does not say whether the CALLER may delete (admin only): the DELETE endpoint decides that. Every input is passed to function.run explicitly.
query "workspace/{workspace_id}/delete-check" verb=GET {
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

    function.run "planner/delete_check" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $check
  }

  response = {
    allowed          : $check.allowed
    code             : $check.code
    message          : $check.message
    name             : $check.name
    counts           : $check.counts
    frees_repeat_date: $check.frees_repeat_date
  }
}
