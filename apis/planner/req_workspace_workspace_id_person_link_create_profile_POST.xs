// REQ-1 story 03 — Make a lasting profile FOR a person on a plan, and tie them to it, in one click. Needed because most people on plans were typed in or copied without ever being tagged as an agent (the founder's own account: 12 of 17 people had no profile, and a login can only find a profile that exists). ADMIN PERSON ONLY (a member is refused E-USR-001; an AI identity E-COP-025). A person WITH a login gets a profile for that login (name left empty: a person's display name comes from the login); a person with NO login (an AI, or one added by hand) gets a profile named after them. If the login ALREADY has a profile, no second one is made: the person is tied to the existing one (at most one profile per real user, the PLAN-2 rule, checked by count here). The profile copies the person's colour and daily hours. It never matches or merges by name. Events: plan_person.linked (how "created") and the profile's own create event. Every input is passed to function.run explicitly.
query "workspace/{workspace_id}/person-link/create-profile" verb=POST {
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
      input = {user_id: $actor.user_id, account_id: $actor.account_id, step: "person_create_profile", entity_type: "planner_agent", entity_id: $input.planner_agent_id}
    } as $_person_only

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "person_link/create_profile", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived   : $guard.workspace.is_archived
        feature       : "REQ-1"
        step          : "person_create_profile"
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        correlation_id: $input.correlation_id
      }
    }

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

    var $login_id {
      value = $agent|get:"user_id":0
    }

    // A login must belong to the caller's own account.
    var $login_ok {
      value = true
    }

    conditional {
      if ($login_id != 0) {
        db.query user {
          where = $db.user.id == $login_id && $db.user.account_id == $actor.account_id
          return = {type: "count"}
        } as $login_in_account

        var.update $login_ok {
          value = ($login_in_account == 1)
        }
      }
    }

    precondition ($login_ok == true) {
      error_type = "notfound"
      error = "That person's login is not in this account."
    }

    db.query agent_profile {
      where = $db.agent_profile.user_id == $login_id
      return = {type: "single"}
    } as $existing_profile

    var $existing_id {
      value = ($login_id != 0) ? ($existing_profile|get:"id":0) : 0
    }

    var $profile_id {
      value = $existing_id
    }

    var $made_new {
      value = false
    }

    var $profile_name {
      value = (($login_id != 0) ? "" : ($agent|get:"name":""))
    }

    conditional {
      if ($existing_id == 0) {
        db.add agent_profile {
          data = {
            user_id                     : $login_id
            account_id                  : $actor.account_id
            kind                        : $agent.kind
            name                        : $profile_name
            color                       : $agent.color
            default_daily_capacity_hours: $agent.daily_capacity_hours
            is_eligible                 : true
          }
        } as $new_profile

        var.update $profile_id {
          value = $new_profile.id
        }

        var.update $made_new {
          value = true
        }
      }
    }

    function.run "req/link_person" {
      input = {account_id: $actor.account_id, planner_agent_id: $input.planner_agent_id, agent_profile_id: $profile_id, how: "created", user_id: $actor.user_id}
    } as $linked

    function.run "ops/log_event" {
      input = {
        feature       : "REQ-1"
        step          : "plan_person.linked"
        outcome       : "success"
        severity      : "info"
        error_code    : ""
        message       : "A profile was made for a person on a plan, and they were tied to it."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_agent"
        entity_id     : $input.planner_agent_id
        correlation_id: $input.correlation_id
        metadata      : {how: "created", agent_profile_id: $profile_id, made_new_profile: $made_new, workspace_id: $input.workspace_id}
      }
    } as $_logged
  }

  response = {planner_agent_id: $input.planner_agent_id, agent_profile_id: $profile_id, made_new_profile: $made_new}
}
