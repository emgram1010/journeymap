// COP-5 story 01 (rule moved from endpoint 535, PLN-5 US-PLN-5-01) - add someone (or something) to a plan. This is endpoint 535's rule moved, not rewritten: same checks in the same order, same error codes and messages, same events, same write, same response key - so the endpoint and the copilot tool (plan_add_person) add people through one piece of code. Takes `actor` (what planner/resolve_actor returns: user_id, account_id, role) because a function has no $auth, and three has_ flags because a function cannot see what the caller sent: has_daily_capacity_hours, has_color and has_model_id say "this field was sent" (the endpoint asked the raw request body). Colour: when none is given the first palette colour this plan is not using is picked (AGENT_PALETTE order from the planner frontend), wrapping to the first once all eight are used; the "is it taken" test is a nested loop because the contains filter is always false on an array. Model: only an ai agent may carry one (E-PLN-008) and it must be in the caller's account (planner/assert_model, "Model not found"). Capacity: 8 when not sent; when sent it must be more than 0 and at most 24 (E-PLN-009) - so a capacity sent as 0 is refused, not defaulted, exactly as the endpoint does. The new row never has a login (user_id 0). Since 4-C (2026-11-16) endpoint 535 itself calls this function, so this is the only copy of the rule.
function "planner_ops/create_agent" {
  input {
    // What planner/resolve_actor returns: {user_id, account_id, role}.
    json actor
    int workspace_id filters=min:1

    // Optional on purpose (4-C, 2026-11-16): a name of only spaces trims to "", and a REQUIRED
    // input would refuse that with a bare "Missing param" and no event. Optional lets it reach the
    // E-VAL-001 check below, which is what endpoint 535 always answered.
    text name? filters=trim
    enum kind {
      values = ["person", "ai"]
    }

    text color? filters=trim

    // True when the caller sent color at all (replaces the endpoint's raw-body test).
    bool has_color?
    decimal daily_capacity_hours?

    // True when the caller sent daily_capacity_hours at all. False = use 8.
    bool has_daily_capacity_hours?
    int model_id?

    // True when the caller sent model_id at all. False = no model (0).
    bool has_model_id?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/assert_workspace" {
      input = {
        account_id  : $input.actor.account_id
        workspace_id: $input.workspace_id
      }
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived   : $guard.workspace.is_archived
        feature       : "PLN-5"
        step          : "create_agent"
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        user_id       : $input.actor.user_id
        account_id    : $input.actor.account_id
        correlation_id: $input.correlation_id
      }
    }

    var $capacity {
      value = 8
    }

    conditional {
      if ($input.has_daily_capacity_hours == true) {
        var.update $capacity {
          value = $input.daily_capacity_hours
        }
      }
    }

    var $model_id {
      value = 0
    }

    conditional {
      if ($input.has_model_id == true) {
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
          input = {account_id: $input.actor.account_id, model_id: $model_id}
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
      if ($input.has_color == true && $input.color != "") {
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
            user_id       : $input.actor.user_id
            account_id    : $input.actor.account_id
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
        user_id       : $input.actor.user_id
        account_id    : $input.actor.account_id
        entity_type   : "planner_agent"
        entity_id     : $agent.id
        correlation_id: $input.correlation_id
        message       : "Agent added to plan."
      }
    }
  }

  response = {agent: $agent}
}
