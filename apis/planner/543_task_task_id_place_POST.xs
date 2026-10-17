// PLN-7 (US-PLN-7-03) — Drag a task somewhere: another day, another
// agent, or back to the backlog.
//
// `timeline_id: 0` (or omitted) means the backlog. Everything about the
// move itself lives in planner/place_task; this endpoint's job is
// permission, tenancy and the index rule.
//
// AN INDEX PAST THE END CLAMPS, A NEGATIVE ONE IS REJECTED. Dropping
// below the last row is an ordinary gesture and should land at the end.
// A negative index is not a gesture, it is a bug in the caller, and
// silently treating it as 0 would hide that.
query "task/{task_id}/place" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int task_id filters=min:1
    int timeline_id?
    int index?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_task" {
      input = {account_id: $actor.account_id, task_id: $input.task_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "PLN-7"
        step       : "place_task"
        entity_type: "planner_task"
        entity_id  : $input.task_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    var $workspace_id {
      value = $guard.workspace.id
    }

    // Destination must be a timeline of THIS plan, or the backlog.
    conditional {
      if ($input.timeline_id != 0) {
        function.run "planner/assert_timeline" {
          input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
        } as $tl_guard

        function.run "planner/assert_same_workspace" {
          input = {workspace_id_a: $workspace_id, workspace_id_b: $tl_guard.timeline.workspace_id}
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
      if ($input.index < 0) {
        var.update $reject_code {
          value = "E-PLN-015"
        }

        var.update $reject_msg {
          value = "That position isn't valid. (E-PLN-015)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "PLN-7"
            step          : "place_task"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_task"
            entity_id     : $input.task_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Task move refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    function.run "planner/place_task" {
      input = {
        workspace_id    : $workspace_id
        task_id         : $input.task_id
        dest_timeline_id: $input.timeline_id
        index           : $input.index
      }
    } as $placed

    function.run "planner/derive_tasks" {
      input = {workspace_id: $workspace_id, timeline_id: $input.timeline_id}
    } as $dest_view

    function.run "ops/log_event" {
      input = {
        feature       : "PLN-7"
        step          : "place_task"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_task"
        entity_id     : $input.task_id
        correlation_id: $input.correlation_id
        message       : "Task moved."
        metadata      : {from: $placed.source_timeline_id, to: $input.timeline_id, index: $placed.clamped_index}
      }
    }
  }

  response = {
    moved            : $placed
    destination_tasks: $dest_view.tasks
  }
}
