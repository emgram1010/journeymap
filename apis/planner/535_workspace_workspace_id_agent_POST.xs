// PLN-5 (US-PLN-5-01) — Add someone (or something) to a plan.
//
// COLOUR: if none is given, the next unused palette colour is picked,
// so a plan's first eight agents are visually distinct without anyone
// choosing. Once all eight are used it wraps to the first — a repeat
// is better than a blank or a random colour nobody can read.
// The palette is AGENT_PALETTE from the planner frontend, kept in the
// same order so the server's choice matches what the UI would show.
//
// The "is this colour taken?" test is a nested loop, NOT `|contains:`.
// `|contains:` returns false for every array, present or absent
// (confirmed live) — the first version of this endpoint used it and
// handed every new agent the same colour. See CLAUDE.md.
//
// MODEL: only an `ai` agent may carry one, because the model is purely
// a token-cost input and a person has no tokens. A `person` sent with
// a model is rejected rather than silently stripped — it means the
// caller has the wrong idea about the row it is creating.
// Tenancy on the model goes through planner/assert_model, so a model
// from another account is "not found", not "forbidden".
query "workspace/{workspace_id}/agent" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text name filters=trim
    enum kind {
      values = ["person", "ai"]
    }

    text color? filters=trim
    decimal daily_capacity_hours?
    int model_id?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {
        account_id  : $actor.account_id
        workspace_id: $input.workspace_id
      }
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-5"
        step       : "create_agent"
        entity_type: "planner_workspace"
        entity_id  : $input.workspace_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $capacity {
      value = 8
    }

    conditional {
      if ($raw_input|has:"daily_capacity_hours") {
        var.update $capacity {
          value = $input.daily_capacity_hours
        }
      }
    }

    var $model_id {
      value = 0
    }

    conditional {
      if ($raw_input|has:"model_id") {
        var.update $model_id {
          value = $input.model_id
        }
      }
    }

    // Tenancy on the model is checked before anything is written, and
    // only when one was actually asked for.
    conditional {
      if ($model_id != 0) {
        function.run "planner/assert_model" {
          input = {account_id: $actor.account_id, model_id: $model_id}
        } as $model_guard
      }
    }

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id && $db.planner_agent.name == $input.name
      return = {type: "count"}
    } as $name_clash

    // --- Colour: first palette entry this plan is not already using ---
    var $palette {
      value = [
        "#475569"
        "#0d9488"
        "#c2410c"
        "#b45309"
        "#7c3aed"
        "#059669"
        "#0284c7"
        "#9f1239"
      ]
    }

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $existing_agents

    var $color {
      value = $palette|first
    }

    var $picked {
      value = false
    }

    var $is_used {
      value = false
    }

    foreach ($palette) {
      each as $p {
        conditional {
          if ($picked == false) {
            var.update $is_used {
              value = false
            }

            foreach ($existing_agents) {
              each as $a {
                conditional {
                  if ($a.color == $p) {
                    var.update $is_used {
                      value = true
                    }
                  }
                }
              }
            }

            conditional {
              if ($is_used == false) {
                var.update $color {
                  value = $p
                }

                var.update $picked {
                  value = true
                }
              }
            }
          }
        }
      }
    }

    conditional {
      if (($raw_input|has:"color") && $input.color != "") {
        var.update $color {
          value = $input.color
        }
      }
    }

    // --- One verdict, one log, one raise ------------------------------
    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($input.name == null || $input.name == "") {
        var.update $reject_code {
          value = "E-VAL-001"
        }

        var.update $reject_msg {
          value = "Give this person or agent a name. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($input.name|strlen) > 60) {
        var.update $reject_code {
          value = "E-VAL-002"
        }

        var.update $reject_msg {
          value = "That name is too long — 60 characters at most. (E-VAL-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($capacity <= 0 || $capacity > 24)) {
        var.update $reject_code {
          value = "E-PLN-009"
        }

        var.update $reject_msg {
          value = "Daily capacity has to be more than 0 and no more than 24 hours. (E-PLN-009)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.kind == "person" && $model_id != 0) {
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
            step          : "create_agent"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_agent"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Agent create refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.add planner_agent {
      data = {
        workspace_id        : $input.workspace_id
        name                : $input.name
        kind                : $input.kind
        color               : $color
        daily_capacity_hours: $capacity
        is_visible          : true
        model_id            : $model_id
        user_id             : 0
        is_active           : true
      }
    } as $agent

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-5"
        step          : "create_agent"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_agent"
        entity_id     : $agent.id
        correlation_id: $input.correlation_id
        message       : "Agent added to plan."
      }
    }
  }

  response = {agent: $agent}
}
