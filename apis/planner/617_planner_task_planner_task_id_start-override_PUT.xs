// SCHED-2 (US-SCHED-2-02) — Set or replace a scheduled slot's manual start
// time (upsert). The rule that USES it lives in planner/start_minutes
// ("pin + flow"); this endpoint only stores it.
//
// A BACKLOG SLOT IS REFUSED (E-SCHED-010): it has no day, so there is no
// computed time to override yet.
//
// RACE: two overlapping first saves both see "no override" and both add;
// the unique index on planner_task_id refuses the second (a transaction does
// not serialize requests — CLAUDE.md). The loser is logged `failure` and
// told to reload, never silently merged.
//
// AFTER GO-LIVE: the change is saved and logged to plan_change_log as
// `moved` via live/log_plan_change (which does nothing on a draft day), and
// the response says the day needs Publish to live again — the performer
// reads only the frozen snapshot (D-23).
query "planner_task/{planner_task_id}/start-override" verb=PUT {
  api_group = "planner"
  auth = "user"

  input {
    int planner_task_id filters=min:1
    text start_time? filters=trim
    text reason? filters=trim
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
        step       : "start_override.set"
        entity_type: "planner_task"
        entity_id  : $input.planner_task_id
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
      if ($slot.timeline_id == 0) {
        var.update $reject_code {
          value = "E-SCHED-010"
        }

        var.update $reject_msg {
          value = "Put this on someone's day first — a step in Unscheduled has no start time to change. (E-SCHED-010)"
        }
      }
    }

    var $time_re {
      value = "/^([01][0-9]|2[0-3]):[0-5][0-9]$/"
    }

    var $time_ok {
      value = $time_re|regex_matches:$input.start_time
    }

    conditional {
      if ($reject_code == "" && $time_ok == false) {
        var.update $reject_code {
          value = "E-SCHED-009"
        }

        var.update $reject_msg {
          value = "Enter the start time as two digits each, like 09:00. (E-SCHED-009)"
        }
      }
    }

    var $reason_len {
      value = $input.reason|strlen
    }

    conditional {
      if ($reject_code == "" && $reason_len > 200) {
        var.update $reject_code {
          value = "E-SCHED-011"
        }

        var.update $reject_msg {
          value = "Keep the reason to 200 characters or fewer. (E-SCHED-011)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "SCHED-2"
            step          : "start_override.set"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_task"
            entity_id     : $input.planner_task_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Start time refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
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

    conditional {
      if ($existing_id != 0) {
        var.update $before_time {
          value = $existing.start_time
        }
      }
    }

    var $tx_failed {
      value = false
    }

    try_catch {
      try {
        group {
          stack {
            db.transaction {
              stack {
                conditional {
                  if ($existing_id == 0) {
                    db.add planner_task_start_override {
                      data = {
                        created_at     : "now"
                        updated_at     : "now"
                        planner_task_id: $input.planner_task_id
                        start_time     : $input.start_time
                        reason         : $input.reason
                        updated_by     : $actor.user_id
                      }
                    } as $_added
                  }

                  else {
                    db.patch planner_task_start_override {
                      field_name = "id"
                      field_value = $existing_id
                      data = {
                        updated_at: "now"
                        start_time: $input.start_time
                        reason    : $input.reason
                        updated_by: $actor.user_id
                      }
                    } as $_patched
                  }
                }
              }
            }
          }
        }
      }

      catch {
        var.update $tx_failed {
          value = true
        }
      }
    }

    conditional {
      if ($tx_failed) {
        function.run "ops/log_event" {
          input = {
            feature       : "SCHED-2"
            step          : "start_override.set"
            outcome       : "failure"
            severity      : "warn"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_task"
            entity_id     : $input.planner_task_id
            correlation_id: $input.correlation_id
            message       : "Start time save failed (likely two saves at once)."
          }
        }
      }
    }

    precondition ($tx_failed == false) {
      error_type = "inputerror"
      error = "Someone else just changed this start time. Reload and try again."
    }

    db.get planner_timeline {
      field_name = "id"
      field_value = $slot.timeline_id
    } as $timeline

    var $is_live {
      value = ($timeline.status == "published")
    }

    var $changed {
      value = ($before_time != $input.start_time)
    }

    // Does nothing on a draft day (live/log_plan_change's own rule).
    conditional {
      if ($changed) {
        function.run "live/log_plan_change" {
          input = {
            timeline_id: $slot.timeline_id
            item_ref   : ("pt-" ~ ($input.planner_task_id|to_text))
            change_type: "moved"
            before     : {start_override: $before_time}
            after      : {start_override: $input.start_time}
            changed_by : $actor.user_id
          }
        } as $plan_change
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "SCHED-2"
        step          : "start_override.set"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_task"
        entity_id     : $input.planner_task_id
        correlation_id: $input.correlation_id
        message       : "Start time set."
        metadata      : {before: $before_time, after: $input.start_time, created: ($existing_id == 0), live: $is_live}
      }
    }
  }

  response = {
    planner_task_id: $input.planner_task_id
    start_override : $input.start_time
    reason         : $input.reason
    created        : ($existing_id == 0)
    needs_republish: ($is_live && $changed)
  }
}
