// PLN-3 (US-PLN-3-03) — Update a plan. Any subset of the fields.
//
// THE RULE THAT MATTERS: every check runs against the MERGED result,
// not against what was sent. Sending only `planning_window_start` must
// still be compared to the END ALREADY STORED, or a one-field edit can
// quietly invert the window. Each field below is therefore resolved to
// "the value this plan will have after this save" before anything is
// validated. FT-PLN-3-04 sends exactly that case.
//
// Presence comes from the raw body, never from the typed input: an
// omitted optional int arrives as 0 and an omitted optional text as "",
// both of which are legitimate values here, so `$input.x != null` would
// be wrong in both directions (CLAUDE.md).
//
// Validation uses the same one-verdict/one-log/one-raise shape as the
// create endpoint, so no refusal goes unlogged (OBS-1).
//
// P3A-1 (US-P3A-1-02): an archived plan is read-only. Un-archiving is
// the separate /archive endpoint, so it stays possible.
//
// Shrinking the window deliberately does NOT touch timelines. They
// simply read as out-of-window in the UI (PLN-9). Moving a date must
// never delete or move someone's work.
query "workspace/{workspace_id}" verb=PATCH {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text name? filters=trim
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

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    var $existing {
      value = $guard.workspace
    }

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $existing.is_archived
        feature    : "PLN-3"
        step       : "update_workspace"
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

    // --- Resolve every field to its post-save value -------------------
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

    var $next_start {
      value = $existing.planning_window_start
    }

    conditional {
      if ($raw_input|has:"planning_window_start") {
        var.update $next_start {
          value = $input.planning_window_start
        }
      }
    }

    var $next_end {
      value = $existing.planning_window_end
    }

    conditional {
      if ($raw_input|has:"planning_window_end") {
        var.update $next_end {
          value = $input.planning_window_end
        }
      }
    }

    var $next_input_rate {
      value = $existing.input_tokens_per_minute
    }

    conditional {
      if ($raw_input|has:"input_tokens_per_minute") {
        var.update $next_input_rate {
          value = $input.input_tokens_per_minute
        }
      }
    }

    var $next_output_rate {
      value = $existing.output_tokens_per_minute
    }

    conditional {
      if ($raw_input|has:"output_tokens_per_minute") {
        var.update $next_output_rate {
          value = $input.output_tokens_per_minute
        }
      }
    }

    // Renaming to its own current name is fine, so the clash check
    // excludes this row rather than counting it as a duplicate.
    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $actor.account_id && $db.planner_workspace.name == $next_name && $db.planner_workspace.id != $input.workspace_id
      return = {type: "count"}
    } as $name_clash

    // --- One verdict, one log, one raise, on the MERGED values ---------
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
          value = "Give the plan a name. (E-VAL-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_name|strlen) > 80) {
        var.update $reject_code {
          value = "E-VAL-002"
        }

        var.update $reject_msg {
          value = "That name is too long — 80 characters at most. (E-VAL-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $next_end < $next_start) {
        var.update $reject_code {
          value = "E-PLN-002"
        }

        var.update $reject_msg {
          value = "The end date can't be before the start date. (E-PLN-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_input_rate < 0 || $next_output_rate < 0)) {
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
            step          : "update_workspace"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_workspace"
            entity_id     : $input.workspace_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.patch planner_workspace {
      field_name = "id"
      field_value = $input.workspace_id
      data = {
        name                    : $next_name
        planning_window_start   : $next_start
        planning_window_end     : $next_end
        input_tokens_per_minute : $next_input_rate
        output_tokens_per_minute: $next_output_rate
        updated_at              : "now"
      }
    } as $updated

    function.run "planner/workspace_counts" {
      input = {workspace_id: $input.workspace_id}
    } as $counts

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-3"
        step          : "update_workspace"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        correlation_id: $input.correlation_id
        message       : "Plan updated."
      }
    }
  }

  response = {
    workspace: $updated
    counts   : $counts
  }
}
