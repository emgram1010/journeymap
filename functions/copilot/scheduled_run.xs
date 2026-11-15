// COP-5 story 05 - one tick of scheduled copilot runs: the hourly task calls this with account_id 0 (every account that has a copilot); a test or a manual run passes one account. First it closes any run that has been "running" for over 30 minutes (marks it failed, E-COP-057, and releases its lock, so one dead run never blocks a business for good). Then it runs copilot/run_for_account for each copilot. It ALWAYS writes one event (COP-5 run_tick) with the counts, even when nothing ran - a task that writes nothing looks healthy.
function "copilot/scheduled_run" {
  input {
    int account_id?
    text trigger? filters=trim
  }

  stack {
    var $all {
      value = ($input.account_id == 0)
    }

    var $trigger {
      value = "schedule"
    }

    conditional {
      if ($input.trigger == "manual") {
        var.update $trigger {
          value = "manual"
        }
      }
    }

    var $now_ms {
      value = now|to_int
    }

    var $cutoff {
      value = $now_ms - 1800000
    }

    // -- Close runs that never finished --
    db.query copilot_run {
      where = $db.copilot_run.status == "running" && $db.copilot_run.started_at < $cutoff && (($all == true) || ($db.copilot_run.account_id == $input.account_id))
      return = {type: "list"}
      output = ["id", "account_id", "journey_architecture_id", "copilot_user_id"]
    } as $stale

    var $stale_count {
      value = $stale|count
    }

    foreach ($stale) {
      each as $s {
        var $stale_key {
          value = "stale::" ~ ($s.id|to_text)
        }

        db.patch copilot_run {
          field_name = "id"
          field_value = $s.id
          data = {
            status     : "failed"
            lock_key   : $stale_key
            finished_at: $now_ms
            reason     : "The copilot did not finish its scheduled run. Anything it did before stopping is in the activity log. (E-COP-057)"
          }
        } as $_stale_closed

        function.run "ops/log_event" {
          input = {
            feature       : "COP-5"
            step          : "run_failed"
            outcome       : "failure"
            severity      : "error"
            user_id       : $s.copilot_user_id
            account_id    : $s.account_id
            entity_type   : "copilot_run"
            entity_id     : $s.id
            correlation_id: ""
            error_code    : "E-COP-057"
            message       : "A scheduled copilot run did not finish within 30 minutes."
            duration_ms   : 0
            metadata      : {journey_architecture_id: $s.journey_architecture_id, stage: "stale"}
          }
        } as $_stale_logged
      }
    }

    // -- Every copilot (or the one account asked for) --
    db.query ai_identity {
      where = ($all == true) || ($db.ai_identity.account_id == $input.account_id)
      sort = {ai_identity.id: "asc"}
      return = {type: "list"}
      output = ["id", "account_id", "user_id"]
    } as $identities

    var $identity_count {
      value = $identities|count
    }

    var $accounts_on {
      value = 0
    }

    var $rows_written {
      value = 0
    }

    var $runs {
      value = 0
    }

    foreach ($identities) {
      each as $ident {
        function.run "copilot/run_for_account" {
          input = {account_id: $ident.account_id, copilot_user_id: $ident.user_id, trigger: $trigger}
        } as $ra

        var.update $accounts_on {
          value = $accounts_on + ($ra.enabled|to_int)
        }

        var.update $rows_written {
          value = $rows_written + $ra.rows_written
        }

        var.update $runs {
          value = $runs + $ra.runs
        }
      }
    }

    var $end_ms {
      value = now|to_int
    }

    var $took_ms {
      value = $end_ms - $now_ms
    }

    function.run "ops/log_event" {
      input = {
        feature       : "COP-5"
        step          : "run_tick"
        outcome       : "success"
        severity      : "info"
        user_id       : 0
        account_id    : 0
        entity_type   : ""
        entity_id     : 0
        correlation_id: ""
        error_code    : ""
        message       : "Scheduled copilot runs ticked."
        duration_ms   : $took_ms
        metadata      : {copilots: $identity_count, accounts_on: $accounts_on, rows_written: $rows_written, runs: $runs, stale_closed: $stale_count}
      }
    } as $_tick_logged
  }

  response = {copilots: $identity_count, accounts_on: $accounts_on, rows_written: $rows_written, runs: $runs, stale_closed: $stale_count}
}
