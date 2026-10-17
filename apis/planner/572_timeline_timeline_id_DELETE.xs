// PLN-6 (US-PLN-6-05) + P3A-1 (US-P3A-1-04) — Delete one day from a
// plan. Created 2026-10-16 on the founder's explicit approval of the
// two non-destructive deletes; task and plan delete remain held.
//
// THE DAY GOES, THE WORK STAYS. Every task on the timeline is returned
// to the backlog first (planner/return_tasks_to_backlog, which keeps
// the tasks' relative order and appends them after whatever is already
// in the backlog), and only the empty timeline row is removed.
//
// A PUBLISHED DAY CANNOT BE DELETED AT ALL (US-P3A-1-04). LIVE-1's
// publication froze that day and handed it to someone; deleting the
// timeline would leave the frozen snapshot and every activity_log
// event pointing at a row that no longer exists. Checked here, before
// the cascade runs, because the cascade itself takes no view on status.
query "timeline/{timeline_id}" verb=DELETE {
  api_group = "planner"
  auth = "user"

  input {
    int timeline_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_timeline" {
      input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
    } as $guard

    var $timeline {
      value = $guard.timeline
    }

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-6"
        step       : "delete_timeline"
        entity_type: "planner_timeline"
        entity_id  : $input.timeline_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($timeline.status == "published") {
        var.update $reject_code {
          value = "E-P3A-003"
        }

        var.update $reject_msg {
          value = "This timeline is live. It can't be deleted. (E-P3A-003)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-6"
            step          : "delete_timeline"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_timeline"
            entity_id     : $input.timeline_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Timeline delete refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    function.run "planner/delete_timeline_cascade" {
      input = {workspace_id: $timeline.workspace_id, timeline_id: $input.timeline_id}
    } as $removed

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-6"
        step          : "delete_timeline"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_timeline"
        entity_id     : $input.timeline_id
        correlation_id: $input.correlation_id
        message       : "Timeline deleted; its tasks returned to the backlog."
        metadata      : {
          workspace_id  : $timeline.workspace_id
          agent_id      : $timeline.agent_id
          planned_date  : $timeline.planned_date
          tasks_returned: $removed.tasks_returned
        }
      }
    }
  }

  response = {
    deleted_timeline_id: $input.timeline_id
    tasks_returned     : $removed.tasks_returned
    moved_ids          : $removed.moved_ids
  }
}
