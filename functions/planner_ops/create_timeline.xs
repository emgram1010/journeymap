// COP-5 story 01 (extraction) — THE ONE PLACE a day's plan is started for
// one person: PLN-6's rule (US-PLN-6-01), moved out of endpoint 538
// (`POST workspace/{workspace_id}/timeline`) so the copilot's
// `plan_start_day` tool starts a day through exactly the same checks,
// writes and logging as a person's click. A copy would drift.
//
// Everything 538's header says still holds here: creating a day that
// already exists is NOT an error (the existing row comes back with
// `created: false`); it holds under a race (the insert is wrapped, and on
// a unique-index conflict the row is re-read); a date outside the plan's
// window is allowed and flagged `out_of_window: true`; `status` is
// read-only (sending one is refused with E-PLN-011).
//
// `actor` is planner/resolve_actor's result: {user_id, account_id, role}.
// A function cannot see what the caller sent, so the two "was this field
// sent?" tests are explicit flags: `has_start_time` (false = default
// 08:00) and `has_status` (true = refuse, E-PLN-011).
// `planned_date` is TEXT "YYYY-MM-DD" here (538's input is `date`): the
// caller validates the shape; it is compared with the `date` column in the
// where clause and stored as given.
function "planner_ops/create_timeline" {
  input {
    json actor
    int workspace_id filters=min:1
    int agent_id filters=min:1
    text planned_date filters=trim
    text start_time? filters=trim
    bool has_start_time?
    bool has_status?
    text correlation_id? filters=trim
  }

  stack {
    var $actor {
      value = $input.actor
    }

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived   : $guard.workspace.is_archived
        feature       : "PLN-6"
        step          : "create_timeline"
        entity_type   : "planner_workspace"
        entity_id     : $input.workspace_id
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        correlation_id: $input.correlation_id
      }
    }

    function.run "planner/assert_agent" {
      input = {account_id: $actor.account_id, agent_id: $input.agent_id}
    } as $agent_guard

    // The agent must be in THIS plan, not merely in this account.
    function.run "planner/assert_same_workspace" {
      input = {workspace_id_a: $input.workspace_id, workspace_id_b: $agent_guard.agent.workspace_id}
    }

    // Handoff 4-A rule 2 (COP-5 story 06): no new day for a switched-off copilot's column (E-COP-059).
    function.run "planner_ops/assert_agent_assignable" {
      input = {agent_id: $input.agent_id, actor_user_id: $actor.user_id, account_id: $actor.account_id, step: "start_day"}
    } as $_assignable

    var $start_time {
      value = "08:00"
    }

    conditional {
      if ($input.has_start_time == true) {
        var.update $start_time {
          value = $input.start_time
        }
      }
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($input.has_status == true) {
        var.update $reject_code {
          value = "E-PLN-011"
        }

        var.update $reject_msg {
          value = "A timeline's status is set by publishing, not here. (E-PLN-011)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ("/^([01][0-9]|2[0-3]):[0-5][0-9]$/"|regex_matches:$start_time) == false) {
        var.update $reject_code {
          value = "E-PLN-010"
        }

        var.update $reject_msg {
          value = "Enter a start time as HH:MM, between 00:00 and 23:59. (E-PLN-010)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-6"
            step          : "create_timeline"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_timeline"
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Timeline create refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.query planner_timeline {
      where = $db.planner_timeline.agent_id == $input.agent_id && $db.planner_timeline.planned_date == $input.planned_date
      return = {type: "list"}
    } as $already

    var $created {
      value = false
    }

    var $timeline {
      value = null
    }

    conditional {
      if (($already|count) > 0) {
        var.update $timeline {
          value = $already|first
        }
      }

      else {
        try_catch {
          try {
            db.add planner_timeline {
              data = {
                workspace_id: $input.workspace_id
                agent_id    : $input.agent_id
                planned_date: $input.planned_date
                start_time  : $start_time
                status      : "draft"
              }
            } as $added

            var.update $timeline {
              value = $added
            }

            var.update $created {
              value = true
            }
          }

          catch {
            // Lost the race. Whoever won created the identical day, so
            // return theirs — the same answer this call would have got
            // a moment later.
            debug.log {
              value = "timeline for this agent and date was created concurrently; returning the existing one"
            }
          }
        }
      }
    }

    // Re-read when the insert did not happen, which covers both the
    // race above and any other reason the row already existed.
    conditional {
      if ($created == false && $timeline == null) {
        db.query planner_timeline {
          where = $db.planner_timeline.agent_id == $input.agent_id && $db.planner_timeline.planned_date == $input.planned_date
          return = {type: "list"}
        } as $after_race

        var.update $timeline {
          value = $after_race|first
        }
      }
    }

    conditional {
      if ($created == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-6"
            step          : "create_timeline"
            outcome       : "success"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_timeline"
            entity_id     : $timeline.id
            correlation_id: $input.correlation_id
            message       : "Timeline created."
          }
        }
      }
    }

    var $out_of_window {
      value = ($input.planned_date < $guard.workspace.planning_window_start || $input.planned_date > $guard.workspace.planning_window_end)
    }
  }

  response = {
    timeline     : $timeline
    created      : $created
    out_of_window: $out_of_window
  }
}
