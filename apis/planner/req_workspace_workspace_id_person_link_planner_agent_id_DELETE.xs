// REQ-1 story 03 — Clear a person's link to their lasting profile. ADMIN PERSON ONLY (a member is refused E-USR-001; an AI identity E-COP-025). The plan is the caller's, the person is on that plan, and the link row is deleted by its own id. Clearing a link that does not exist is not an error (removed: false). The person then holds nothing as far as the system can tell, and the plan's list shows "No profile" again. Event: plan_person.unlinked, with who. Every input is passed to function.run explicitly.
query "workspace/{workspace_id}/person-link/{planner_agent_id}" verb=DELETE {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    int planner_agent_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "copilot/assert_person_only" {
      input = {user_id: $actor.user_id, account_id: $actor.account_id, step: "person_unlink", entity_type: "planner_agent", entity_id: $input.planner_agent_id}
    } as $_person_only

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "person_link/clear", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    db.query planner_agent {
      where = $db.planner_agent.id == $input.planner_agent_id && $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "single"}
    } as $agent

    var $agent_id {
      value = $agent|get:"id":0
    }

    precondition ($agent_id != 0) {
      error_type = "notfound"
      error = "That person is not on this plan."
    }

    db.query planner_agent_profile {
      where = $db.planner_agent_profile.planner_agent_id == $input.planner_agent_id
      return = {type: "single"}
    } as $link

    var $link_id {
      value = $link|get:"id":0
    }

    var $was_profile {
      value = $link|get:"agent_profile_id":0
    }

    conditional {
      if ($link_id != 0) {
        db.del planner_agent_profile {
          field_name = "id"
          field_value = $link_id
        }

        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "plan_person.unlinked"
            outcome       : "success"
            severity      : "info"
            error_code    : ""
            message       : "A person on a plan was untied from their lasting profile."
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_agent"
            entity_id     : $input.planner_agent_id
            correlation_id: $input.correlation_id
            metadata      : {was_profile_id: $was_profile, workspace_id: $input.workspace_id}
          }
        } as $_logged
      }
    }
  }

  response = {planner_agent_id: $input.planner_agent_id, removed: ($link_id != 0)}
}
