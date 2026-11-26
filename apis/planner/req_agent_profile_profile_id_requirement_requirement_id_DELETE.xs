// REQ-1 story 02 — Remove a holding: the person no longer holds it. ADMIN PERSON ONLY (a member is refused E-USR-001; an AI identity is refused and logged E-COP-025). Another account's profile or requirement is "not found". Removing something that is not held is not an error (the answer says removed: false). Who removed it, and when, is recorded: holding.removed carries the profile, the requirement, the end date it had, and the actor. The row is deleted by its own id. Every input is passed to function.run explicitly.
query "agent-profile/{agent_profile_id}/requirement/{requirement_id}" verb=DELETE {
  api_group = "planner"
  auth = "user"

  input {
    int agent_profile_id filters=min:1
    int requirement_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "copilot/assert_person_only" {
      input = {user_id: $actor.user_id, account_id: $actor.account_id, step: "holding_remove", entity_type: "agent_profile", entity_id: $input.agent_profile_id}
    } as $_person_only

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "holding/remove", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "planner/assert_agent_profile" {
      input = {account_id: $actor.account_id, profile_id: $input.agent_profile_id}
    } as $profile_guard

    function.run "req/assert_requirement" {
      input = {account_id: $actor.account_id, requirement_id: $input.requirement_id}
    } as $req_guard

    db.query agent_profile_requirement {
      where = $db.agent_profile_requirement.agent_profile_id == $input.agent_profile_id && $db.agent_profile_requirement.requirement_id == $input.requirement_id
      return = {type: "single"}
    } as $row

    var $row_id {
      value = $row|get:"id":0
    }

    var $had_until {
      value = $row|get:"held_until":""
    }

    conditional {
      if ($row_id != 0) {
        db.del agent_profile_requirement {
          field_name = "id"
          field_value = $row_id
        }

        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "holding.removed"
            outcome       : "success"
            severity      : "info"
            error_code    : ""
            message       : "A holding was removed."
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "agent_profile"
            entity_id     : $input.agent_profile_id
            correlation_id: $input.correlation_id
            metadata      : {requirement_id: $input.requirement_id, requirement: $req_guard.requirement.name, held_until: $had_until, actor: $actor.user_id}
          }
        } as $_logged
      }
    }
  }

  response = {agent_profile_id: $input.agent_profile_id, requirement_id: $input.requirement_id, removed: ($row_id != 0)}
}
