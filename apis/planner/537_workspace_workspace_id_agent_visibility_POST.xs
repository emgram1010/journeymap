// PLN-5 (US-PLN-5-03) — Show all / hide all, in one call.
//
// The popover's "show all" and "hide all" buttons would otherwise be N
// separate PATCHes from the browser, which is both slow and
// non-atomic: a half-applied "hide all" leaves the roster in a state
// nobody asked for.
//
// ⚠️ IT LOOPS, AND IT HAS TO. `db.patch` with field_name/field_value
// updates only the FIRST matching row, not every match — confirmed
// live: the first version of this endpoint patched by `workspace_id`
// and flipped exactly one of six agents, silently reporting success.
// There is no "patch where" form, so the only correct way to write
// many rows is to read them and patch each by id. See CLAUDE.md.
//
// The whole loop is one `db.transaction`, so "hide all" either applies
// to everyone or to nobody.
//
// Visibility is presentation only. Nothing else is touched — no
// timeline, no task, no assignment — so hiding is always safe and
// always reversible. FT-PLN-5-06 checks exactly that.
query "workspace/{workspace_id}/agent/visibility" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    bool visible
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-5"
        step       : "bulk_visibility"
        entity_type: "planner_workspace"
        entity_id  : $input.workspace_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $to_change

    db.transaction {
      stack {
        foreach ($to_change) {
          each as $a {
            db.patch planner_agent {
              field_name = "id"
              field_value = $a.id
              data = {is_visible: $input.visible, updated_at: "now"}
            } as $patched
          }
        }
      }
    }

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      sort = {planner_agent.created_at: "asc", planner_agent.id: "asc"}
      return = {type: "list"}
    } as $agents

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-5"
        step          : "bulk_visibility"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        correlation_id: $input.correlation_id
        message       : "Agent visibility changed for the whole plan."
        metadata      : {agents_changed: ($to_change|count)}
      }
    }
  }

  response = {agents: $agents}
}
