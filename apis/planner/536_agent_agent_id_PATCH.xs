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
