// REQ-1 story 03 — Tie a person on a plan to a lasting profile by hand (an admin confirms each one: nothing is ever linked by name on its own). ADMIN PERSON ONLY: a member is refused (usr/assert_team_admin, E-USR-001), an AI identity is refused and logged (copilot/assert_person_only, E-COP-025). The person must be on THIS plan, and the plan and the profile must both belong to the caller's account: a profile from another account is "not found", the same answer as one that does not exist. Linking again replaces the old link. The write is req/link_person; the event plan_person.linked says who and how ("hand"). Every input is passed to function.run explicitly.
query "workspace/{workspace_id}/person-link" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    int planner_agent_id filters=min:1
    int agent_profile_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "copilot/assert_person_only" {
      input = {user_id: $actor.user_id, account_id: $actor.account_id, step: "person_link", entity_type: "planner_agent", entity_id: $input.planner_agent_id}
    } as $_person_only

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "person_link/set", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived   : $guard.workspace.is_archived
        feature       : "REQ-1"
        step          : "person_link"
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        correlation_id: $input.correlation_id
      }
    }

    function.run "planner/assert_agent_profile" {
      input = {account_id: $actor.account_id, profile_id: $input.agent_profile_id}
    } as $profile_guard

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

    function.run "req/link_person" {
      input = {account_id: $actor.account_id, planner_agent_id: $input.planner_agent_id, agent_profile_id: $input.agent_profile_id, how: "hand", user_id: $actor.user_id}
    } as $linked

    function.run "ops/log_event" {
      input = {
        feature       : "REQ-1"
        step          : "plan_person.linked"
        outcome       : "success"
        severity      : "info"
        error_code    : ""
        message       : "A person on a plan was tied to a lasting profile."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_agent"
        entity_id     : $input.planner_agent_id
        correlation_id: $input.correlation_id
        metadata      : {how: "hand", agent_profile_id: $input.agent_profile_id, result: $linked.result, workspace_id: $input.workspace_id}
      }
    } as $_logged
  }

  response = {planner_agent_id: $input.planner_agent_id, agent_profile_id: $input.agent_profile_id, result: $linked.result}
}
