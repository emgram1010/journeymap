// PLN-5 (US-PLN-5-02, US-PLN-5-03) — Edit one agent, including hiding
// or showing them.
//
// A RENAME TOUCHES ONLY THIS ROW. That is the whole point of PLN-1's
// normalization: the old localStorage planner stored the assignee's
// name on every timeline and task, so renaming someone rewrote dozens
// of rows. Here nothing else is written, and a hydrated read (PLN-8)
// picks up the new name through the foreign key. Verified live by
// snapshotting the agent's timelines before and after a rename — the
// rows came back byte-identical.
//
// AI → PERSON CLEARS THE MODEL in the same write. Leaving a stale
// model_id on a person would be an invisible inconsistency: nothing
// reads it for a person, so it would sit there until something else
// tripped over it. PERSON → AI is allowed without a model — the UI
// simply shows no cost until one is chosen (US-PLN-5-02).
//
// APP-1 (US-APP-1-01) adds `user_id`: which login performs this
// agent's work. 0 clears the link — an agent without one simply
// cannot appear in `perform/today` for anyone, which is the whole
// enforcement (nothing else needs to check it). ONE LOGIN PER AGENT
// PER PLAN, checked here rather than with a unique index: an int
// column can't hold a real null, so a unique index on (workspace_id,
// user_id) would reject every second login-less agent (see CLAUDE.md
// on nullable FKs) — exactly the same shape as the `name` clash check
// just below, done the same way.
query "agent/{agent_id}" verb=PATCH {
  api_group = "planner"
  auth = "user"

  input {
    int agent_id filters=min:1
    text name? filters=trim
    enum kind? {
      values = ["person", "ai"]
    }

    text color? filters=trim
    decimal daily_capacity_hours?
    int model_id?
    bool is_visible?
    int user_id?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_agent" {
      input = {account_id: $actor.account_id, agent_id: $input.agent_id}
    } as $guard

    var $existing {
      value = $guard.agent
    }

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-5"
        step       : "update_agent"
        entity_type: "planner_agent"
        entity_id  : $input.agent_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
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

    var $next_kind {
      value = $existing.kind
    }

    conditional {
      if ($raw_input|has:"kind") {
        var.update $next_kind {
          value = $input.kind
        }
      }
    }

    var $next_color {
      value = $existing.color
    }

    conditional {
      if (($raw_input|has:"color") && $input.color != "") {
        var.update $next_color {
          value = $input.color
        }
      }
    }

    var $next_capacity {
      value = $existing.daily_capacity_hours
    }

    conditional {
      if ($raw_input|has:"daily_capacity_hours") {
        var.update $next_capacity {
          value = $input.daily_capacity_hours
        }
      }
    }

    var $next_visible {
      value = $existing.is_visible
    }

    conditional {
      if ($raw_input|has:"is_visible") {
        var.update $next_visible {
          value = $input.is_visible
        }
      }
    }

    var $next_model {
      value = $existing.model_id
    }

    conditional {
      if ($raw_input|has:"model_id") {
        var.update $next_model {
          value = $input.model_id
        }
      }
    }

    // Becoming a person drops the model, whatever was sent.
    conditional {
      if ($next_kind == "person") {
        var.update $next_model {
          value = 0
        }
      }
    }

    conditional {
      if ($next_model != 0) {
        function.run "planner/assert_model" {
          input = {account_id: $actor.account_id, model_id: $next_model}
        } as $model_guard
      }
    }

    // APP-1 (US-APP-1-01).
    var $next_user {
      value = $existing.user_id
    }

    conditional {
      if ($raw_input|has:"user_id") {
        var.update $next_user {
          value = $input.user_id
        }
      }
    }

    // No conditional needed: ids start at 1, so a lookup for id 0 (the
    // "no link" sentinel) naturally returns null — the same answer a
    // conditional guard would have produced, without depending on an
    // `as` var's visibility outside a branch.
    db.get user {
      field_name = "id"
      field_value = $next_user
    } as $linked_user

    // Guarded by `$next_user != 0` IN the where clause (not a separate
    // conditional around the query) — 0 means "no link", and plenty of
    // other agents legitimately also have 0, which must never count as
    // a clash. A plain var computed earlier is fine inside a where
    // clause; it compiles to SQL (CLAUDE.md).
    db.query planner_agent {
      where = $next_user != 0 && $db.planner_agent.workspace_id == $existing.workspace_id && $db.planner_agent.user_id == $next_user && $db.planner_agent.id != $input.agent_id
      return = {type: "count"}
    } as $user_clash

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $existing.workspace_id && $db.planner_agent.name == $next_name && $db.planner_agent.id != $input.agent_id
      return = {type: "count"}
    } as $name_clash

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($next_name == null || $next_name == "") {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Give this person or agent a name. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_name|strlen) > 60) {
        var.update $reject_code {
          value = "E-VAL-002"
        }

        var.update $reject_msg {
          value = "That name is too long — 60 characters at most. (E-VAL-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_capacity <= 0 || $next_capacity > 24)) {
        var.update $reject_code {
          value = "E-PLN-009"
        }

        var.update $reject_msg {
          value = "Daily capacity has to be more than 0 and no more than 24 hours. (E-PLN-009)"
        }
      }
    }

    // Only reachable when the caller explicitly sent a model AND kept
    // the agent a person — the clearing rule above handles the switch.
    conditional {
      if ($reject_code == "" && $next_kind == "person" && ($raw_input|has:"model_id") && $input.model_id != 0) {
        var.update $reject_code {
          value = "E-PLN-008"
        }

        var.update $reject_msg {
          value = "Only AI agents can have a model. (E-PLN-008)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $name_clash > 0) {
        var.update $reject_code {
          value = "E-PLN-007"
        }

        var.update $reject_msg {
          value = "This plan already has someone with that name. (E-PLN-007)"
        }
      }
    }

    // APP-1 (US-APP-1-01). Tenancy first (does this login even belong
    // here), then uniqueness (one login, one agent, per plan).
    conditional {
      if ($reject_code == "" && $next_user != 0 && ($linked_user == null || $linked_user.account_id != $actor.account_id)) {
        var.update $reject_code {
          value = "E-PLN-010"
        }

        var.update $reject_msg {
          value = "That login doesn't belong to this account. (E-PLN-010)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $user_clash > 0) {
        var.update $reject_code {
          value = "E-PLN-011"
        }

        var.update $reject_msg {
          value = "That login is already linked to someone else in this plan. (E-PLN-011)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-5"
            step          : "update_agent"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_agent"
            entity_id     : $input.agent_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Agent update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.patch planner_agent {
      field_name = "id"
      field_value = $input.agent_id
      data = {
        name                : $next_name
        kind                : $next_kind
        color               : $next_color
        daily_capacity_hours: $next_capacity
        is_visible          : $next_visible
        model_id            : $next_model
        user_id             : $next_user
        updated_at          : "now"
      }
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-5"
        step          : "update_agent"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_agent"
        entity_id     : $input.agent_id
        correlation_id: $input.correlation_id
        message       : "Agent updated."
      }
    }
  }

  response = {agent: $updated}
}
