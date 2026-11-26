// REPEAT-1 story 06 — Where a plan came from and what was made from it: `repeated_from` (null when the plan was not made by a repeat; `exists: false` when its source has since been deleted, so the repeated plan still opens) and `repeated_to` (the plans repeated from this one that still exist, earliest first, each with how many copied slots still need a look). Read-only. Another account's plan is "not found". All of the answer comes from repeat/history. Every input is passed to function.run explicitly.
query "workspace/{workspace_id}/repeat-history" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "repeat/history" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $history
  }

  response = {
    repeated_from: $history.repeated_from
    repeated_to  : $history.repeated_to
  }
}
