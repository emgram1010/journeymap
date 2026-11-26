// REPEAT-1 story 05 — Mark a whole DAY as reviewed: every open "needs review" mark on that day's slots is cleared and kept as history (who, when, how: "day"). Same rules as clearing one slot (684): a person only (AI refused with E-COP-025), another account's day is not found (planner/assert_timeline), an archived plan refuses. A day with no open marks answers 200 with cleared 0. The write is review/clear_marks, which queries the marks and patches each by its own id (a patch by a non-unique field touches only the first row), then this endpoint re-counts what is still open so the answer proves zero. Logged as plan.review_cleared with the count. Every input is passed to function.run explicitly.
query "timeline/{timeline_id}/review-clear" verb=POST {
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

    function.run "copilot/assert_person_only" {
      input = {user_id: $actor.user_id, account_id: $actor.account_id, step: "review_clear_day", entity_type: "planner_timeline", entity_id: $input.timeline_id}
    } as $_person_only

    function.run "planner/assert_timeline" {
      input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived   : $guard.workspace.is_archived
        feature       : "REPEAT-1"
        step          : "review_clear_day"
        entity_type   : "planner_timeline"
        entity_id     : $input.timeline_id
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        correlation_id: $input.correlation_id
      }
    }

    function.run "review/clear_marks" {
      input = {account_id: $actor.account_id, user_id: $actor.user_id, how: "day", planner_task_id: 0, timeline_id: $input.timeline_id}
    } as $cleared

    db.query planner_task {
      where = $db.planner_task.timeline_id == $input.timeline_id
      return = {type: "list"}
      output = ["id"]
    } as $day_slots

    var $slot_ids {
      value = [-1]
    }

    foreach ($day_slots) {
      each as $ds {
        array.push $slot_ids {
          value = $ds.id
        }
      }
    }

    db.query planner_task_review {
      where = $db.planner_task_review.planner_task_id in $slot_ids && $db.planner_task_review.account_id == $actor.account_id
      return = {type: "list"}
      output = ["id", "cleared_at"]
    } as $after

    var $still_open {
      value = 0
    }

    foreach ($after) {
      each as $a {
        var.update $still_open {
          value = $still_open + (($a.cleared_at == 0)|to_int)
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "REPEAT-1"
        step          : "plan.review_cleared"
        outcome       : "success"
        severity      : "info"
        error_code    : ""
        message       : "Needs-review marks cleared for a day."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_timeline"
        entity_id     : $input.timeline_id
        correlation_id: $input.correlation_id
        metadata      : {how: "day", cleared: $cleared.cleared, still_open: $still_open, workspace_id: $guard.workspace.id}
      }
    } as $_logged
  }

  response = {
    timeline_id: $input.timeline_id
    cleared    : $cleared.cleared
    still_open : $still_open
  }
}
