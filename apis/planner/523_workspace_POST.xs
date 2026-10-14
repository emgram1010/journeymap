// PLN-3 (US-PLN-3-01) — Create a plan.
//
// `account_id` and `created_by` come from the signed-in user and are
// never read from the request body. FT-PLN-3-02 sends an `account_id`
// deliberately; it is not even declared as an input, so it is ignored.
//
// VALIDATION SHAPE: every check sets a reject code and message rather
// than throwing where it stands. That way there is exactly ONE place
// that logs the rejection and ONE precondition that raises it, so no
// refusal can ever go unlogged — OBS-1's "never fail silently" rule.
// The first failing check wins; later checks are skipped by the
// `$reject_code == ""` guard, so the user sees one clear reason.
//
// The duplicate-name check runs before the insert purely so the user
// gets a sentence instead of a database error. The unique index on
// (account_id, name) is still the thing that actually guarantees it.
query "workspace" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    text name filters=trim
    date planning_window_start?
    date planning_window_end?
    int input_tokens_per_minute?
    int output_tokens_per_minute?
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

    // Defaults: a two-week window starting today.
    var $window_start {
      value = now|format_timestamp:"Y-m-d":"UTC"
    }

    conditional {
      if ($raw_input|has:"planning_window_start") {
        var.update $window_start {
          value = $input.planning_window_start
        }
      }
    }

    var $window_end {
      value = (now|transform_timestamp:"+13 days":"UTC")|format_timestamp:"Y-m-d":"UTC"
    }

    conditional {
      if ($raw_input|has:"planning_window_end") {
        var.update $window_end {
          value = $input.planning_window_end
        }
      }
    }

    // An omitted optional int arrives as 0, which is a legitimate value
    // here, so presence is read from the raw body — see CLAUDE.md.
    var $input_rate {
      value = 2000
    }

    conditional {
      if ($raw_input|has:"input_tokens_per_minute") {
        var.update $input_rate {
          value = $input.input_tokens_per_minute
        }
      }
    }

    var $output_rate {
      value = 500
    }

    conditional {
      if ($raw_input|has:"output_tokens_per_minute") {
        var.update $output_rate {
          value = $input.output_tokens_per_minute
        }
      }
    }

    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $actor.account_id && $db.planner_workspace.name == $input.name
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
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_workspace"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Create refused."
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
        account_id              : $actor.account_id
        created_by              : $actor.user_id
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
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_workspace"
        entity_id     : $workspace.id
        correlation_id: $input.correlation_id
        message       : "Plan created."
      }
    }
  }

  response = {
    workspace: $workspace
    counts   : {agent_count: 0, timeline_count: 0, task_count: 0, backlog_count: 0}
  }
}
