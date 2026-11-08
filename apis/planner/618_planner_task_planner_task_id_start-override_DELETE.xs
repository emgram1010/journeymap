// SCHED-2 (US-SCHED-2-02) — Clear a slot's manual start time, so it goes
// back to the computed one (planner/start_minutes with no pin).
//
// Deletes the override row only; the slot itself is never touched.
// IDEMPOTENT: clearing a slot with no override succeeds and changes nothing
// (`cleared: false`), so a double-click is not an error.
//
// AFTER GO-LIVE: logged to plan_change_log as `moved` (live/log_plan_change
// does nothing on a draft day) and the response says Publish to live again.
query "planner_task/{planner_task_id}/start-override" verb=DELETE {
  api_group = "planner"
  auth = "user"

  input {
    int planner_task_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_task" {
      input = {account_id: $actor.account_id, task_id: $input.planner_task_id}
    } as $guard

    var $slot {
      value = $guard.task
    }

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "SCHED-2"
        step       : "start_override.clear"
        entity_type: "planner_task"
        entity_id  : $input.planner_task_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    db.query planner_task_start_override {
      where = $db.planner_task_start_override.planner_task_id == $input.planner_task_id
      return = {type: "single"}
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    var $before_time {
      value = ""
    }

    var $is_live {
      value = false
    }

    conditional {
      if ($existing_id != 0) {
        var.update $before_time {
          value = $existing.start_time
        }

        db.del planner_task_start_override {
          field_name = "id"
          field_value = $existing_id
        }

        // A backlog slot (timeline 0) has no day to log against.
        conditional {
          if ($slot.timeline_id != 0) {
            db.get planner_timeline {
              field_name = "id"
              field_value = $slot.timeline_id
            } as $timeline

            var.update $is_live {
              value = ($timeline.status == "published")
            }

            function.run "live/log_plan_change" {
              input = {
                timeline_id: $slot.timeline_id
                item_ref   : ("pt-" ~ ($input.planner_task_id|to_text))
                change_type: "moved"
                before     : {start_override: $before_time}
                after      : {start_override: ""}
                changed_by : $actor.user_id
              }
            } as $plan_change
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "SCHED-2"
        step          : "start_override.clear"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_task"
        entity_id     : $input.planner_task_id
        correlation_id: $input.correlation_id
        message       : "Start time cleared."
        metadata      : {before: $before_time, cleared: ($existing_id != 0), live: $is_live}
      }
    }
  }

  response = {
    planner_task_id: $input.planner_task_id
    cleared        : ($existing_id != 0)
    needs_republish: $is_live
  }
}
