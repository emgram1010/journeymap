// TW-1 (US-TW-1-02) — Remove a job's time window. Removes only the
// window row; the job and its scheduled steps are untouched. A job with
// no window succeeds quietly (deleted: false). Cancelled jobs refuse
// (E-TW-005): their window is history.
query "work-item/{work_item_id}/time-window" verb=DELETE {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
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
            step          : "time_window.cleared"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            error_code    : "E-TW-004"
            message       : "Time window removal refused: job not in this account."
          }
        }
      }
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "That job isn't available any more. (E-TW-004)"
    }

    var $cancelled {
      value = ($job.status == "cancelled")
    }

    conditional {
      if ($cancelled) {
        function.run "ops/log_event" {
          input = {
            feature       : "TW-1"
            step          : "time_window.cleared"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            error_code    : "E-TW-005"
            message       : "Time window removal refused: job cancelled."
          }
        }
      }
    }

    precondition ($cancelled == false) {
      error_type = "inputerror"
      error = "This job is cancelled, so its time window can't be changed. (E-TW-005)"
    }

    db.query work_item_time_window {
      where = $db.work_item_time_window.work_item_id == $input.work_item_id
      return = {type: "single"}
    } as $row

    var $row_id {
      value = $row|get:"id":0
    }

    var $before {
      value = null
    }

    conditional {
      if ($row_id != 0) {
        var.update $before {
          value = {start_date: $row.start_date, start_time: $row.start_time, end_date: $row.end_date, end_time: $row.end_time, note: $row.note}
        }

        db.del work_item_time_window {
          field_name = "id"
          field_value = $row_id
        }
      }
    }

    function.run "jobs/time_window_live_refs" {
      input = {work_item_id: $input.work_item_id}
    } as $live

    var $was_live {
      value = ($live.live && $row_id != 0)
    }

    function.run "ops/log_event" {
      input = {
        feature       : "TW-1"
        step          : "time_window.cleared"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "work_item"
        entity_id     : $input.work_item_id
        correlation_id: $input.correlation_id
        message       : "Time window removed."
        metadata      : {before: $before, deleted: ($row_id != 0), live: $was_live}
      }
    }

    conditional {
      if ($was_live) {
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
            message       : "Time window removed on a live day; needs Publish to live again."
            metadata      : {item_refs: $live.item_refs, timeline_ids: $live.published_timeline_ids, before: $before, after: null}
          }
        }
      }
    }
  }

  response = {
    work_item_id       : $input.work_item_id
    deleted            : ($row_id != 0)
    needs_republish    : $was_live
    published_item_refs: $live.item_refs
  }
}
