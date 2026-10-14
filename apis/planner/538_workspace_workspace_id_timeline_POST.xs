// PLN-6 (US-PLN-6-01) — Start a day's plan for one agent.
//
// CREATING A TIMELINE THAT ALREADY EXISTS IS NOT AN ERROR. The UI's
// "start a timeline here" is a click on an empty cell, and two clicks
// should not produce two timelines or a scary message — the second one
// just opens the existing day. So this returns the existing row with
// `created: false`. The unique index on (agent_id, planned_date) is
// still what makes a duplicate impossible.
//
// ⚠️ AND IT HOLDS UNDER A RACE. The "does one already exist?" query
// followed by an insert is check-then-act: two simultaneous clicks
// both see nothing and both insert, and the unique index rejects the
// loser. Confirmed live — two parallel creates returned one `200` and
// one **`500 "Duplicate record detected"`**, a raw database string in
// front of a user who did nothing wrong.
// So the insert is wrapped: on a conflict the row is re-read and
// returned as `created: false`, which is the same answer the slower
// click would have got a moment later. Re-tested after the fix: both
// callers got `200` with the same timeline id, one `created: true`
// and one `created: false`, and exactly one row existed.
//
// OUT-OF-WINDOW DATES ARE ALLOWED. A date outside the plan's window is
// created and flagged `out_of_window: true` for the UI to mark. People
// plan outside their own window all the time, and refusing it would be
// the tool arguing with the user about their own dates.
//
// `status` IS READ-ONLY. Publishing is on hold (PLN-6 Non-Goals) and
// only LIVE-1 may ever move it. Sending one is rejected rather than
// ignored, so a client that thinks it published something finds out it
// did not.
query "workspace/{workspace_id}/timeline" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    int agent_id filters=min:1
    date planned_date
    text start_time? filters=trim
    text status? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_workspace" {
      input = {account_id: $actor.account_id, workspace_id: $input.workspace_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-6"
        step       : "create_timeline"
        entity_type: "planner_workspace"
        entity_id  : $input.workspace_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    function.run "planner/assert_agent" {
      input = {account_id: $actor.account_id, agent_id: $input.agent_id}
    } as $agent_guard

    // The agent must be in THIS plan, not merely in this account.
    function.run "planner/assert_same_workspace" {
      input = {workspace_id_a: $input.workspace_id, workspace_id_b: $agent_guard.agent.workspace_id}
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $start_time {
      value = "08:00"
    }

    conditional {
      if ($raw_input|has:"start_time") {
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
      if ($raw_input|has:"status") {
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
