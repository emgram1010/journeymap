// REPEAT-1 story 06 — The periods of a "repeat for several periods": for each, its dates, its own free name, and whether it was already made. Read-only. The app then makes each period with its OWN request (POST workspace/{id}/repeat), so each is its own all-or-nothing write and a failure never undoes an earlier period; this function only says what the periods are. Every period is copied from the SAME source (the app always asks for the source plan), never from the copy before it. Period n starts at the first start date + (n-1) x the source's length, computed from the first date each time, never by adding to a previous result. Dates and names come from the shared rules (repeat/period_dates, repeat/free_name), so this can never disagree with the single-period preview. The limit is 1 to 8 periods (E-REPEAT-010). A refusal is returned as reject_code / reject_msg, not thrown, so the caller can log it first. A period that already exists (plan_repeat is unique on source + start date) is flagged `exists` with the plan it made, so the app skips it and names it. No conditional inside the loop: every value is arithmetic, a lookup or an expression on the current period.
function "repeat/list_periods" {
  input {
    int account_id
    int workspace_id
    text start_date? filters=trim
    int periods?
  }

  stack {
    function.run "planner/assert_workspace" {
      input = {account_id: $input.account_id, workspace_id: $input.workspace_id}
    } as $guard

    var $ws {
      value = $guard.workspace
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($input.periods < 1 || $input.periods > 8) {
        var.update $reject_code {
          value = "E-REPEAT-010"
        }

        var.update $reject_msg {
          value = "You can repeat a plan for 1 to 8 periods at a time. (E-REPEAT-010)"
        }
      }
    }

    function.run "repeat/period_dates" {
      input = {src_start: $ws.planning_window_start, src_end: $ws.planning_window_end, start_date: $input.start_date}
    } as $first

    conditional {
      if ($reject_code == "" && $first.reject_code != "") {
        var.update $reject_code {
          value = $first.reject_code
        }

        var.update $reject_msg {
          value = $first.reject_msg
        }
      }
    }

    var $count {
      value = (($reject_code == "") ? $input.periods : 0)
    }

    var $first_ms {
      value = $first.new_start|to_timestamp
    }

    var $step_ms {
      value = $first.length_days * 86400000
    }

    var $periods {
      value = []
    }

    var $i {
      value = 0
    }

    var $n_val {
      value = 1
    }

    var $start_ms {
      value = 0
    }

    var $start_text {
      value = ""
    }

    var $exists_id {
      value = 0
    }

    var $is_made {
      value = false
    }

    while ($i < $count) {
      each {
        var.update $n_val {
          value = $i + 1
        }

        var.update $start_ms {
          value = $first_ms + ($i * $step_ms)
        }

        var.update $start_text {
          value = $start_ms|format_timestamp:"Y-m-d":"UTC"
        }

        function.run "repeat/period_dates" {
          input = {src_start: $ws.planning_window_start, src_end: $ws.planning_window_end, start_date: $start_text}
        } as $pd

        function.run "repeat/free_name" {
          input = {account_id: $input.account_id, source_name: $ws.name, start_date: $pd.new_start}
        } as $pn

        db.query plan_repeat {
          where = $db.plan_repeat.source_workspace_id == $input.workspace_id && $db.plan_repeat.new_start_date == $pd.new_start
          return = {type: "single"}
        } as $made

        var.update $exists_id {
          value = $made|get:"new_workspace_id":0
        }

        var.update $is_made {
          value = ($exists_id != 0)
        }

        array.push $periods {
          value = {n: $n_val, start_date: $pd.new_start, end_date: $pd.new_end, shift_days: $pd.shift_days, weekdays_align: $pd.weekdays_align, name: $pn.name, exists: $is_made, existing_workspace_id: $exists_id}
        }

        var.update $i {
          value = $i + 1
        }
      }
    }

    var $source {
      value = {id: $ws.id, name: $ws.name, start_date: $ws.planning_window_start, end_date: $ws.planning_window_end, length_days: $first.length_days}
    }
  }

  response = {
    reject_code: $reject_code
    reject_msg : $reject_msg
    source     : $source
    periods    : $periods
  }
}
