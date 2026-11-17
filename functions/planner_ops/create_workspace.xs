// COP-5 story 01 - "create a plan": the rule of endpoint 523 (POST /workspace, PLN-3), moved here unchanged so the endpoint and the copilot tool plan_create share one copy. The caller resolves the actor (planner/resolve_actor) and passes it in; a function has no $auth. A function cannot see what the caller sent, so each optional field comes with a has_x flag (true = the caller really sent it; false = use the default: a two-week window from today, 2000 / 500 tokens per minute). Dates are text "YYYY-MM-DD" because an omitted optional date input does not exist at all. Every check sets one reject code and message; there is one place that logs the refusal and one precondition that raises it; the first failing check wins. The unique index on (account_id, name) is still what guarantees the name. name is optional HERE on purpose (4-C): a name of only spaces reaches the endpoint, is trimmed to "" and must get E-VAL-001 with a logged refusal, as it always did; a required input would refuse it with a bare "Missing param: name" and log nothing.
function "planner_ops/create_workspace" {
  input {
    json actor
    text name? filters=trim
    text planning_window_start? filters=trim
    bool has_planning_window_start?
    text planning_window_end? filters=trim
    bool has_planning_window_end?
    int input_tokens_per_minute?
    bool has_input_tokens_per_minute?
    int output_tokens_per_minute?
    bool has_output_tokens_per_minute?
    text correlation_id? filters=trim
  }

  stack {
    // A where clause cannot read a dotted path into the json input, so it is hoisted.
    var $actor_account {
      value = $input.actor.account_id
    }

    // Defaults: a two-week window starting today.
    var $window_start {
      value = now|format_timestamp:"Y-m-d":"UTC"
    }

    conditional {
      if ($input.has_planning_window_start) {
        var.update $window_start {
          value = $input.planning_window_start
        }
      }
    }

    var $window_end {
      value = (now|transform_timestamp:"+13 days":"UTC")|format_timestamp:"Y-m-d":"UTC"
    }

    conditional {
      if ($input.has_planning_window_end) {
        var.update $window_end {
          value = $input.planning_window_end
        }
      }
    }

    // An omitted optional int arrives as 0, which is a legitimate value
    // here, so presence comes from the has_ flag - see CLAUDE.md.
    var $input_rate {
      value = 2000
    }

    conditional {
      if ($input.has_input_tokens_per_minute) {
        var.update $input_rate {
          value = $input.input_tokens_per_minute
        }
      }
    }

    var $output_rate {
      value = 500
    }

    conditional {
      if ($input.has_output_tokens_per_minute) {
        var.update $output_rate {
          value = $input.output_tokens_per_minute
        }
      }
    }

    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $actor_account && $db.planner_workspace.name == $input.name
      return = {type: "count"}
    } as $name_clash

    // --- One verdict, one log, one raise --------------------------------
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
          value = "Give the plan a name. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($input.name|strlen) > 80) {
        var.update $reject_code {
          value = "E-VAL-002"
        }

        var.update $reject_msg {
          value = "That name is too long — 80 characters at most. (E-VAL-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $window_end < $window_start) {
        var.update $reject_code {
          value = "E-PLN-002"
        }

        var.update $reject_msg {
          value = "The end date can't be before the start date. (E-PLN-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($input_rate < 0 || $output_rate < 0)) {
        var.update $reject_code {
          value = "E-PLN-003"
        }

        var.update $reject_msg {
          value = "This has to be zero or more. (E-PLN-003)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $name_clash > 0) {
        var.update $reject_code {
          value = "E-PLN-001"
        }

        var.update $reject_msg {
          value = "You already have a plan with this name. (E-PLN-001)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-3"
            step          : "create_workspace"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $input.actor.user_id
            account_id    : $input.actor.account_id
            entity_type   : "planner_workspace"
            entity_id     : 0
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Create refused."
            duration_ms   : 0
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.add planner_workspace {
      data = {
        account_id              : $input.actor.account_id
        created_by              : $input.actor.user_id
        name                    : $input.name
        planning_window_start   : $window_start
        planning_window_end     : $window_end
        input_tokens_per_minute : $input_rate
        output_tokens_per_minute: $output_rate
        is_archived             : false
        plan_template_id        : 0
      }
    } as $workspace

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-3"
        step          : "create_workspace"
        outcome       : "success"
        severity      : "info"
        user_id       : $input.actor.user_id
        account_id    : $input.actor.account_id
        entity_type   : "planner_workspace"
        entity_id     : $workspace.id
        correlation_id: $input.correlation_id
        error_code    : ""
        message       : "Plan created."
        duration_ms   : 0
      }
    }
  }

  response = {
    workspace: $workspace
    counts   : {agent_count: 0, timeline_count: 0, task_count: 0, backlog_count: 0}
  }
}
