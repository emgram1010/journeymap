// VAR-1 (US-VAR-1-03, MVP slice) — One job's variance report.
//
// READ-ONLY, same as the function it calls. Nobody reports variance
// (the epic's own first sentence) — every figure here is derived from
// the activity log, the pinned version and the published snapshot, on
// the fly, every time this is called. Nothing is ever written.
//
// `data_quality_warning` IS LOGGED, NOT JUST RETURNED — a job whose
// tasks keep coming back "done with no start" is something the
// product manager should be able to find on the Health page without
// having to open this report first.
query "variance/work_item/{work_item_id}" verb=GET {
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

    precondition ($belongs) {
      error_type = "notfound"
      error = "Job not found"
    }

    var $start_ms {
      value = now|to_int
    }

    function.run "variance/task_report" {
      input = {work_item_id: $input.work_item_id}
    } as $report

    var $end_ms {
      value = now|to_int
    }

    var $duration_ms {
      value = $end_ms - $start_ms
    }

    // Tally warnings by code for the Health page — one event per
    // report, not one per row.
    var $warning_tally {
      value = {}
    }

    var $wkey {
      value = ""
    }

    var $existing {
      value = 0
    }

    foreach ($report.tasks) {
      each as $t {
        foreach ($t.warnings) {
          each as $w {
            var.update $existing {
              value = $warning_tally|get:$w:0
            }

            var.update $warning_tally {
              value = $warning_tally|set:$w:($existing + 1)
            }
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "VAR-1"
        step          : "compute_report"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "work_item"
        entity_id     : $input.work_item_id
        correlation_id: $input.correlation_id
        duration_ms   : $duration_ms
        message       : "Variance report computed."
        metadata      : {task_count: $report.task_count, outlier_count: $report.outlier_count, warning_count: $report.warning_count}
      }
    }

    conditional {
      if ($report.warning_count > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "VAR-1"
            step          : "data_quality_warning"
            outcome       : "rejected"
            severity      : "warn"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            message       : "Variance report found data-quality warnings."
            metadata      : {by_code: $warning_tally}
          }
        }
      }
    }
  }

  response = {
    work_item_id : $report.work_item_id
    task_count   : $report.task_count
    outlier_count: $report.outlier_count
    warning_count: $report.warning_count
    tasks        : $report.tasks
  }
}
