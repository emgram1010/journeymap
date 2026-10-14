// PLN-6 (US-PLN-6-03, US-PLN-6-04) — Change a timeline's start time,
// or move it to another agent and/or date.
//
// MOVING REFUSES, IT NEVER SWAPS OR MERGES. If the target agent already
// has a timeline on the target date, the move is rejected and nothing
// changes — the same rule the shipped `handleMoveTimelineCell` follows.
// Merging two days of someone's work because of one drag would be very
// hard to undo and nobody asked for it.
//
// MOVING ONTO ITS OWN CELL IS A NO-OP SUCCESS, not a duplicate-key
// error. A drag that ends where it started should do nothing quietly.
// That is why the clash query excludes this timeline's own id.
//
// CHANGING start_time WRITES NO TASK ROWS. Task start times are derived
// from the timeline's start (`recomputeTimelineTaskTimes` in the UI,
// hydrated reads in PLN-8), so shifting a day by 90 minutes shifts
// every task with a single-column write here. Storing per-task times
// would mean rewriting every task and risking drift.
//
// TASK OVERRIDES SURVIVE A MOVE. A task carrying an explicit
// `assignee_agent_id` keeps it: the override exists precisely to say
// "this one is someone else's regardless of whose day it sits in".
// This endpoint writes no task rows at all, so that holds by
// construction — confirmed live, a task row was byte-identical after
// two moves of its timeline.
//
// `status` is read-only (PLN-6 Non-Goals) — sending one is rejected.
query "timeline/{timeline_id}" verb=PATCH {
  api_group = "planner"
  auth = "user"

  input {
    int timeline_id filters=min:1
    int agent_id?
    date planned_date?
    text start_time? filters=trim
    text status? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_timeline" {
      input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
    } as $guard

    var $existing {
      value = $guard.timeline
    }

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-6"
        step       : "update_timeline"
        entity_type: "planner_timeline"
        entity_id  : $input.timeline_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $next_start {
      value = $existing.start_time
    }

    conditional {
      if ($raw_input|has:"start_time") {
        var.update $next_start {
          value = $input.start_time
        }
      }
    }

    var $next_agent {
      value = $existing.agent_id
    }

    conditional {
      if ($raw_input|has:"agent_id") {
        var.update $next_agent {
          value = $input.agent_id
        }
      }
    }

    var $next_date {
      value = $existing.planned_date
    }

    conditional {
      if ($raw_input|has:"planned_date") {
        var.update $next_date {
          value = $input.planned_date
        }
      }
    }

    // The target agent must be in this plan, not merely this account.
    function.run "planner/assert_agent" {
      input = {account_id: $actor.account_id, agent_id: $next_agent}
    } as $agent_guard

    function.run "planner/assert_same_workspace" {
      input = {workspace_id_a: $existing.workspace_id, workspace_id_b: $agent_guard.agent.workspace_id}
    }

    // Is the target cell taken by a DIFFERENT timeline? Moving onto its
    // own cell finds only itself, which is not a clash.
    db.query planner_timeline {
      where = $db.planner_timeline.agent_id == $next_agent && $db.planner_timeline.planned_date == $next_date && $db.planner_timeline.id != $input.timeline_id
      return = {type: "count"}
    } as $cell_clash

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
      if ($reject_code == "" && ("/^([01][0-9]|2[0-3]):[0-5][0-9]$/"|regex_matches:$next_start) == false) {
        var.update $reject_code {
          value = "E-PLN-010"
        }

        var.update $reject_msg {
          value = "Enter a start time as HH:MM, between 00:00 and 23:59. (E-PLN-010)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $cell_clash > 0) {
        var.update $reject_code {
          value = "E-PLN-012"
        }

        var.update $reject_msg {
          value = "That agent already has a timeline on that date. (E-PLN-012)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-6"
            step          : "update_timeline"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_timeline"
            entity_id     : $input.timeline_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Timeline update refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.patch planner_timeline {
      field_name = "id"
      field_value = $input.timeline_id
      data = {
        agent_id    : $next_agent
        planned_date: $next_date
        start_time  : $next_start
        updated_at  : "now"
      }
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-6"
        step          : "update_timeline"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_timeline"
        entity_id     : $input.timeline_id
        correlation_id: $input.correlation_id
        message       : "Timeline updated."
      }
    }
  }

  response = {timeline: $updated}
}
