// PLAN-2 (US-PLAN-2-02) — Update an agent profile's defaults, or
// toggle eligibility.
//
// WHO MAY DO THIS (gap-fix #2, decision D-2): anyone may change their
// OWN profile; only an account admin may change someone else's or an
// AI profile — including toggling eligibility off.
//
// TOGGLING OFF IS NOT A DELETE. Same rule `planner_agent.is_active`
// and `plan_template.is_active` already follow: history on any plan
// this person is already part of stays intact; they just stop
// appearing in future template rosters.
query "agent-profile/{profile_id}" verb=PATCH {
  api_group = "planner"
  auth = "user"

  input {
    int profile_id filters=min:1
    text name? filters=trim
    text color? filters=trim
    decimal default_daily_capacity_hours?
    bool is_eligible?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_agent_profile" {
      input = {account_id: $actor.account_id, profile_id: $input.profile_id}
    } as $guard

    var $existing {
      value = $guard.profile
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $next_name {
      value = $existing.name
    }

    conditional {
      if ($raw_input|has:"name") {
        var.update $next_name {
          value = $input.name
        }
      }
    }

    var $next_color {
      value = $existing.color
    }

    conditional {
      if ($raw_input|has:"color") {
        var.update $next_color {
          value = $input.color
        }
      }
    }

    var $next_capacity {
      value = $existing.default_daily_capacity_hours
    }

    conditional {
      if ($raw_input|has:"default_daily_capacity_hours") {
        var.update $next_capacity {
          value = $input.default_daily_capacity_hours
        }
      }
    }

    var $next_eligible {
      value = $existing.is_eligible
    }

    conditional {
      if ($raw_input|has:"is_eligible") {
        var.update $next_eligible {
          value = $input.is_eligible
        }
      }
    }

    var $needs_admin {
      value = ($existing.user_id == 0 || $existing.user_id != $actor.user_id)
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($needs_admin == true && $actor.role != "admin") {
        var.update $reject_code {
          value = "E-PLAN-013"
        }

        var.update $reject_msg {
          value = "Only an account admin can change someone else's agent settings or an AI agent. (E-PLAN-013)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $existing.user_id == 0 && ($next_name == null || $next_name == "")) {
        var.update $reject_code {
          value = "E-PLAN-007"
        }

        var.update $reject_msg {
          value = "Give this AI agent a name. (E-PLAN-007)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $next_capacity <= 0) {
        var.update $reject_code {
          value = "E-PLAN-008"
        }

        var.update $reject_msg {
          value = "Daily capacity must be a positive number of hours. (E-PLAN-008)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $next_color != null && $next_color != "" && ("/^#[0-9a-fA-F]{6}$/"|regex_matches:$next_color) == false) {
        var.update $reject_code {
          value = "E-PLAN-009"
        }

        var.update $reject_msg {
          value = "Enter a color like #4f46e5. (E-PLAN-009)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLAN-2"
            step          : "update_profile"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "agent_profile"
            entity_id     : $input.profile_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Agent profile update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.patch agent_profile {
      field_name = "id"
      field_value = $input.profile_id
      data = {
        name                        : $next_name
        color                       : $next_color
        default_daily_capacity_hours: $next_capacity
        is_eligible                 : $next_eligible
        updated_at                  : "now"
      }
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "PLAN-2"
        step          : "update_profile"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "agent_profile"
        entity_id     : $input.profile_id
        correlation_id: $input.correlation_id
        message       : "Agent profile updated."
        metadata      : {is_eligible: $next_eligible}
      }
    }
  }

  response = {profile: $updated}
}
