// REQ-1 story 01 — Archive a requirement, or restore it. Admin only. Archived means it can no longer be newly picked for a step or a person; it still shows wherever it is already used, and nothing that uses it changes. Takes `is_archived` (required) rather than being a one-way action, so restoring is possible (the same shape as plan archive). Events: requirement.archived / requirement.restored. Every input is passed to function.run explicitly.
query "requirement/{requirement_id}/archive" verb=POST {
  api_group = "catalog"
  auth = "user"

  input {
    int requirement_id filters=min:1
    bool is_archived
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "requirement/archive", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "req/assert_requirement" {
      input = {account_id: $actor.account_id, requirement_id: $input.requirement_id}
    } as $guard

    var $now_active {
      value = ($input.is_archived == false)
    }

    db.patch requirement {
      field_name = "id"
      field_value = $input.requirement_id
      data = {is_active: $now_active, updated_at: "now"}
    } as $updated

    var $step {
      value = (($input.is_archived == true) ? "requirement.archived" : "requirement.restored")
    }

    function.run "ops/log_event" {
      input = {
        feature       : "REQ-1"
        step          : $step
        outcome       : "success"
        severity      : "info"
        error_code    : ""
        message       : "A requirement was archived or restored."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "requirement"
        entity_id     : $input.requirement_id
        correlation_id: $input.correlation_id
        metadata      : {name: $guard.requirement.name}
      }
    } as $_logged
  }

  response = {requirement: $updated}
}
