// REQ-1 story 01 — Delete a requirement that nothing uses. Admin only. Refused while a step needs it, a person holds it, or a published version froze it (E-REQ-004): the answer says how many places use it and offers archive instead. Counted by query (req/usage), never by loading rows. Allowed only when it is used nowhere; the row is deleted by its own id. Events: requirement.deleted (and a rejected event for a refusal). Another account's requirement is "not found" (E-REQ-006). Every input is passed to function.run explicitly.
query "requirement/{requirement_id}" verb=DELETE {
  api_group = "catalog"
  auth = "user"

  input {
    int requirement_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "requirement/delete", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "req/assert_requirement" {
      input = {account_id: $actor.account_id, requirement_id: $input.requirement_id}
    } as $guard

    function.run "req/usage" {
      input = {requirement_id: $input.requirement_id}
    } as $use

    var $in_use_msg {
      value = "It is used in " ~ ($use.steps|to_text) ~ " step(s), held by " ~ ($use.people|to_text) ~ " person(s) and frozen in " ~ ($use.versions|to_text) ~ " published version(s), so it can't be deleted. Archive it instead. (E-REQ-004)"
    }

    conditional {
      if ($use.total > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "requirement.delete"
            outcome       : "rejected"
            severity      : "info"
            error_code    : "E-REQ-004"
            message       : $in_use_msg
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "requirement"
            entity_id     : $input.requirement_id
            correlation_id: $input.correlation_id
          }
        } as $_logged_reject
      }
    }

    precondition ($use.total == 0) {
      error_type = "inputerror"
      error = $in_use_msg
    }

    db.del requirement {
      field_name = "id"
      field_value = $input.requirement_id
    }

    function.run "ops/log_event" {
      input = {
        feature       : "REQ-1"
        step          : "requirement.deleted"
        outcome       : "success"
        severity      : "warn"
        error_code    : ""
        message       : "A requirement was deleted."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "requirement"
        entity_id     : $input.requirement_id
        correlation_id: $input.correlation_id
        metadata      : {name: $guard.requirement.name}
      }
    } as $_logged
  }

  response = {deleted_requirement_id: $input.requirement_id}
}
