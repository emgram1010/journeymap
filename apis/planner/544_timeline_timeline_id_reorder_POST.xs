// PLN-7 (US-PLN-7-04) — Reorder a day by sending its task ids in the
// order you want them.
//
// IT MUST BE AN EXACT PERMUTATION — every current task, each exactly
// once, nothing else. Anything short of that is rejected and NOTHING
// is written. A partial reorder is worse than a refused one: the
// caller would believe it succeeded while the day silently lost or
// duplicated a task.
//
// The check is two numbers, no loops and no array-membership filter
// (`|contains:` is false for every array — CLAUDE.md):
//
//   a) the submitted count equals the timeline's task count, and
//   b) `WHERE timeline_id = X AND id IN (submitted)` matches that
//      same count.
//
// Together those catch every bad case. An extra or missing id fails
// (a). A duplicate fails (b): [A,A,B] has a count of 3 but matches
// only 2 distinct rows. A foreign id fails (b) too, which also means
// an id from another plan can never be reordered into this one.
// All three were confirmed live, each leaving the order untouched.
//
// Applying the order is a plain counter — position 1..n patched by id
// — with no branching inside the loop.
query "timeline/{timeline_id}/reorder" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int timeline_id filters=min:1
    json task_ids
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_timeline" {
      input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-7"
        step       : "reorder_timeline"
        entity_type: "planner_timeline"
        entity_id  : $input.timeline_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    var $workspace_id {
      value = $guard.workspace.id
    }

    db.query planner_task {
      where = $db.planner_task.timeline_id == $input.timeline_id
      return = {type: "count"}
    } as $current_count

    var $submitted_count {
      value = $input.task_ids|count
    }

    db.query planner_task {
      where = $db.planner_task.timeline_id == $input.timeline_id && $db.planner_task.id in $input.task_ids
      return = {type: "count"}
    } as $matched_count

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($submitted_count != $current_count || $matched_count != $current_count) {
        var.update $reject_code {
          value = "E-PLN-016"
        }

        var.update $reject_msg {
          value = "That new order doesn't match this day's tasks, so nothing was changed. (E-PLN-016)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-7"
            step          : "reorder_timeline"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_timeline"
            entity_id     : $input.timeline_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Reorder refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $pos {
      value = 0
    }

    db.transaction {
      stack {
        foreach ($input.task_ids) {
          each as $tid {
            var.update $pos {
              value = $pos + 1
            }

            db.patch planner_task {
              field_name = "id"
              field_value = $tid
              data = {seq: $pos, updated_at: "now"}
            } as $patched
          }
        }
      }
    }

    function.run "planner/derive_tasks" {
      input = {workspace_id: $workspace_id, timeline_id: $input.timeline_id}
    } as $view

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-7"
        step          : "reorder_timeline"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_timeline"
        entity_id     : $input.timeline_id
        correlation_id: $input.correlation_id
        message       : "Day reordered."
      }
    }
  }

  response = {tasks: $view.tasks}
}
