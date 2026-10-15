// SCHED-1 (US-SCHED-1-05) — Change how long a scheduled job step is
// allowed to take, for THIS job only.
//
// EXPECTED MINUTES ARE NEVER TOUCHED. The map's estimate lives in the
// pinned version and is read-only from here; a tweak only moves
// `planner_task.duration_minutes`. That separation is what lets VAR-1
// later say "this took longer than the map says" — if a tweak
// overwrote the expectation there would be nothing left to compare
// against, and the plan would always look perfectly estimated.
// Confirmed live: after tweaking a step from 999 to 120 minutes, the
// version still reported 999, and a reset restored it exactly.
//
// A REASON IS OPTIONAL BUT MUST BE REAL. It is either `other` or a key
// the job actually has in its attributes, so a reason can never point
// at a detail that was never recorded.
//
// ⚠️ STALE-WRITE DETECTION IS BY VALUE, NOT BY TIMESTAMP, and that is
// forced. GOV-1's `guards/assert_fresh` compares `updated_at`, but
// every planner table declares `updated_at` as a **date** — day
// granularity. Two people editing the same slot ten minutes apart
// produce an identical `updated_at`, so the generic guard would wave
// the second one through while reporting success. Instead the caller
// may send `expected_duration_minutes`: what they believed the value
// was when they opened the form. If the row has moved on, the write
// is refused. This is narrower than a timestamp check — it only fires
// when the field being changed actually moved — but it is honest,
// whereas comparing a date here would not be.
query "planner_task/{planner_task_id}/tweak" verb=PATCH {
  api_group = "planner"
  auth = "user"

  input {
    int planner_task_id filters=min:1
    int duration_minutes?
    text tweak_reason? filters=trim
    int expected_duration_minutes?
    bool reset_to_expected?
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
        feature    : "SCHED-1"
        step       : "tweak_duration"
        entity_type: "planner_task"
        entity_id  : $input.planner_task_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    // Which job step is this slot covering, if any?
    db.query planner_task_work_task {
      where = $db.planner_task_work_task.planner_task_id == $input.planner_task_id
      return = {type: "list"}
    } as $links

    var $is_linked {
      value = (($links|count) > 0)
    }

    var $expected {
      value = 0
    }

    var $attribute_keys {
      value = []
    }

    conditional {
      if ($is_linked == true) {
        var $link {
          value = $links|first
        }

        db.get work_task {
          field_name = "id"
          field_value = $link.work_task_id
        } as $wt

        db.get work_item {
          field_name = "id"
          field_value = $wt.work_item_id
        } as $job

        db.get journey_map_version {
          field_name = "id"
          field_value = $job.journey_map_version_id
        } as $version

        foreach ($version.snapshot.cells) {
          each as $c {
            conditional {
              if ($c.stage_key == $wt.stage_key && $c.lens_key == $wt.lens_key) {
                var.update $expected {
                  value = ($c.duration_minutes ?? 0)
                }
              }
            }
          }
        }

        foreach (($job.attributes ?? {})|keys) {
          each as $k {
            array.push $attribute_keys {
              value = $k
            }
          }
        }
      }
    }

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    var $next_duration {
      value = $slot.duration_minutes
    }

    conditional {
      if ($raw_input|has:"duration_minutes") {
        var.update $next_duration {
          value = $input.duration_minutes
        }
      }
    }

    // Reset puts it back to the map's estimate and clears the reason.
    conditional {
      if ($input.reset_to_expected == true && $expected > 0) {
        var.update $next_duration {
          value = $expected
        }
      }
    }

    var $next_reason {
      value = $slot.tweak_reason
    }

    conditional {
      if ($raw_input|has:"tweak_reason") {
        var.update $next_reason {
          value = $input.tweak_reason
        }
      }
    }

    conditional {
      if ($input.reset_to_expected == true) {
        var.update $next_reason {
          value = ""
        }
      }
    }

    // Is the reason one this job could actually explain?
    var $reason_ok {
      value = ($next_reason == "" || $next_reason == "other")
    }

    foreach ($attribute_keys) {
      each as $k {
        conditional {
          if ($k == $next_reason) {
            var.update $reason_ok {
              value = true
            }
          }
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
      if (($raw_input|has:"expected_duration_minutes") && $input.expected_duration_minutes != $slot.duration_minutes) {
        var.update $reject_code {
          value = "E-SCHED-003"
        }

        var.update $reject_msg {
          value = "Someone else changed this. Reload to see the latest. (E-SCHED-003)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($next_duration < 1 || $next_duration > 1440)) {
        var.update $reject_code {
          value = "E-SCHED-002"
        }

        var.update $reject_msg {
          value = "Enter a duration between 1 and 1,440 minutes. (E-SCHED-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $reason_ok == false) {
        var.update $reject_code {
          value = "E-SCHED-005"
        }

        var.update $reject_msg {
          value = "Pick a reason from the list or choose 'Other'. (E-SCHED-005)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "SCHED-1"
            step          : "tweak_duration"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_task"
            entity_id     : $input.planner_task_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Duration tweak refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $old_duration {
      value = $slot.duration_minutes
    }

    db.patch planner_task {
      field_name = "id"
      field_value = $input.planner_task_id
      data = {duration_minutes: $next_duration, tweak_reason: $next_reason, updated_at: "now"}
    } as $updated

    function.run "ops/log_event" {
      input = {
        feature       : "SCHED-1"
        step          : "tweak_duration"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "planner_task"
        entity_id     : $input.planner_task_id
        correlation_id: $input.correlation_id
        message       : "Scheduled duration changed."
        metadata      : {
          expected_minutes: $expected
          old_minutes     : $old_duration
          new_minutes     : $next_duration
          reason          : $next_reason
        }
      }
    }
  }

  response = {
    planner_task     : $updated
    expected_minutes : $expected
    scheduled_minutes: $next_duration
    is_tweaked       : ($is_linked == true && $next_duration != $expected)
    tweak_reason     : $next_reason
  }
}
