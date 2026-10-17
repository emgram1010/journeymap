// PLN-3 / P3A-1 (US-P3A-1-02) — Archive or restore a plan.
//
// Archiving is what the product does instead of deleting once a plan
// has work recorded against it: the plan drops out of the default list
// and stops accepting edits, and everything recorded against it stays
// exactly where it is.
//
// Deliberately takes `is_archived` rather than being a one-way
// /archive action, so restoring is possible. A one-way archive would be
// a second kind of delete.
//
// This endpoint is the ONE write that is still allowed on an archived
// plan — otherwise a plan could be archived and never brought back.
query "workspace/{workspace_id}/archive" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    bool is_archived
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    db.patch planner_workspace {
      field_name = "id"
      field_value = $input.workspace_id
      data = {is_archived: $input.is_archived, updated_at: "now"}
    } as $updated

    var $step {
      value = "archive_workspace"
    }

    conditional {
      if ($input.is_archived == false) {
        var.update $step {
          value = "restore_workspace"
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "P3A-1"
        step          : $step
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        correlation_id: $input.correlation_id
        message       : "Plan archive flag changed."
      }
    }
  }

  response = {workspace: $updated}
}
