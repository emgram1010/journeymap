// PLAN-2 (US-PLAN-2-02) — Tag a user as an agent, or create an AI
// profile with no login.
//
// WHO MAY DO THIS (gap-fix #2, decision D-2): anyone may tag
// THEMSELVES; only an account admin may tag someone else or create an
// AI profile. Without this, any member could set up — or, via the
// PATCH endpoint, untag — a teammate.
//
// AT MOST ONE PROFILE PER REAL USER, enforced by a count check here,
// not a DB-level unique index — same reason `plan_template`'s unique
// name isn't a DB constraint either: an int column can't hold a real
// null, so a unique index on `user_id` would reject every second AI
// profile (they all share user_id = 0).
query "agent-profile" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int user_id? filters=min:0
    text name? filters=trim
    text color? filters=trim
    decimal default_daily_capacity_hours?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $target_user_id {
      value = 0
    }

    conditional {
      if ($raw_input|has:"user_id") {
        var.update $target_user_id {
          value = $input.user_id
        }
      }
    }

    var $kind {
      value = "ai"
    }

    conditional {
      if ($target_user_id != 0) {
        var.update $kind {
          value = "person"
        }
      }
    }

    var $capacity {
      value = 8
    }

    conditional {
      if ($raw_input|has:"default_daily_capacity_hours") {
        var.update $capacity {
          value = $input.default_daily_capacity_hours
        }
      }
    }

    // Tenancy check on the target user, for a person profile — same
    // "not found" shape as every other cross-account guard.
    var $target_user {
      value = null
    }

    conditional {
      if ($target_user_id != 0) {
        db.get user {
          field_name = "id"
          field_value = $target_user_id
        } as $target_user
      }
    }

    var $target_belongs {
      value = ($target_user_id == 0 || ($target_user != null && $target_user.account_id == $actor.account_id))
    }

    var $existing_count {
      value = 0
    }

    conditional {
      if ($target_user_id != 0) {
        db.query agent_profile {
          where = $db.agent_profile.user_id == $target_user_id
          return = {type: "count"}
        } as $existing_count
      }
    }

    var $needs_admin {
      value = ($target_user_id == 0 || $target_user_id != $actor.user_id)
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($target_belongs == false) {
        var.update $reject_code {
          value = "E-PLAN-011"
        }

        var.update $reject_msg {
          value = "That user isn't on this account. (E-PLAN-011)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $needs_admin == true && $actor.role != "admin") {
        var.update $reject_code {
          value = "E-PLAN-013"
        }

        var.update $reject_msg {
          value = "Only an account admin can set up agents for other people or add an AI agent. You can tag yourself. (E-PLAN-013)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $target_user_id != 0 && $existing_count > 0) {
        var.update $reject_code {
          value = "E-PLAN-006"
        }

        var.update $reject_msg {
          value = "This person is already set up as an agent. (E-PLAN-006)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $target_user_id == 0 && ($input.name == null || $input.name == "")) {
        var.update $reject_code {
          value = "E-PLAN-007"
        }

        var.update $reject_msg {
          value = "Give this AI agent a name. (E-PLAN-007)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $capacity <= 0) {
        var.update $reject_code {
          value = "E-PLAN-008"
        }

        var.update $reject_msg {
          value = "Daily capacity must be a positive number of hours. (E-PLAN-008)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.color != null && $input.color != "" && ("/^#[0-9a-fA-F]{6}$/"|regex_matches:$input.color) == false) {
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
            step          : "create_profile"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "agent_profile"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Agent profile create refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $profile_account_id {
      value = 0
    }

    conditional {
      if ($target_user_id == 0) {
        var.update $profile_account_id {
          value = $actor.account_id
        }
      }
    }

    db.add agent_profile {
      data = {
        user_id                     : $target_user_id
        account_id                  : $profile_account_id
        kind                        : $kind
        name                        : $input.name
        color                       : $input.color
        default_daily_capacity_hours: $capacity
        is_eligible                 : true
      }
    } as $profile

    function.run "ops/log_event" {
      input = {
        feature       : "PLAN-2"
        step          : "create_profile"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "agent_profile"
        entity_id     : $profile.id
        correlation_id: $input.correlation_id
        message       : "Agent profile created."
        metadata      : {kind: $kind}
      }
    }
  }

  response = {profile: $profile}
}
