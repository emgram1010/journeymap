// TW-1 (US-TW-1-02) — Set or replace a job's one time window (upsert).
// Same codes and rules as src/planner/timeWindowModel.ts; this is the
// authority (D-6).
//
// DATES ARRIVE AS TEXT: an omitted optional `date` input does not exist at
// all and crashes on read (CLAUDE.md), so they are text, regex-checked.
// ORDER IS COMPARED AS DIGITS: "YYYY-MM-DD HH:MM" stripped to 12 digits is
// a plain int, so no reliance on string `<` semantics.
//
// RACE: two overlapping first saves both see "no window" and both add;
// the unique index on work_item_id refuses the second (a transaction does
// not serialize requests — CLAUDE.md). That loser is logged `failure` and
// told to reload, never silently merged.
//
// AFTER GO-LIVE (D-7): the change is saved, logged with the published item
// refs it affects, and the response says the day needs Publish to live
// again. The performer reads only the frozen snapshot (D-23).
query "work-item/{work_item_id}/time-window" verb=PUT {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
    text start_date? filters=trim
    text start_time? filters=trim
    text end_date? filters=trim
    text end_time? filters=trim
    text note? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    conditional {
      if ($belongs == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "TW-1"
            step          : "time_window.set"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            error_code    : "E-TW-004"
            message       : "Time window refused: job not in this account."
          }
        }
      }
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "That job isn't available any more. (E-TW-004)"
    }

    db.get planner_workspace {
      field_name = "id"
      field_value = $job.workspace_id
    } as $ws

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($job.status == "cancelled") {
        var.update $reject_code {
          value = "E-TW-005"
        }

        var.update $reject_msg {
          value = "This job is cancelled, so its time window can't be changed. (E-TW-005)"
        }
      }
    }

    var $date_re {
      value = "/^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/"
    }

    var $time_re {
      value = "/^([01][0-9]|2[0-3]):[0-5][0-9]$/"
    }

    var $dates_ok {
      value = ($date_re|regex_matches:$input.start_date) && ($date_re|regex_matches:$input.end_date)
    }

    var $times_ok {
      value = ($time_re|regex_matches:$input.start_time) && ($time_re|regex_matches:$input.end_time)
    }

    conditional {
      if ($reject_code == "" && $dates_ok == false) {
        var.update $reject_code {
          value = "E-TW-001"
        }

        var.update $reject_msg {
          value = "Enter a start and end date, and times as two digits each, like 09:00. (E-TW-001)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $times_ok == false) {
        var.update $reject_code {
          value = "E-TW-001"
        }

        var.update $reject_msg {
          value = "Enter a start and end date, and times as two digits each, like 09:00. (E-TW-001)"
        }
      }
    }

    var $start_composed {
      value = $input.start_date ~ " " ~ $input.start_time
    }

    var $end_composed {
      value = $input.end_date ~ " " ~ $input.end_time
    }

    var $start_n {
      value = ("/[^0-9]/"|regex_replace:"":$start_composed)|to_int
    }

    var $end_n {
      value = ("/[^0-9]/"|regex_replace:"":$end_composed)|to_int
    }

    conditional {
      if ($reject_code == "" && $end_n <= $start_n) {
        var.update $reject_code {
          value = "E-TW-002"
        }

        var.update $reject_msg {
          value = "The window has to end after it starts. (E-TW-002)"
        }
      }
    }

    // D-5 / Q-3 default: refuse only when there is NO overlap with the plan.
    var $plan_start_txt {
      value = ($ws.planning_window_start ?? "")|to_text
    }

    var $plan_end_txt {
      value = ($ws.planning_window_end ?? "")|to_text
    }

    var $plan_start_n {
      value = ("/[^0-9]/"|regex_replace:"":$plan_start_txt)|to_int
    }

    var $plan_end_n {
      value = ("/[^0-9]/"|regex_replace:"":$plan_end_txt)|to_int
    }

    var $start_date_n {
      value = ("/[^0-9]/"|regex_replace:"":$input.start_date)|to_int
    }

    var $end_date_n {
      value = ("/[^0-9]/"|regex_replace:"":$input.end_date)|to_int
    }

    var $has_plan_window {
      value = ($plan_start_n > 0 && $plan_end_n > 0)
    }

    var $outside_msg {
      value = "This time window falls completely outside the plan (" ~ $plan_start_txt ~ " to " ~ $plan_end_txt ~ "). Move it so at least part of it is inside. (E-TW-003)"
    }

    conditional {
      if ($reject_code == "" && $has_plan_window && ($end_date_n < $plan_start_n || $start_date_n > $plan_end_n)) {
        var.update $reject_code {
          value = "E-TW-003"
        }

        var.update $reject_msg {
          value = $outside_msg
        }
      }
    }

    var $note_len {
      value = $input.note|strlen
    }

    conditional {
      if ($reject_code == "" && $note_len > 200) {
        var.update $reject_code {
          value = "E-TW-006"
        }

        var.update $reject_msg {
          value = "Keep the time window's note to 200 characters or fewer. (E-TW-006)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "TW-1"
            step          : "time_window.set"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Time window refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    db.query work_item_time_window {
      where = $db.work_item_time_window.work_item_id == $input.work_item_id
      return = {type: "single"}
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    var $before {
      value = null
    }

    conditional {
      if ($existing_id != 0) {
        var.update $before {
          value = {start_date: $existing.start_date, start_time: $existing.start_time, end_date: $existing.end_date, end_time: $existing.end_time, note: $existing.note}
        }
      }
    }

    var $after {
      value = {start_date: $input.start_date, start_time: $input.start_time, end_date: $input.end_date, end_time: $input.end_time, note: $input.note}
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
                    db.add work_item_time_window {
                      data = {
                        created_at     : "now"
                        updated_at     : "now"
                        work_item_id   : $input.work_item_id
                        start_date     : $input.start_date
                        start_time     : $input.start_time
                        end_date       : $input.end_date
                        end_time       : $input.end_time
                        note           : $input.note
                        constraint_type: "soft"
                        updated_by     : $actor.user_id
                      }
                    } as $_added
                  }

                  else {
                    db.patch work_item_time_window {
                      field_name = "id"
                      field_value = $existing_id
                      data = {
                        updated_at: "now"
                        start_date: $input.start_date
                        start_time: $input.start_time
                        end_date  : $input.end_date
                        end_time  : $input.end_time
                        note      : $input.note
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
            feature       : "TW-1"
            step          : "time_window.set"
            outcome       : "failure"
            severity      : "warn"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            message       : "Time window save failed (likely two saves at once)."
          }
        }
      }
    }

    precondition ($tx_failed == false) {
      error_type = "inputerror"
      error = "Someone else just changed this time window. Reload and try again."
    }

    function.run "jobs/time_window_live_refs" {
      input = {work_item_id: $input.work_item_id}
    } as $live

    function.run "ops/log_event" {
      input = {
        feature       : "TW-1"
        step          : "time_window.set"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "work_item"
        entity_id     : $input.work_item_id
        correlation_id: $input.correlation_id
        message       : "Time window saved."
        metadata      : {before: $before, after: $after, created: ($existing_id == 0), live: $live.live}
      }
    }

    conditional {
      if ($live.live) {
        function.run "ops/log_event" {
          input = {
            feature       : "TW-1"
            step          : "time_window.changed_after_live"
            outcome       : "success"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            message       : "Time window changed on a live day; needs Publish to live again."
            metadata      : {item_refs: $live.item_refs, timeline_ids: $live.published_timeline_ids, before: $before, after: $after}
          }
        }
      }
    }
  }

  response = {
    work_item_id      : $input.work_item_id
    time_window       : $after
    created           : ($existing_id == 0)
    needs_republish   : $live.live
    published_item_refs: $live.item_refs
  }
}
