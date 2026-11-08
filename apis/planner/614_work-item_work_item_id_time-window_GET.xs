// TW-1 (US-TW-1-02) — A job's time window, or {time_window: null}.
// Cancelled jobs still return theirs: it is history (E-TW-005 only
// blocks edits).
query "work-item/{work_item_id}/time-window" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
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

    precondition ($belongs) {
      error_type = "notfound"
      error = "That job isn't available any more. (E-TW-004)"
    }

    db.query work_item_time_window {
      where = $db.work_item_time_window.work_item_id == $input.work_item_id
      return = {type: "single"}
    } as $row

    var $row_id {
      value = $row|get:"id":0
    }

    var $tw {
      value = null
    }

    conditional {
      if ($row_id != 0) {
        var.update $tw {
          value = {start_date: $row.start_date, start_time: $row.start_time, end_date: $row.end_date, end_time: $row.end_time, note: $row.note}
        }
      }
    }
  }

  response = {
    work_item_id: $input.work_item_id
    time_window : $tw
  }
}
